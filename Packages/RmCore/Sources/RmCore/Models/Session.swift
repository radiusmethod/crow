import Foundation

/// A development session representing work on a ticket or feature.
public struct Session: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var status: SessionStatus
    public var ticketURL: String?
    public var ticketTitle: String?
    public var ticketNumber: Int?
    public var provider: Provider?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        status: SessionStatus = .active,
        ticketURL: String? = nil,
        ticketTitle: String? = nil,
        ticketNumber: Int? = nil,
        provider: Provider? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.ticketURL = ticketURL
        self.ticketTitle = ticketTitle
        self.ticketNumber = ticketNumber
        self.provider = provider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
