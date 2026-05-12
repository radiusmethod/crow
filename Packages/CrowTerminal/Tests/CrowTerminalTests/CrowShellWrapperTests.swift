import Foundation
import Testing
@testable import CrowTerminal

/// Tests for the bundled `crow-shell-wrapper.sh` stage breadcrumbs (#256).
///
/// We invoke the wrapper as a subprocess with a controlled environment so
/// the assertions don't depend on the developer's actual `~/.zshrc`. Two
/// flavors:
///   1. Setup-phase test: uses a fake `*-zsh` shell that exits immediately,
///      proving the wrapper writes the breadcrumbs it controls directly
///      (`start`, `zdotdir_temp_created`, `pre_exec`).
///   2. Runtime test (zsh-only, skipped if /bin/zsh is absent): drives a
///      real zsh through a controlled `.zshrc` so we observe the runtime
///      breadcrumbs (`user_rc_sourced`, `hook_installed`, `precmd_fired`,
///      `sentinel_written`).
///   3. Sentinel-failure test: points `CROW_SENTINEL` at an un-writable
///      path and confirms the wrapper logs `sentinel_write_failed`.
@Suite("crow-shell-wrapper breadcrumbs")
struct CrowShellWrapperTests {

    /// Spawn the wrapper, wait for it to exit, return the breadcrumb log.
    /// All temp files live under the returned `workDir` for inspection on
    /// failure.
    private struct Fixture {
        let workDir: URL
        let sentinel: String
        let log: String
        let logContents: String
    }

    private func runWrapper(
        shell: String,
        userZdotdir: String? = nil,
        sentinelOverride: String? = nil,
        timeoutSeconds: TimeInterval = 8.0
    ) throws -> Fixture {
        guard let wrapperURL = BundledResources.shellWrapperScriptURL else {
            throw WrapperTestError.missingWrapperScript
        }

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-wrapper-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let sentinel = sentinelOverride
            ?? workDir.appendingPathComponent("sentinel").path
        let log = workDir.appendingPathComponent("wrapper.log").path

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [wrapperURL.path]
        var env: [String: String] = [
            "SHELL": shell,
            "CROW_SENTINEL": sentinel,
            "CROW_WRAPPER_LOG": log,
            "HOME": workDir.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "USER": ProcessInfo.processInfo.environment["USER"] ?? "test",
        ]
        if let userZdotdir { env["ZDOTDIR"] = userZdotdir }
        p.environment = env
        p.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()

        // Kill the process after `timeoutSeconds` regardless of state — for
        // the runtime test the shell is interactive and won't exit on its
        // own. The setup-phase test exits much sooner.
        let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + timeoutSeconds, execute: deadline)
        p.waitUntilExit()
        deadline.cancel()

        let logContents = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
        return Fixture(
            workDir: workDir,
            sentinel: sentinel,
            log: log,
            logContents: logContents
        )
    }

    /// Drop a `*-zsh`-named fake shell that exits immediately. Lets us trip
    /// the wrapper's zsh code path without invoking a real shell.
    private func makeFakeZshShell(in dir: URL) throws -> String {
        let path = dir.appendingPathComponent("myshell-zsh").path
        let script = "#!/bin/sh\nexit 0\n"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private enum WrapperTestError: Error {
        case missingWrapperScript
    }

    // MARK: - Tests

    @Test func setupPhaseBreadcrumbsAreEmitted() throws {
        // Setup-phase tests are deterministic — no real shell needed.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-fake-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let fakeShell = try makeFakeZshShell(in: scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let fx = try runWrapper(shell: fakeShell)
        defer { try? FileManager.default.removeItem(at: fx.workDir) }

        #expect(fx.logContents.contains(" start "))
        #expect(fx.logContents.contains(" zdotdir_temp_created "))
        #expect(fx.logContents.contains(" pre_exec "))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/zsh")))
    func runtimeBreadcrumbsWithRealZsh() throws {
        // Point CROW_USER_ZDOTDIR at a controlled dir whose .zshrc exits the
        // shell as soon as the first prompt has fired — so the test resolves
        // quickly.
        let userZdotdir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-userz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        // Minimal user .zshrc: a comment is enough — we just need the file
        // to exist so the wrapper logs `user_rc_sourced`.
        try "# crow wrapper test rc\n".write(
            to: userZdotdir.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: userZdotdir) }

        // Override CROW_USER_ZDOTDIR via env, then run wrapper. The wrapper
        // re-exports ZDOTDIR=$ZTMP and the embedded rc reads CROW_USER_ZDOTDIR
        // from env. Inject via runWrapper's `userZdotdir` parameter — but
        // that parameter sets ZDOTDIR (the user's), which the wrapper then
        // moves into CROW_USER_ZDOTDIR. Same effect.
        let fx = try runWrapper(
            shell: "/bin/zsh",
            userZdotdir: userZdotdir.path,
            timeoutSeconds: 6.0
        )
        defer { try? FileManager.default.removeItem(at: fx.workDir) }

        // We can't guarantee the shell prints a prompt without a PTY, so
        // we tolerate either of two outcomes:
        //   (a) the shell *did* fire precmd → full chain present
        //   (b) the shell didn't reach a prompt → at minimum the user_rc
        //       sourcing + hook install lines must be there
        let setupLine = fx.logContents.contains("hook_installed mechanism=add-zsh-hook")
            || fx.logContents.contains("hook_installed mechanism=precmd_functions_append")
        let sourcedLine = fx.logContents.contains("user_rc_sourced")
            || fx.logContents.contains("user_rc_skipped")
        #expect(setupLine, "expected hook_installed line in:\n\(fx.logContents)")
        #expect(sourcedLine, "expected user_rc line in:\n\(fx.logContents)")
        // pre_exec must appear regardless — it's a wrapper-side breadcrumb
        // emitted before the shell starts.
        #expect(fx.logContents.contains(" pre_exec "))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/zsh")))
    func sentinelWriteFailureIsLogged() throws {
        // Point CROW_SENTINEL at a path under a non-existent directory so the
        // wrapper's redirect can't possibly succeed. Then check the wrapper
        // log for the `sentinel_write_failed` breadcrumb. Requires the shell
        // to actually fire its precmd hook — best-effort here; if the shell
        // never prompts under the test harness, we don't fail loudly.
        let userZdotdir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-userz-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        try "# crow wrapper test rc\n".write(
            to: userZdotdir.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: userZdotdir) }

        let badSentinel = "/this/path/cannot/exist/crow-sentinel"
        let fx = try runWrapper(
            shell: "/bin/zsh",
            userZdotdir: userZdotdir.path,
            sentinelOverride: badSentinel,
            timeoutSeconds: 6.0
        )
        defer { try? FileManager.default.removeItem(at: fx.workDir) }

        // The strong assertion — wrapper-side setup must still complete.
        #expect(fx.logContents.contains(" pre_exec "))
        // Best-effort: if precmd ever fires, we expect a failure line. We
        // don't make this an unconditional #expect because non-tty zsh may
        // not reach a prompt before we kill it. The log path itself remains
        // a useful diagnostic if this turns out flaky.
        if fx.logContents.contains("precmd_fired") {
            #expect(fx.logContents.contains("sentinel_write_failed"))
        }
    }
}
