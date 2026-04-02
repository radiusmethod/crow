import Foundation

/// A Claude Code hook event received from a session's Claude Code instance.
public struct HookEvent: Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let eventName: String
    public let summary: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        eventName: String,
        summary: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eventName = eventName
        self.summary = summary
        self.timestamp = timestamp
    }
}
