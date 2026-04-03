import SwiftUI
import RmCore
import RmTerminal

/// Detail view for a selected session.
public struct SessionDetailView: View {
    let session: Session
    @Bindable var appState: AppState
    @State private var sessionToDelete: Session?

    public init(session: Session, appState: AppState) {
        self.session = session
        self.appState = appState
    }

    private var primaryWorktree: SessionWorktree? {
        appState.primaryWorktree(for: session.id)
    }

    private var sessionLinks: [SessionLink] {
        appState.links(for: session.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider().overlay(CorveilTheme.borderSubtle)
            terminalArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .deleteSessionAlert(session: $sessionToDelete, appState: appState)
    }

    // MARK: - Three-Row Header

    private var sessionHeader: some View {
        VStack(spacing: 0) {
            // Row 1: Name + Status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CorveilTheme.gold)

                    if let title = session.ticketTitle {
                        Text(title)
                            .font(.callout)
                            .foregroundStyle(CorveilTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                StatusBadge(status: session.status)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Row 2: Repo / Branch / Path (if worktree exists)
            if let wt = primaryWorktree {
                Divider().overlay(CorveilTheme.borderSubtle).padding(.horizontal, 16)

                HStack(spacing: 16) {
                    DetailLabel(icon: "folder", text: wt.repoName)
                    DetailLabel(icon: "arrow.triangle.branch", text: shortenBranch(wt.branch))
                    Spacer()
                    Text(shortenPath(wt.worktreePath))
                        .font(.caption)
                        .foregroundStyle(CorveilTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Row 3: Links + Actions (only if there's content to show)
            if session.ticketURL != nil || !sessionLinks.isEmpty || session.id != AppState.managerSessionID {
                Divider().overlay(CorveilTheme.borderSubtle).padding(.horizontal, 16)

                HStack(spacing: 8) {
                // Issue link
                if let url = session.ticketURL {
                    LinkChip(
                        label: session.ticketNumber.map { "Issue #\($0)" } ?? "Issue",
                        url: url,
                        icon: "link"
                    )
                }

                // PR link with status (from session links)
                ForEach(sessionLinks.filter { $0.linkType == .pr }) { link in
                    LinkChip(label: link.label, url: link.url, icon: "arrow.triangle.pull")
                }

                // PR status indicators (pipeline, review, merge)
                if let status = appState.prStatus[session.id] {
                    PRStatusDetail(status: status)
                }

                // Repo link
                ForEach(sessionLinks.filter { $0.linkType == .repo }) { link in
                    LinkChip(label: link.label, url: link.url, icon: "folder")
                }

                Spacer()

                // Action buttons (not for Manager)
                if session.id != AppState.managerSessionID {
                    if appState.vsCodeAvailable, primaryWorktree != nil {
                        Button {
                            appState.onOpenInVSCode?(session.id)
                        } label: {
                            Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(CorveilTheme.gold)
                        .fixedSize()
                    }

                    if primaryWorktree != nil {
                        Button {
                            appState.onOpenTerminal?(session.id)
                        } label: {
                            Label("Open Terminal", systemImage: "terminal")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(CorveilTheme.gold)
                        .fixedSize()
                    }

                    if session.status == .active,
                       session.ticketURL != nil,
                       session.provider == .github {
                        if appState.isMarkingInReview[session.id] == true {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 8)
                        } else {
                            Button {
                                appState.onMarkInReview?(session.id)
                            } label: {
                                Label("In Review", systemImage: "eye.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(CorveilTheme.gold)
                            .fixedSize()
                        }
                    }

                    if session.status == .active || session.status == .inReview {
                        Button {
                            appState.onCompleteSession?(session.id)
                        } label: {
                            Label("Mark as Completed", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(CorveilTheme.gold)
                        .fixedSize()
                    }

                    Button(role: .destructive) {
                        sessionToDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            }
        }
        .background(CorveilTheme.bgSurface)
    }

    @ViewBuilder
    private var managerBrandmark: some View {
        let image: NSImage? = {
            for bundle in Bundle.allBundles {
                if let url = bundle.url(forResource: "CorveilBrandmark", withExtension: "png"),
                   let img = NSImage(contentsOf: url) { return img }
            }
            return nil
        }()
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        }
    }

    // MARK: - Terminal Area

    @ViewBuilder
    private var terminalArea: some View {
        let sessionTerminals = appState.terminals(for: session.id)
        if sessionTerminals.isEmpty {
            TerminalSurfaceView(
                terminalID: session.id,
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            .id(session.id)
        } else if sessionTerminals.count == 1 {
            let terminal = sessionTerminals[0]
            ReadinessAwareTerminal(terminal: terminal, appState: appState)
        } else {
            VStack(spacing: 0) {
                TerminalTabBar(
                    terminals: sessionTerminals,
                    activeID: appState.activeTerminalID[session.id] ?? sessionTerminals[0].id,
                    onSelect: { id in appState.activeTerminalID[session.id] = id }
                )
                Divider().overlay(CorveilTheme.borderSubtle)
                let activeID = appState.activeTerminalID[session.id] ?? sessionTerminals[0].id
                if let terminal = sessionTerminals.first(where: { $0.id == activeID }) {
                    ReadinessAwareTerminal(terminal: terminal, appState: appState)
                }
            }
        }
    }

    // MARK: - Helpers

    private func shortenBranch(_ branch: String) -> String {
        if let last = branch.split(separator: "/").last {
            return String(last)
        }
        return branch
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Supporting Views

struct DetailLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(CorveilTheme.textMuted)
            Text(text)
                .font(.caption)
                .foregroundStyle(CorveilTheme.textSecondary)
                .lineLimit(1)
        }
    }
}

public struct TerminalTabBar: View {
    let terminals: [SessionTerminal]
    let activeID: UUID
    let onSelect: (UUID) -> Void

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(terminals) { terminal in
                Button { onSelect(terminal.id) } label: {
                    Text(terminal.name)
                        .font(.caption)
                        .foregroundStyle(terminal.id == activeID ? CorveilTheme.gold : CorveilTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(terminal.id == activeID ? CorveilTheme.gold.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(CorveilTheme.bgSurface)
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .active: .green
        case .paused: .yellow
        case .inReview: CorveilTheme.gold
        case .completed: CorveilTheme.gold
        case .archived: CorveilTheme.textMuted
        }
    }
}

struct LinkChip: View {
    let label: String
    let url: String
    let icon: String

    var body: some View {
        Button {
            if let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(CorveilTheme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CorveilTheme.gold.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(CorveilTheme.goldDark.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Readiness-Aware Terminal Wrapper

/// Wraps a TerminalSurfaceView with readiness tracking.
/// Auto-launches `claude --continue` when the shell becomes ready on first focus.
struct ReadinessAwareTerminal: View {
    let terminal: SessionTerminal
    @Bindable var appState: AppState

    private var readiness: TerminalReadiness {
        appState.terminalReadiness[terminal.id] ?? .claudeLaunched  // Default for non-tracked terminals
    }

    var body: some View {
        ZStack {
            TerminalSurfaceView(
                terminalID: terminal.id,
                workingDirectory: terminal.cwd,
                command: terminal.command
            )
            .id(terminal.id)

            // Loading overlay while terminal is not yet ready
            if readiness < .shellReady {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(readiness == .uninitialized ? "Waiting for terminal..." : "Shell starting...")
                        .font(.caption)
                        .foregroundStyle(CorveilTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CorveilTheme.bgDeep.opacity(0.85))
            }
        }
        .onChange(of: readiness) { oldValue, newValue in
            if newValue == .shellReady {
                // Shell just became ready — auto-launch Claude
                appState.onLaunchClaude?(terminal.id)
            }
        }
    }
}
