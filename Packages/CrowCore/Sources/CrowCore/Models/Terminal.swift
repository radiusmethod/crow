import Foundation

/// A terminal instance within a session.
public struct SessionTerminal: Identifiable, Codable, Sendable {
    public let id: UUID
    public var sessionID: UUID
    public var name: String
    public var cwd: String
    public var command: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        name: String = "Shell",
        cwd: String,
        command: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.command = command
        self.createdAt = createdAt
    }
}
