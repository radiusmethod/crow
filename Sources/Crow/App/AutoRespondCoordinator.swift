import Foundation
import CrowCore
import CrowTerminal

/// Handles auto-respond to PR status transitions: when CrowConfig opts in
/// for a transition kind, find the session's managed terminal and inject a
/// short prompt asking Claude Code to investigate and address the issue.
///
/// Crow does not fetch review bodies or CI logs itself — the prompt asks
/// Claude to do that via `gh`/`glab`. This keeps Crow simple and avoids new
/// API scopes / rate-limit pressure.
///
/// If a transition's toggle is off, or the session has no managed terminal
/// surface, the coordinator silently skips. The caller still fires the
/// macOS notification regardless, so the user can act manually.
@MainActor
final class AutoRespondCoordinator {
    private let appState: AppState
    /// Closure that returns the current `AutoRespondSettings`. Closure rather
    /// than a stored value so updates from Settings UI take effect on the
    /// next transition without explicit wiring.
    private let settingsProvider: () -> AutoRespondSettings

    init(appState: AppState, settingsProvider: @escaping () -> AutoRespondSettings) {
        self.appState = appState
        self.settingsProvider = settingsProvider
    }

    func handle(_ transitions: [PRStatusTransition]) {
        let cfg = settingsProvider()
        for t in transitions {
            switch t.kind {
            case .changesRequested where cfg.respondToChangesRequested:
                dispatch(t)
            case .checksFailing where cfg.respondToFailedChecks:
                dispatch(t)
            default:
                continue
            }
        }
    }

    private func dispatch(_ transition: PRStatusTransition) {
        let terminals = appState.terminals(for: transition.sessionID)
        guard let terminal = terminals.first(where: { $0.isManaged }) else {
            NSLog("[AutoRespond] Skipping %@ for session %@: no managed terminal",
                  transition.kind.rawValue, transition.sessionID.uuidString)
            return
        }
        guard TerminalManager.shared.existingSurface(for: terminal.id) != nil else {
            NSLog("[AutoRespond] Skipping %@ for session %@: terminal surface not initialized",
                  transition.kind.rawValue, transition.sessionID.uuidString)
            return
        }

        let provider = appState.sessions.first(where: { $0.id == transition.sessionID })?.provider ?? .github
        let prompt = AutoRespondPrompts.build(for: transition, provider: provider)
        NSLog("[AutoRespond] Sending %@ prompt to terminal %@ (%d chars)",
              transition.kind.rawValue, terminal.id.uuidString, prompt.count)
        TerminalManager.shared.send(id: terminal.id, text: prompt)
    }
}

/// Builds the deterministic prompt text injected into a session's managed
/// terminal when an auto-respond transition fires. Each prompt:
///   1. States what just happened (and links to the PR).
///   2. Tells Claude how to fetch the relevant context via `gh`/`glab`.
///   3. Asks Claude to make local changes and push to update the PR.
///
/// Always ends with a trailing newline so the terminal submits it as Enter.
enum AutoRespondPrompts {
    static func build(for transition: PRStatusTransition, provider: Provider) -> String {
        let prRef = transition.prNumber.map { "PR #\($0)" } ?? "the PR"
        let cli = provider == .gitlab ? "glab" : "gh"

        switch transition.kind {
        case .changesRequested:
            let fetchHint: String
            if provider == .gitlab {
                fetchHint = "Run `glab mr view \(transition.prURL) --comments` to read the review feedback."
            } else {
                fetchHint = "Run `gh pr view \(transition.prURL) --json reviews,comments` (and `gh api repos/{owner}/{repo}/pulls/\(transition.prNumber.map(String.init) ?? "<number>")/comments` for inline comments) to read the full review feedback."
            }
            return """
            Crow detected a 'changes requested' review on \(prRef) (\(transition.prURL)).
            \(fetchHint) Address every reviewer comment in code, commit the fix, and push so the PR updates. If a comment is unclear or you disagree, leave a reply explaining your reasoning instead of changing the code.

            """

        case .checksFailing:
            let failedSummary: String
            if transition.failedCheckNames.isEmpty {
                failedSummary = ""
            } else {
                let names = transition.failedCheckNames.prefix(5).joined(separator: ", ")
                let extra = transition.failedCheckNames.count > 5 ? " (+\(transition.failedCheckNames.count - 5) more)" : ""
                failedSummary = " Failing checks: \(names)\(extra)."
            }
            let logHint: String
            if provider == .gitlab {
                logHint = "Run `glab ci view` / `glab ci trace` on the failing pipeline to read the logs."
            } else {
                logHint = "Run `\(cli) pr checks \(transition.prURL)` to list the failing checks, then `\(cli) run view --log-failed <run-id>` to read the failure output."
            }
            return """
            Crow detected failing CI checks on \(prRef) (\(transition.prURL)).\(failedSummary)
            \(logHint) Identify the root cause, fix it locally, run the relevant tests, then commit and push so CI re-runs.

            """
        }
    }
}
