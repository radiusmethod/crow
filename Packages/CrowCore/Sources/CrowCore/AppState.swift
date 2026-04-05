import Foundation

/// Observable application state shared across the app.
@MainActor
@Observable
public final class AppState {
    public var sessions: [Session] = []
    public var selectedSessionID: UUID?

    /// Whether notification sounds are muted (toggled via sidebar speaker icon).
    public var soundMuted: Bool = false

    /// Whether subtitle rows (ticket title, repo/branch) are hidden in sidebar session rows.
    public var hideSessionDetails: Bool = false

    /// Worktrees keyed by session ID.
    public var worktrees: [UUID: [SessionWorktree]] = [:]

    /// Links keyed by session ID.
    public var links: [UUID: [SessionLink]] = [:]

    /// Terminals keyed by session ID.
    public var terminals: [UUID: [SessionTerminal]] = [:]

    /// Active terminal tab per session.
    public var activeTerminalID: [UUID: UUID] = [:]

    // MARK: - Manager Session

    /// Fixed UUID for the always-present manager session.
    nonisolated public static let managerSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Fixed UUID for the ticket board tab.
    nonisolated public static let ticketBoardSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Fixed UUID for the allow list tab.
    nonisolated public static let allowListSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    public var managerSession: Session? {
        sessions.first { $0.id == Self.managerSessionID }
    }

    // MARK: - Issue Tracking

    /// Issues assigned to the current user across all workspaces.
    public var assignedIssues: [AssignedIssue] = []
    public var isLoadingIssues: Bool = false

    /// Number of issues completed (closed) in the last 24 hours.
    public var doneIssuesLast24h: Int = 0

    /// Currently selected pipeline filter on the ticket board (nil = show all).
    public var selectedTicketStatus: TicketStatus? = .inProgress

    /// Text search for ticket board filtering.
    public var ticketSearchText: String = ""

    /// Sort order for the ticket board.
    public var ticketSortOrder: TicketSortOrder = .updatedDesc

    // MARK: - Allow List

    /// Aggregated allow-list entries from all worktrees.
    public var allowEntries: [AllowEntry] = []
    public var isLoadingAllowList: Bool = false

    /// Called to scan and aggregate allow-list entries.
    public var onLoadAllowList: (() -> Void)?

    /// Called to promote selected patterns to the global settings.
    public var onPromoteToGlobal: ((Set<String>) -> Void)?

    // MARK: - PR & Tool Status

    /// PR status per session (pipeline, review, merge readiness).
    public var prStatus: [UUID: PRStatus] = [:]

    /// Whether the VS Code `code` CLI is available on this system.
    public var vsCodeAvailable: Bool = false

    /// Runtime dependencies that were not found at startup (e.g., "gh", "git", "claude").
    public var missingDependencies: [String] = []

    /// Terminal readiness state per terminal ID.
    public var terminalReadiness: [UUID: TerminalReadiness] = [:]

    // MARK: - Hook Events (per-session Observable wrappers)

    /// Per-session hook state. Using @Observable class wrappers so mutations to one
    /// session's state only invalidate views reading THAT session — not all sessions.
    /// (Plain dictionaries with @Observable cause ALL readers to re-render on any key change.)
    private var _sessionState: [UUID: SessionHookState] = [:]

    /// Get or create the hook state for a session. Views should hold the returned reference
    /// to benefit from scoped observation.
    public func hookState(for sessionID: UUID) -> SessionHookState {
        if let existing = _sessionState[sessionID] { return existing }
        let new = SessionHookState()
        _sessionState[sessionID] = new
        return new
    }

    /// Remove hook state for a deleted session.
    public func removeHookState(for sessionID: UUID) {
        _sessionState.removeValue(forKey: sessionID)
    }

    /// Called when user clicks "Work on" for an assigned issue.
    public var onWorkOnIssue: ((String) -> Void)?  // receives issue URL

    /// Called to launch Claude in a terminal that just became ready.
    public var onLaunchClaude: ((UUID) -> Void)?  // receives terminal ID

    /// Called to add a new plain-shell terminal tab to a session.
    public var onAddTerminal: ((UUID) -> Void)?  // receives session ID

    /// Called to close a non-managed terminal tab.
    public var onCloseTerminal: ((UUID, UUID) -> Void)?  // receives (sessionID, terminalID)

    // MARK: - Closures wired by AppDelegate

    /// Called to delete a session and clean up its worktrees.
    public var onDeleteSession: ((UUID) async throws -> Void)?

    /// Called to mark a session as completed.
    public var onCompleteSession: ((UUID) -> Void)?

    /// Called to mark a session's ticket as "In Review" on the GitHub Project board.
    public var onMarkInReview: ((UUID) -> Void)?

    /// Called to update session status to .inReview (persists to store).
    public var onSetSessionInReview: ((UUID) -> Void)?

    /// Whether a given session is currently being marked as "In Review" (loading state).
    public var isMarkingInReview: [UUID: Bool] = [:]

    /// Called to open a session's primary worktree in VS Code.
    public var onOpenInVSCode: ((UUID) -> Void)?

    /// Called to open a terminal at a session's primary worktree path.
    public var onOpenTerminal: ((UUID) -> Void)?

    /// Called when the sound mute toggle is changed.
    public var onSoundMutedChanged: ((Bool) -> Void)?

    // MARK: - Computed Properties

    public var selectedSession: Session? {
        guard selectedSessionID != Self.ticketBoardSessionID,
              selectedSessionID != Self.allowListSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    public var activeSessions: [Session] {
        sessions.filter { $0.status == .active && $0.id != Self.managerSessionID }
    }

    public var inReviewSessions: [Session] {
        sessions.filter { $0.status == .inReview && $0.id != Self.managerSessionID }
    }

    public var completedSessions: [Session] {
        sessions.filter { $0.status == .completed || $0.status == .archived }
    }

    public func worktrees(for sessionID: UUID) -> [SessionWorktree] {
        worktrees[sessionID] ?? []
    }

    public func links(for sessionID: UUID) -> [SessionLink] {
        links[sessionID] ?? []
    }

    public func terminals(for sessionID: UUID) -> [SessionTerminal] {
        terminals[sessionID] ?? []
    }

    public func primaryWorktree(for sessionID: UUID) -> SessionWorktree? {
        worktrees[sessionID]?.first(where: { $0.isPrimary }) ?? worktrees[sessionID]?.first
    }

    // MARK: - Ticket Board Helpers

    /// Count of issues in a given pipeline status. Treats `.unknown` as `.backlog`.
    public func issueCount(for status: TicketStatus) -> Int {
        assignedIssues.filter { effectiveStatus($0) == status }.count
    }

    /// Issues filtered by the given pipeline status. Treats `.unknown` as `.backlog`.
    public func issues(for status: TicketStatus) -> [AssignedIssue] {
        assignedIssues.filter { effectiveStatus($0) == status }
    }

    /// Filtered and sorted issues for the ticket board, applying status filter, search, and sort.
    public var filteredSortedIssues: [AssignedIssue] {
        var result = assignedIssues

        // Status filter
        if let status = selectedTicketStatus {
            result = result.filter { effectiveStatus($0) == status }
        }

        // Text search
        if !ticketSearchText.isEmpty {
            let query = ticketSearchText.lowercased()
            result = result.filter { issue in
                issue.title.lowercased().contains(query)
                || issue.repo.lowercased().contains(query)
                || "#\(issue.number)".contains(query)
                || issue.labels.contains(where: { $0.lowercased().contains(query) })
            }
        }

        // Sort
        result.sort { a, b in
            switch ticketSortOrder {
            case .updatedDesc:
                return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
            case .updatedAsc:
                return (a.updatedAt ?? .distantPast) < (b.updatedAt ?? .distantPast)
            case .titleAsc:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .titleDesc:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending
            case .numberDesc:
                return a.number > b.number
            case .numberAsc:
                return a.number < b.number
            }
        }

        return result
    }

    /// Find the active session linked to a given issue (by matching ticket URL).
    public func activeSession(for issue: AssignedIssue) -> Session? {
        activeSessions.first { $0.ticketURL == issue.url }
    }

    /// Maps `.unknown` project status to `.backlog` for display purposes.
    private func effectiveStatus(_ issue: AssignedIssue) -> TicketStatus {
        issue.projectStatus == .unknown ? .backlog : issue.projectStatus
    }

    public init() {}
}

// MARK: - Per-Session Hook State

/// Observable wrapper for per-session hook/Claude state.
/// Using a reference-type @Observable class ensures that mutations to one session's
/// state only invalidate views observing THAT session's instance — not all sessions.
@MainActor
@Observable
public final class SessionHookState {
    public var claudeState: ClaudeState = .idle
    public var pendingNotification: HookNotification?
    public var lastToolActivity: ToolActivity?
    public var hookEvents: [HookEvent] = []

    public init() {}
}
