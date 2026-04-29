import Foundation

/// Thin wrapper around the `tmux` CLI.
///
/// Owns the (binary, socket, session-name) tuple and exposes typed methods
/// for the subset of tmux commands the production code actually uses.
/// Every public method shells out via `Process` — there is no long-lived
/// connection here. For paste-buffer staging, `loadBufferFromStdin` writes
/// payload bytes through a pipe to avoid ARG_MAX-derived `command too long`
/// errors that bite `send-keys -l` for >10KB strings (Phase 3 §3 finding).
///
/// All methods are blocking until the spawned tmux process exits.
public struct TmuxController: Sendable {
    public let tmuxBinary: String
    public let socketPath: String
    public let sessionName: String

    public init(tmuxBinary: String, socketPath: String, sessionName: String) {
        self.tmuxBinary = tmuxBinary
        self.socketPath = socketPath
        self.sessionName = sessionName
    }

    // MARK: - Generic invocation

    /// Run `tmux -S <socket> <args...>`. Returns stdout on exit-0,
    /// throws on non-zero exit with stdout/stderr captured.
    @discardableResult
    public func run(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmuxBinary)
        p.arguments = ["-S", socketPath] + args
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        p.waitUntilExit()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outString = String(data: stdoutData, encoding: .utf8) ?? ""
        let errString = String(data: stderrData, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw TmuxError.cliFailed(
                args: args,
                status: p.terminationStatus,
                stdout: outString,
                stderr: errString
            )
        }
        return outString
    }

    // MARK: - Server / session lifecycle

    public func killServer() {
        _ = try? run(["kill-server"])
    }

    /// `tmux new-session -d -s <name>` with optional config file (`-f`)
    /// and per-session env overrides (`-e KEY=VAL`).
    public func newSessionDetached(
        configPath: String? = nil,
        env: [String: String] = [:],
        command: String? = nil
    ) throws {
        var args: [String] = []
        if let configPath { args.append(contentsOf: ["-f", configPath]) }
        // Note: -f is a SERVER option, not a new-session option, so it
        // must come before "new-session" via the run() prepend. We pass
        // it through args here; run() will assemble correctly because
        // run() prepends `-S socket` only.
        args.append(contentsOf: ["new-session", "-d", "-s", sessionName])
        for (k, v) in env { args.append(contentsOf: ["-e", "\(k)=\(v)"]) }
        if let command { args.append(contentsOf: ["--", command]) }
        try run(args)
    }

    public func hasSession() -> Bool {
        ((try? run(["has-session", "-t", sessionName])) != nil)
    }

    public func listWindowIndices() throws -> [Int] {
        let out = try run(["list-windows", "-t", sessionName, "-F", "#{window_index}"])
        return out.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - Windows

    public func newWindow(
        name: String? = nil,
        env: [String: String] = [:],
        command: String? = nil
    ) throws -> Int {
        var args = ["new-window", "-P", "-F", "#{window_index}", "-t", sessionName]
        if let name { args.append(contentsOf: ["-n", name]) }
        for (k, v) in env { args.append(contentsOf: ["-e", "\(k)=\(v)"]) }
        if let command { args.append(command) }
        let out = try run(args)
        guard let idx = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw TmuxError.cliFailed(
                args: args,
                status: 0,
                stdout: out,
                stderr: "could not parse window index"
            )
        }
        return idx
    }

    public func selectWindow(index: Int) throws {
        try run(["select-window", "-t", "\(sessionName):\(index)"])
    }

    public func killWindow(index: Int) {
        _ = try? run(["kill-window", "-t", "\(sessionName):\(index)"])
    }

    // MARK: - Input routing (paste buffer path; see spec §7)

    /// Stage `data` into a named tmux buffer via stdin. Avoids the
    /// ARG_MAX-derived `command too long` error that hits `send-keys -l`
    /// for large payloads (~10KB+ in our measurements).
    public func loadBufferFromStdin(name: String, data: Data) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmuxBinary)
        p.arguments = ["-S", socketPath, "load-buffer", "-b", name, "-"]
        let stdin = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardError = stderr
        try p.run()
        try stdin.fileHandleForWriting.write(contentsOf: data)
        try stdin.fileHandleForWriting.close()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let errString = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw TmuxError.cliFailed(
                args: ["load-buffer", "-b", name, "-"],
                status: p.terminationStatus,
                stdout: "",
                stderr: errString
            )
        }
    }

    public func pasteBuffer(name: String, target: String) throws {
        try run(["paste-buffer", "-b", name, "-t", target])
    }

    public func deleteBuffer(name: String) {
        _ = try? run(["delete-buffer", "-b", name])
    }

    // MARK: - Diagnostic

    public static func versionString(tmuxBinary: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmuxBinary)
        p.arguments = ["-V"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum TmuxError: Error, CustomStringConvertible {
    case cliFailed(args: [String], status: Int32, stdout: String, stderr: String)

    public var description: String {
        switch self {
        case let .cliFailed(args, status, stdout, stderr):
            let argString = args.joined(separator: " ")
            let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return "tmux \(argString) → exit \(status); stderr=\(trimmedErr); stdout=\(trimmedOut)"
        }
    }
}
