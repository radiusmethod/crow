import SwiftUI
import CrowCore

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

            // Manager + Allow List row
            if appState.managerSession != nil {
                ManagerAllowListRow(appState: appState)
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

            // In Review sessions
            if !appState.inReviewSessions.isEmpty {
                SectionDivider(title: "In Review")
                ForEach(filteredSessions(appState.inReviewSessions)) { session in
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
                    appState.soundMuted.toggle()
                    appState.onSoundMutedChanged?(appState.soundMuted)
                } label: {
                    Image(systemName: appState.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(appState.soundMuted ? CorveilTheme.textMuted : CorveilTheme.gold)
                }
                .help(appState.soundMuted ? "Unmute notifications" : "Mute notifications")
                .accessibilityLabel(appState.soundMuted ? "Unmute notifications" : "Mute notifications")
            }
        }
        .deleteSessionAlert(session: $sessionToDelete, appState: appState)
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        if session.status == .active,
           session.ticketURL != nil,
           session.provider == .github {
            Button {
                appState.onMarkInReview?(session.id)
            } label: {
                Label("Mark as In Review", systemImage: "eye.circle")
            }
            .disabled(appState.isMarkingInReview[session.id] == true)
        }

        if session.status == .active || session.status == .inReview {
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

/// Sidebar header showing the Corveil brandmark.
struct SidebarBrandmark: View {
    var body: some View {
        VStack(spacing: 0) {
            BrandmarkImage()
                .frame(width: 120)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

// MARK: - Section Divider

/// Uppercase section label used to group sessions in the sidebar.
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

// MARK: - Manager + Allow List Row

/// Combined Manager and Allow List toggle buttons in the sidebar.
struct ManagerAllowListRow: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            sidebarButton(
                title: "Manager",
                isActive: appState.selectedSessionID == AppState.managerSessionID
            ) {
                appState.selectedSessionID = AppState.managerSessionID
            }

            sidebarButton(
                title: "Allow List",
                isActive: appState.selectedSessionID == AppState.allowListSessionID
            ) {
                appState.selectedSessionID = AppState.allowListSessionID
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? CorveilTheme.gold : CorveilTheme.goldDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? CorveilTheme.bgCard : CorveilTheme.bgSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isActive ? CorveilTheme.goldDark.opacity(0.6) : CorveilTheme.goldDark.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row

/// Sidebar row for a work session, showing name, ticket info, PR status, and Claude state.
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
        appState.hookState(for: session.id).claudeState
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
            if !appState.hideSessionDetails, let title = session.ticketTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textSecondary)
                    .lineLimit(1)
            }

            // Row 3: Repo + branch
            if !appState.hideSessionDetails, let wt = primaryWorktree {
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
                        CapsuleBadge("Issue #\(num)", color: CorveilTheme.gold)
                    }
                    if let pr = prLink {
                        PRBadge(label: pr.label, status: prStatus)
                    }
                    if claudeState != .idle || appState.hookState(for: session.id).pendingNotification != nil {
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
        .animation(.easeInOut(duration: 0.2), value: appState.hideSessionDetails)
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
                    .accessibilityLabel("Waiting for terminal")
            case .surfaceCreated:
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Terminal starting")
            case .shellReady:
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Shell ready")
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
                        .accessibilityLabel("Needs attention")
                } else if claudeState == .working {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.green.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.6)
                        )
                        .accessibilityLabel("Claude working")
                } else {
                    // done or idle — solid green
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Active")
                }
            }
        case .inReview:
            Image(systemName: "eye.circle.fill")
                .foregroundStyle(CorveilTheme.gold)
                .font(.caption)
                .accessibilityLabel("In review")
        case .paused:
            Circle()
                .fill(.yellow)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Paused")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CorveilTheme.gold)
                .font(.caption)
                .accessibilityLabel("Completed")
        case .archived:
            Image(systemName: "archivebox.fill")
                .foregroundStyle(CorveilTheme.textMuted)
                .font(.caption)
                .accessibilityLabel("Archived")
        }
    }

    @ViewBuilder
    private var claudeStateBadge: some View {
        let activity = appState.hookState(for: session.id).lastToolActivity
        let notification = appState.hookState(for: session.id).pendingNotification

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
        appState.hookState(for: session.id).pendingNotification != nil
    }

    private var rowBackgroundColor: Color {
        if needsAttention {
            return Color.orange.opacity(0.12)
        } else if claudeState == .done && terminalReadiness == .claudeLaunched {
            return CorveilTheme.bgDone
        }
        return CorveilTheme.bgCard
    }

    private var rowBorderColor: Color {
        if needsAttention {
            return Color.orange.opacity(0.4)
        }
        return CorveilTheme.borderSubtle
    }

}
