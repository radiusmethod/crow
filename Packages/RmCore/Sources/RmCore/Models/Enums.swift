import Foundation

/// Status of a development session.
public enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case archived
}

/// Git provider type.
public enum Provider: String, Codable, Sendable {
    case github
    case gitlab
}

/// Type of link associated with a session.
public enum LinkType: String, Codable, Sendable {
    case ticket
    case pr
    case repo
    case custom
}

/// Claude Code process state as inferred from PTY output.
public enum ClaudeState: String, Codable, Sendable {
    case idle
    case working
    case waiting
    case done
}

/// Pipeline status for a ticket, derived from project board fields.
public enum TicketStatus: String, Codable, Sendable, CaseIterable {
    case backlog    = "Backlog"
    case ready      = "Ready"
    case inProgress = "In Progress"
    case inReview   = "In Review"
    case done       = "Done"
    case unknown    = "Unknown"

    /// The four active pipeline stages shown in the UI.
    public static let pipelineStatuses: [TicketStatus] = [.backlog, .ready, .inProgress, .inReview]
}
