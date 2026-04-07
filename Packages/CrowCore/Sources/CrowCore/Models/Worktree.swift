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

// MARK: - Worktree Classification

extension SessionWorktree {
    /// Default branches that should never be deleted during worktree cleanup.
    public static let protectedBranchNames: Set<String> = [
        "main", "master", "develop", "dev", "trunk", "release",
    ]

    /// Returns true if a branch name is a protected default branch.
    /// Strips `refs/heads/` and `origin/` prefixes before comparison.
    public static func isProtectedBranch(_ branch: String) -> Bool {
        let name = branch
            .replacingOccurrences(of: "refs/heads/", with: "")
            .replacingOccurrences(of: "origin/", with: "")
            .lowercased()
        return protectedBranchNames.contains(name)
    }

    /// Returns true if this worktree points at the main repo checkout (not a real git worktree).
    /// True when the worktree path matches the repo path, or the branch is a protected default branch.
    public var isMainRepoCheckout: Bool {
        let worktree = (worktreePath as NSString).standardizingPath
        let repo = (repoPath as NSString).standardizingPath
        if worktree == repo { return true }
        return Self.isProtectedBranch(branch)
    }
}
