import Foundation

/// A terminal instance within a session.
public struct SessionTerminal: Identifiable, Codable, Sendable {
    public let id: UUID
    public var sessionID: UUID
    public var name: String
    public var cwd: String
    public var command: String?
    public var isManaged: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        name: String = "Shell",
        cwd: String,
        command: String? = nil,
        isManaged: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.command = command
        self.isManaged = isManaged
        self.createdAt = createdAt
    }

    // Custom decoder for backward compatibility — existing data lacks isManaged.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        name = try container.decode(String.self, forKey: .name)
        cwd = try container.decode(String.self, forKey: .cwd)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        isManaged = try container.decodeIfPresent(Bool.self, forKey: .isManaged) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
