import Foundation

/// A git worktree associated with a session.
public struct SessionWorktree: Identifiable, Codable, Sendable {
    public let id: UUID
    public var sessionID: UUID
    public var repoName: String
    public var repoPath: String
    public var worktreePath: String
    public var branch: String
    public var isPrimary: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        repoName: String,
        repoPath: String,
        worktreePath: String,
        branch: String,
        isPrimary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.repoName = repoName
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.isPrimary = isPrimary
        self.createdAt = createdAt
    }
}
