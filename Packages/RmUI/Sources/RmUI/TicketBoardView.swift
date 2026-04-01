import SwiftUI
import RmCore

// MARK: - Main Ticket Board View

/// Full-pane ticket board shown when the Ticket Board tab is selected.
public struct TicketBoardView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            ticketBoardHeader
            Divider()
            PipelineView(appState: appState)
            Divider()
            TicketListView(appState: appState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var ticketBoardHeader: some View {
        HStack {
            Text("Ticket Board")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CorveilTheme.gold)

            if appState.isLoadingIssues {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Text("\(appState.assignedIssues.count) issues")
                .font(.caption)
                .foregroundStyle(CorveilTheme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(CorveilTheme.bgSurface)
    }
}

// MARK: - Pipeline View

/// Horizontal status timeline showing the four pipeline stages.
struct PipelineView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(TicketStatus.pipelineStatuses.enumerated()), id: \.element) { index, status in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 2)
                }

                PipelineSegment(
                    status: status,
                    count: appState.issueCount(for: status),
                    isSelected: appState.selectedTicketStatus == status
                ) {
                    appState.selectedTicketStatus = status
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct PipelineSegment: View {
    let status: TicketStatus
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(status.rawValue)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? statusColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? statusColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch status {
        case .backlog: .gray
        case .ready: .blue
        case .inProgress: .orange
        case .inReview: .purple
        case .done: .green
        case .unknown: .secondary
        }
    }
}

// MARK: - Ticket List View

struct TicketListView: View {
    @Bindable var appState: AppState

    private var filteredIssues: [AssignedIssue] {
        appState.issues(for: appState.selectedTicketStatus)
    }

    var body: some View {
        if filteredIssues.isEmpty {
            VStack {
                Spacer().frame(height: 40)
                Image(systemName: "ticket")
                    .font(.system(size: 32))
                    .foregroundStyle(CorveilTheme.textMuted)
                Text("No \(appState.selectedTicketStatus.rawValue) Tickets")
                    .font(.headline)
                    .foregroundStyle(CorveilTheme.textSecondary)
                    .padding(.top, 8)
                Text("No issues are in the \(appState.selectedTicketStatus.rawValue) state.")
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(filteredIssues) { issue in
                TicketRow(issue: issue, appState: appState)
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Ticket Row

struct TicketRow: View {
    let issue: AssignedIssue
    @Bindable var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(issue.repo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("#\(issue.number)")
                        .font(.callout)
                        .fontWeight(.medium)
                    if let prNum = issue.prNumber {
                        prBadge(number: prNum, url: issue.prURL)
                    }
                }
                Text(issue.title)
                    .font(.body)
                    .lineLimit(2)
                if !issue.labels.isEmpty {
                    labelRow
                }
            }

            Spacer()

            worktreeAction
        }
        .padding(.vertical, 4)
    }

    private func prBadge(number: Int, url: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.pull")
                .font(.caption2)
            Text("PR #\(number)")
                .font(.caption)
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.purple.opacity(0.1))
        .clipShape(Capsule())
    }

    private var labelRow: some View {
        HStack(spacing: 4) {
            ForEach(issue.labels.prefix(4), id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            if issue.labels.count > 4 {
                Text("+\(issue.labels.count - 4)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var worktreeAction: some View {
        if let session = appState.activeSession(for: issue) {
            Button {
                appState.selectedSessionID = session.id
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(session.name)
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                appState.onWorkOnIssue?(issue.url)
            } label: {
                Label("Start Working", systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Sidebar Row

/// Compact sidebar row showing ticket board with status counts using SF Symbols.
public struct TicketBoardSidebarRow: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text("Tickets")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CorveilTheme.gold)
                if appState.isLoadingIssues {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                StatusCount(icon: "tray", color: CorveilTheme.textMuted, count: appState.issueCount(for: .backlog))
                StatusCount(icon: "flag.fill", color: .blue, count: appState.issueCount(for: .ready))
                StatusCount(icon: "bolt.fill", color: .orange, count: appState.issueCount(for: .inProgress))
                StatusCount(icon: "eye.fill", color: .purple, count: appState.issueCount(for: .inReview))
                StatusCount(icon: "checkmark.circle.fill", color: .green, count: appState.doneIssuesLast24h)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CorveilTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(CorveilTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}

struct StatusCount: View {
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorveilTheme.textSecondary)
        }
    }
}
