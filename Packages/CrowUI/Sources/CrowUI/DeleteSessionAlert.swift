import SwiftUI
import CrowCore

// MARK: - Shared Delete Session Alert

/// View modifier that attaches a delete-session confirmation alert.
/// Used by both SessionListView (sidebar context menu) and SessionDetailView (header button).
struct DeleteSessionAlert: ViewModifier {
    @Binding var sessionToDelete: Session?
    let appState: AppState

    func body(content: Content) -> some View {
        content.alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button(buttonLabel, role: .destructive) {
                if let session = sessionToDelete {
                    Task {
                        do {
                            try await appState.onDeleteSession?(session.id)
                        } catch {
                            NSLog("Failed to delete session \(session.name): \(error)")
                        }
                    }
                    sessionToDelete = nil
                }
            }
        } message: {
            Text(messageText)
        }
    }

    private var buttonLabel: String {
        guard let session = sessionToDelete else { return "Delete" }
        let wts = appState.worktrees(for: session.id)
        let hasRealWorktrees = wts.contains { !$0.isMainRepoCheckout }
        return DeleteSessionMessageBuilder.buttonLabel(hasRealWorktrees: hasRealWorktrees)
    }

    private var messageText: String {
        guard let session = sessionToDelete else { return "" }
        let wts = appState.worktrees(for: session.id)
        let realWorktrees = wts.filter { !$0.isMainRepoCheckout }
        let mainCheckouts = wts.filter { $0.isMainRepoCheckout }
        return DeleteSessionMessageBuilder.buildMessage(
            sessionName: session.name,
            realWorktrees: realWorktrees,
            mainCheckouts: mainCheckouts
        )
    }
}

extension View {
    func deleteSessionAlert(session: Binding<Session?>, appState: AppState) -> some View {
        modifier(DeleteSessionAlert(sessionToDelete: session, appState: appState))
    }
}

// MARK: - Delete Session Message Builder

/// Testable logic for generating delete-session confirmation messages.
enum DeleteSessionMessageBuilder {
    static func buttonLabel(hasRealWorktrees: Bool) -> String {
        hasRealWorktrees ? "Delete Everything" : "Remove Session"
    }

    static func buildMessage(
        sessionName: String,
        realWorktrees: [SessionWorktree],
        mainCheckouts: [SessionWorktree]
    ) -> String {
        let hasWorktrees = !realWorktrees.isEmpty || !mainCheckouts.isEmpty

        if !hasWorktrees {
            return "This will remove the session \"\(sessionName)\"."
        } else if realWorktrees.isEmpty {
            return "This will remove the session \"\(sessionName)\".\n\nThe repository folder and branch (\(mainCheckouts.map(\.branch).joined(separator: ", "))) will not be affected."
        } else if mainCheckouts.isEmpty {
            return "This will delete:\n\n" +
                realWorktrees.map { "  \u{2022} Worktree: \($0.worktreePath)\n  \u{2022} Branch: \($0.branch)" }
                    .joined(separator: "\n\n") +
                "\n\nThe worktree folders and git branches will be removed from disk."
        } else {
            return "This will delete:\n\n" +
                realWorktrees.map { "  \u{2022} Worktree: \($0.worktreePath)\n  \u{2022} Branch: \($0.branch)" }
                    .joined(separator: "\n\n") +
                "\n\nThe worktree folders and branches above will be removed.\n\nThe main repo (\(mainCheckouts.map(\.branch).joined(separator: ", "))) will not be affected."
        }
    }
}

