import Foundation

/// A link (issue, PR, repo) associated with a session.
public struct SessionLink: Identifiable, Codable, Sendable {
    public let id: UUID
    public var sessionID: UUID
    public var label: String
    public var url: String
    public var linkType: LinkType

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        label: String,
        url: String,
        linkType: LinkType
    ) {
        self.id = id
        self.sessionID = sessionID
        self.label = label
        self.url = url
        self.linkType = linkType
    }
}
