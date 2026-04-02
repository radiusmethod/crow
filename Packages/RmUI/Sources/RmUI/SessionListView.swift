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
            // Brandmark header
            SidebarBrandmark()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Ticket board row
            TicketBoardSidebarRow(appState: appState)
                .tag(AppState.ticketBoardSessionID)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Manager row
            if let manager = appState.managerSession {
                ManagerRow()
                    .tag(manager.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // Active sessions
            if !appState.activeSessions.isEmpty {
                SectionDivider(title: "Active")
                ForEach(filteredSessions(appState.activeSessions)) { session in
                    SessionRow(session: session, appState: appState)
                        .tag(session.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            sessionContextMenu(session)
                        }
                }
            }

            // Completed sessions
            if !appState.completedSessions.isEmpty {
                SectionDivider(title: "Completed")
                ForEach(filteredSessions(appState.completedSessions)) { session in
                    SessionRow(session: session, appState: appState)
                        .tag(session.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            sessionContextMenu(session)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(CorveilTheme.bgDeep)
        .searchable(text: $searchText, prompt: "Search sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isCreatingSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                        .foregroundStyle(CorveilTheme.gold)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $appState.isCreatingSession) {
            CreateSessionView(appState: appState)
        }
        .deleteSessionAlert(session: $sessionToDelete, appState: appState)
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        if session.status == .active {
            Button {
                appState.onCompleteSession?(session.id)
            } label: {
                Label("Mark as Completed", systemImage: "checkmark.circle")
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
}

// MARK: - Sidebar Brandmark

struct SidebarBrandmark: View {
    var body: some View {
        VStack(spacing: 0) {
            if let image = loadBrandmark() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func loadBrandmark() -> NSImage? {
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "CorveilBrandmark", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

// MARK: - Section Divider

struct SectionDivider: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(CorveilTheme.goldDark)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Manager Row

struct ManagerRow: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Manager")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CorveilTheme.gold)
            Spacer()
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CorveilTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(CorveilTheme.goldDark.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.vertical, 2)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let appState: AppState

    private var primaryWorktree: SessionWorktree? {
        appState.primaryWorktree(for: session.id)
    }

    private var prLink: SessionLink? {
        appState.links(for: session.id).first(where: { $0.linkType == .pr })
    }

    private var prStatus: PRStatus? {
        appState.prStatus[session.id]
    }

    private var claudeState: ClaudeState {
        appState.claudeState[session.id] ?? .idle
    }

    /// Readiness of the primary terminal for this session.
    private var terminalReadiness: TerminalReadiness? {
        let terminals = appState.terminals(for: session.id)
        guard let primary = terminals.first else { return nil }
        return appState.terminalReadiness[primary.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: Name + status indicator
            HStack {
                Text(session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CorveilTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                statusIndicator
            }

            // Row 2: Ticket title (if any)
            if let title = session.ticketTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textSecondary)
                    .lineLimit(1)
            }

            // Row 3: Repo + branch
            if let wt = primaryWorktree {
                Text("\(wt.repoName) / \(shortenBranch(wt.branch))")
                    .font(.caption2)
                    .foregroundStyle(CorveilTheme.textMuted)
                    .lineLimit(1)
            }

            // Row 4: Issue badge + PR badge + Claude state
            let hasIssueBadge = session.ticketNumber != nil
            let hasBadges = hasIssueBadge || prLink != nil || claudeState != .idle
            if hasBadges {
                HStack(spacing: 6) {
                    if let num = session.ticketNumber {
                        Text("Issue #\(num)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CorveilTheme.gold.opacity(0.1))
                            .foregroundStyle(CorveilTheme.gold)
                            .overlay(
                                Capsule().strokeBorder(CorveilTheme.goldDark.opacity(0.3), lineWidth: 0.5)
                            )
                            .clipShape(Capsule())
                    }
                    if let pr = prLink {
                        PRBadge(label: pr.label, status: prStatus)
                    }
                    if claudeState != .idle || appState.pendingNotification[session.id] != nil {
                        claudeStateBadge
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(rowBorderColor, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: needsAttention)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .active:
            // Reflect terminal readiness state
            switch terminalReadiness {
            case .uninitialized, nil:
                Circle()
                    .fill(CorveilTheme.textMuted)
                    .frame(width: 8, height: 8)
            case .surfaceCreated:
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
            case .shellReady:
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            case .claudeLaunched:
                if needsAttention {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.orange.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.6)
                        )
                } else if claudeState == .working {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.green.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.6)
                        )
                } else {
                    // done or idle — solid green
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }
        case .paused:
            Circle()
                .fill(.yellow)
                .frame(width: 8, height: 8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CorveilTheme.gold)
                .font(.caption)
        case .archived:
            Image(systemName: "archivebox.fill")
                .foregroundStyle(CorveilTheme.textMuted)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var claudeStateBadge: some View {
        let activity = appState.lastToolActivity[session.id]
        let notification = appState.pendingNotification[session.id]

        if let notification {
            // Attention badges
            if notification.notificationType == "permission_prompt" {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Permission")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            } else if notification.notificationType == "question" {
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.caption2)
                    Text("Question")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        } else {
            switch claudeState {
            case .working:
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    if let activity, activity.isActive {
                        Text(activity.toolName)
                            .font(.caption2)
                    } else {
                        Text("Working")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.orange)
            case .done:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Done")
                        .font(.caption2)
                }
                .foregroundStyle(CorveilTheme.gold)
            case .waiting, .idle:
                EmptyView()
            }
        }
    }

    private var needsAttention: Bool {
        appState.pendingNotification[session.id] != nil
    }

    private var rowBackgroundColor: Color {
        if needsAttention {
            return Color.orange.opacity(0.12)
        } else if claudeState == .done && terminalReadiness == .claudeLaunched {
            return Color.green.opacity(0.06)
        }
        return CorveilTheme.bgCard
    }

    private var rowBorderColor: Color {
        if needsAttention {
            return Color.orange.opacity(0.4)
        }
        return CorveilTheme.borderSubtle
    }

    private func shortenBranch(_ branch: String) -> String {
        branch
            .replacingOccurrences(of: "feature/", with: "")
            .replacingOccurrences(of: "refs/heads/", with: "")
    }
}
