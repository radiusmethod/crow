import Foundation
import Testing
@testable import CrowTerminal

/// Policy tests for the conservative orphan-window reaper (#408): reap a
/// cockpit window only when NO live terminal references it AND it is sitting at
/// a bare login shell. Pure over `shouldReapWindow`, so no tmux needed.
@Suite("Orphan cockpit window reaper policy (#408)")
struct OrphanWindowReaperTests {

    @Test func reapsUnboundBareShell() {
        #expect(TmuxBackend.shouldReapWindow(index: 3, command: "zsh", keep: []))
        #expect(TmuxBackend.shouldReapWindow(index: 3, command: "-zsh", keep: []))
        #expect(TmuxBackend.shouldReapWindow(index: 3, command: "bash", keep: []))
        #expect(TmuxBackend.shouldReapWindow(index: 3, command: "sh", keep: []))
    }

    @Test func keepsBoundWindowEvenWhenBareShell() {
        // A terminal references it (e.g. the agent exited and the user is now at
        // the shell) — must be preserved.
        #expect(!TmuxBackend.shouldReapWindow(index: 3, command: "zsh", keep: [3]))
    }

    @Test func keepsWindowRunningAProcess() {
        // Anything that isn't a bare login shell is left alone.
        #expect(!TmuxBackend.shouldReapWindow(index: 4, command: "claude", keep: []))
        #expect(!TmuxBackend.shouldReapWindow(index: 4, command: "node", keep: []))
        #expect(!TmuxBackend.shouldReapWindow(index: 4, command: "codex", keep: []))
        #expect(!TmuxBackend.shouldReapWindow(index: 4, command: "tail", keep: []))  // session anchor
    }
}
