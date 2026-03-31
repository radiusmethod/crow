import SwiftUI
import RmCore
import RmTerminal

/// Detail view for a selected session.
public struct SessionDetailView: View {
    let session: Session
    @Bindable var appState: AppState
    @State private var showDeleteConfirmation = false

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
            Divider()
            terminalArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { try? await appState.onDeleteSession?(session.id) }
            }
        } message: {
            let wts = appState.worktrees(for: session.id)
            if wts.isEmpty {
                Text("This will delete the session \"\(session.name)\".")
            } else {
                Text("This will delete:\n\n" +
                     wts.map { "  \u{2022} \($0.worktreePath)\n  \u{2022} Branch: \($0.branch)" }
                         .joined(separator: "\n\n") +
                     "\n\nWorktree folders and git branches will be removed.")
            }
        }
    }

    // MARK: - Three-Row Header

    private var sessionHeader: some View {
        VStack(spacing: 0) {
            // Row 1: Name + Status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let title = session.ticketTitle {
                        Text(title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
                Divider().padding(.horizontal, 16)

                HStack(spacing: 16) {
                    DetailLabel(icon: "folder", text: wt.repoName)
                    DetailLabel(icon: "arrow.triangle.branch", text: shortenBranch(wt.branch))
                    Spacer()
                    Text(shortenPath(wt.worktreePath))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Row 3: Links + Actions
            Divider().padding(.horizontal, 16)

            HStack(spacing: 8) {
                // Issue link
                if let url = session.ticketURL {
                    LinkChip(
                        label: session.ticketNumber.map { "#\($0)" } ?? "Issue",
                        url: url,
                        icon: "link"
                    )
                }

                // PR link (from session links)
                ForEach(sessionLinks.filter { $0.linkType == .pr }) { link in
                    LinkChip(label: link.label, url: link.url, icon: "arrow.triangle.pull")
                }

                // Repo link
                ForEach(sessionLinks.filter { $0.linkType == .repo }) { link in
                    LinkChip(label: link.label, url: link.url, icon: "folder")
                }

                Spacer()

                // Action buttons (not for Manager)
                if session.id != AppState.managerSessionID {
                    if session.status == .active {
                        Button {
                            appState.onCompleteSession?(session.id)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
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
            TerminalSurfaceView(
                terminalID: terminal.id,
                workingDirectory: terminal.cwd,
                command: terminal.command
            )
            .id(terminal.id)
        } else {
            VStack(spacing: 0) {
                TerminalTabBar(
                    terminals: sessionTerminals,
                    activeID: appState.activeTerminalID[session.id] ?? sessionTerminals[0].id,
                    onSelect: { id in appState.activeTerminalID[session.id] = id }
                )
                Divider()
                let activeID = appState.activeTerminalID[session.id] ?? sessionTerminals[0].id
                if let terminal = sessionTerminals.first(where: { $0.id == activeID }) {
                    TerminalSurfaceView(
                        terminalID: terminal.id,
                        workingDirectory: terminal.cwd,
                        command: terminal.command
                    )
                    .id(terminal.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func shortenBranch(_ branch: String) -> String {
        // Show last component: "feature/citadel-197-tab" → "citadel-197-tab"
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
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(terminal.id == activeID ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(.bar)
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption)
            .fontWeight(.medium)
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
        case .completed: .blue
        case .archived: .secondary
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
