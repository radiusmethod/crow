import SwiftUI
import RmCore

/// Left sidebar showing grouped session list with pinned manager tab.
public struct SessionListView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var sessionToDelete: Session?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        List(selection: $appState.selectedSessionID) {
            // Ticket board tab
            Section {
                TicketBoardSidebarRow(appState: appState)
                    .tag(AppState.ticketBoardSessionID)
            } header: {
                Label("Tickets", systemImage: "ticket")
            }

            // Pinned manager tab
            if let manager = appState.managerSession {
                Section {
                    SessionRow(session: manager, isManager: true)
                        .tag(manager.id)
                } header: {
                    Label("Manager", systemImage: "sparkle")
                }
            }

            // Active sessions
            if !appState.activeSessions.isEmpty {
                Section("Active") {
                    ForEach(filteredSessions(appState.activeSessions)) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                sessionContextMenu(session)
                            }
                    }
                }
            }

            // Completed sessions
            if !appState.completedSessions.isEmpty {
                Section("Completed") {
                    ForEach(filteredSessions(appState.completedSessions)) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                sessionContextMenu(session)
                            }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isCreatingSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $appState.isCreatingSession) {
            CreateSessionView(appState: appState)
        }
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            if let session = sessionToDelete {
                let wts = appState.worktrees(for: session.id)
                let hasRealWorktrees = wts.contains { !Self.isMainCheckout($0) }
                Button(hasRealWorktrees ? "Delete Everything" : "Remove Session", role: .destructive) {
                    Task { try? await appState.onDeleteSession?(session.id) }
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                let wts = appState.worktrees(for: session.id)
                let realWorktrees = wts.filter { !Self.isMainCheckout($0) }
                let mainCheckouts = wts.filter { Self.isMainCheckout($0) }

                if wts.isEmpty {
                    Text("This will delete the session \"\(session.name)\".")
                } else if realWorktrees.isEmpty {
                    // All worktrees are main checkouts — only removing session metadata
                    Text("This will remove the session \"\(session.name)\".\n\nThe repository folder and branch (\(mainCheckouts.map(\.branch).joined(separator: ", "))) will not be affected.")
                } else if mainCheckouts.isEmpty {
                    // All are real worktrees — full cleanup
                    Text("This will delete:\n\n" +
                         realWorktrees.map { wt in
                             "  \u{2022} Worktree: \(wt.worktreePath)\n  \u{2022} Branch: \(wt.branch)"
                         }.joined(separator: "\n\n") +
                         "\n\nThe worktree folders and git branches will be removed from disk.")
                } else {
                    // Mix of both
                    Text("This will delete:\n\n" +
                         realWorktrees.map { wt in
                             "  \u{2022} Worktree: \(wt.worktreePath)\n  \u{2022} Branch: \(wt.branch)"
                         }.joined(separator: "\n\n") +
                         "\n\nThe worktree folders and branches above will be removed.\n\n" +
                         "The main repo (\(mainCheckouts.map(\.branch).joined(separator: ", "))) will not be affected.")
                }
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        if session.status == .active {
            Button {
                appState.onCompleteSession?(session.id)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        }

        Button(role: .destructive) {
            sessionToDelete = session
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func filteredSessions(_ sessions: [Session]) -> [Session] {
        if searchText.isEmpty { return sessions }
        return sessions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Check if a worktree entry is the main repo checkout (not a real git worktree).
    private static func isMainCheckout(_ wt: SessionWorktree) -> Bool {
        let worktree = (wt.worktreePath as NSString).standardizingPath
        let repo = (wt.repoPath as NSString).standardizingPath
        if worktree == repo { return true }
        let branch = wt.branch.lowercased()
        let protectedNames: Set<String> = ["main", "master", "develop", "dev", "trunk", "release"]
        return protectedNames.contains(branch)
    }
}

struct SessionRow: View {
    let session: Session
    var isManager: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if isManager {
                    Image(systemName: "sparkle")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if !isManager {
                    statusIndicator
                }
            }
            if let title = session.ticketTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .active:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .paused:
            Circle()
                .fill(.yellow)
                .frame(width: 8, height: 8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .archived:
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
