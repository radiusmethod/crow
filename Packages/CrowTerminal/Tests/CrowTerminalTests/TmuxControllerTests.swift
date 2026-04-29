import Foundation
import Testing
@testable import CrowTerminal

/// Locate a tmux binary on the host, in priority order. Top-level so the
/// `.enabled(if:)` trait below can reference it without the macro hitting
/// a circular-reference resolution.
private let discoveredTmuxBinary: String? = {
    let candidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}()

/// Integration tests for `TmuxController`. Skipped automatically when
/// `tmux` is not installed (e.g. CI without the brew formula); the unit
/// behavior is exercised via the bundled-resources tests above.
@Suite("TmuxController integration", .enabled(if: discoveredTmuxBinary != nil))
struct TmuxControllerTests {

    private func makeController() -> TmuxController {
        let id = UUID().uuidString.prefix(8).lowercased()
        let socket = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("crow-test-\(id).sock")
        return TmuxController(
            tmuxBinary: discoveredTmuxBinary!,
            socketPath: socket,
            sessionName: "crow-test-\(id)"
        )
    }

    @Test func createsAndKillsSession() throws {
        let ctrl = makeController()
        defer {
            ctrl.killServer()
            try? FileManager.default.removeItem(atPath: ctrl.socketPath)
        }
        try ctrl.newSessionDetached(command: "/bin/sh -c 'sleep 60'")
        #expect(ctrl.hasSession())
    }

    @Test func newWindowReturnsIndex() throws {
        let ctrl = makeController()
        defer {
            ctrl.killServer()
            try? FileManager.default.removeItem(atPath: ctrl.socketPath)
        }
        try ctrl.newSessionDetached(command: "/bin/sh -c 'sleep 60'")
        let idx = try ctrl.newWindow(command: "/bin/sh -c 'sleep 60'")
        // Default base-index is 0; second window is at 1.
        #expect(idx >= 1)
        let indices = try ctrl.listWindowIndices()
        #expect(indices.contains(idx))
    }

    @Test func loadBufferAndPaste() throws {
        let ctrl = makeController()
        defer {
            ctrl.killServer()
            try? FileManager.default.removeItem(atPath: ctrl.socketPath)
        }
        // /bin/cat echoes its stdin so we can verify round-trip via capture.
        try ctrl.newSessionDetached(command: "/bin/cat")

        let bufName = "crow-test-buf"
        let payload = Data("MARKER-\(UUID().uuidString)".utf8)
        try ctrl.loadBufferFromStdin(name: bufName, data: payload)
        try ctrl.pasteBuffer(name: bufName, target: "\(ctrl.sessionName):0")
        ctrl.deleteBuffer(name: bufName)
        // No assertion on pane content — that's a Phase 3 §3 measurement,
        // not a unit test. Here we just verify the calls don't throw.
    }

    @Test func cliFailureSurfacesError() throws {
        let ctrl = makeController()
        defer {
            ctrl.killServer()
            try? FileManager.default.removeItem(atPath: ctrl.socketPath)
        }
        // Ask for a session that doesn't exist.
        #expect(throws: TmuxError.self) {
            try ctrl.run(["has-session", "-t", "nonexistent-\(UUID().uuidString)"])
        }
    }

    @Test func versionStringIsParsable() {
        guard let version = TmuxController.versionString(tmuxBinary: discoveredTmuxBinary!) else {
            Issue.record("tmux -V returned nil unexpectedly")
            return
        }
        // "tmux 3.6a" or similar.
        #expect(version.hasPrefix("tmux "))
    }
}
