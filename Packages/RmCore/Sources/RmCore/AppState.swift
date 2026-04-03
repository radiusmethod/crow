import Foundation

/// Observable application state shared across the app.
@MainActor
@Observable
public final class AppState {
    public var sessions: [Session] = []
    public var selectedSessionID: UUID?
    public var isCreatingSession: Bool = false

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

    public var managerSession: Session? {
        sessions.first { $0.id == Self.managerSessionID }
    }

    // MARK: - Issue Tracking

    /// Issues assigned to the current user across all workspaces.
    public var assignedIssues: [AssignedIssue] = []
    public var isLoadingIssues: Bool = false

    /// Number of issues completed (closed) in the last 24 hours.
    public var doneIssuesLast24h: Int = 0

    /// Currently selected pipeline filter on the ticket board.
    public var selectedTicketStatus: TicketStatus = .inProgress

    /// Claude Code state per session (idle, working, waiting, done).
    public var claudeState: [UUID: ClaudeState] = [:]

    /// PR status per session (pipeline, review, merge readiness).
    public var prStatus: [UUID: PRStatus] = [:]

    /// Whether the VS Code `code` CLI is available on this system.
    public var vsCodeAvailable: Bool = false

    /// Terminal readiness state per terminal ID.
    public var terminalReadiness: [UUID: TerminalReadiness] = [:]

    // MARK: - Hook Events

    /// Recent hook events per session (ring buffer, last 50 events).
    public var hookEvents: [UUID: [HookEvent]] = [:]

    /// Pending notification requiring user attention, per session.
    public var pendingNotification: [UUID: HookNotification] = [:]

    /// Last tool activity per session (what Claude is currently doing).
    public var lastToolActivity: [UUID: ToolActivity] = [:]

    /// Called when user clicks "Work on" for an assigned issue.
    public var onWorkOnIssue: ((String) -> Void)?  // receives issue URL

    /// Called to launch Claude in a terminal that just became ready.
    public var onLaunchClaude: ((UUID) -> Void)?  // receives terminal ID

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

    // MARK: - Computed Properties

    public var selectedSession: Session? {
        guard selectedSessionID != Self.ticketBoardSessionID else { return nil }
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
