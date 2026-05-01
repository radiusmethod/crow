import CrowCore
import CrowTerminal
import Foundation

/// Routes per-terminal operations to the right backend based on the
/// SessionTerminal's `backend` discriminator.
///
/// Centralizes the dispatch so call sites stay readable and the policy
/// change ("which backend handles this terminal?") is in one place. Each
/// method either delegates to `TerminalManager.shared` (the legacy Ghostty
/// path) or to `TmuxBackend.shared` (the new path).
@MainActor
public enum TerminalRouter {

    /// Send text to a terminal. For `.tmux` terminals the path is the
    /// load-buffer + paste-buffer route (PROD #3) — works for arbitrary
    /// payloads; `send-keys -l` would fail on >10KB strings.
    public static func send(_ terminal: SessionTerminal, text: String) {
        switch terminal.backend {
        case .ghostty:
            TerminalManager.shared.send(id: terminal.id, text: text)
        case .tmux:
            do {
                try TmuxBackend.shared.sendText(id: terminal.id, text: text)
            } catch {
                NSLog("[TerminalRouter] tmux sendText failed for \(terminal.id): \(error)")
            }
        }
    }

    /// Destroy the terminal's backing surface or tmux window.
    public static func destroy(_ terminal: SessionTerminal) {
        switch terminal.backend {
        case .ghostty:
            TerminalManager.shared.destroy(id: terminal.id)
        case .tmux:
            TmuxBackend.shared.destroyTerminal(id: terminal.id)
        }
    }

    /// Mark the terminal as one whose readiness should be tracked.
    /// Ghostty path uses `TerminalManager.trackReadiness`; tmux path's
    /// readiness is wired automatically when the binding registers.
    public static func trackReadiness(for terminal: SessionTerminal) {
        switch terminal.backend {
        case .ghostty:
            TerminalManager.shared.trackReadiness(for: terminal.id)
        case .tmux:
            // No-op: tmux backend's startReadinessWatch fires on register.
            break
        }
    }

    /// Whether the terminal's backing surface (Ghostty) or window
    /// (tmux) is alive enough to receive a `send`. Callers that want to
    /// fail-soft when the user hasn't materialized the terminal yet — e.g.
    /// auto-respond and the session-card quick action buttons — gate on
    /// this instead of relying on the underlying send to throw.
    public static func canSend(_ terminal: SessionTerminal) -> Bool {
        switch terminal.backend {
        case .ghostty:
            return TerminalManager.shared.existingSurface(for: terminal.id) != nil
        case .tmux:
            return TmuxBackend.shared.isRegistered(id: terminal.id)
        }
    }
}
