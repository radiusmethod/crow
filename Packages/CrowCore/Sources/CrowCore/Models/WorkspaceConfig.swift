import Foundation

/// Workspace configuration from ~/.claude/workspace-repos.json
public struct WorkspaceConfig: Codable, Sendable {
    public let devRoot: String
    public let workspaces: [String: WorkspaceEntry]
    public let defaults: WorkspaceDefaults

    public init(devRoot: String, workspaces: [String: WorkspaceEntry], defaults: WorkspaceDefaults) {
        self.devRoot = devRoot
        self.workspaces = workspaces
        self.defaults = defaults
    }

    /// Load config from ~/.claude/workspace-repos.json
    public static func load() throws -> WorkspaceConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".claude/workspace-repos.json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(WorkspaceConfig.self, from: data)
    }
}

public struct WorkspaceEntry: Codable, Sendable {
    public let provider: String
    public let cli: String
    public let host: String?
    public let alwaysInclude: [String]?

    public init(provider: String, cli: String, host: String? = nil, alwaysInclude: [String]? = nil) {
        self.provider = provider
        self.cli = cli
        self.host = host
        self.alwaysInclude = alwaysInclude
    }
}

public struct WorkspaceDefaults: Codable, Sendable {
    public let provider: String
    public let cli: String
    public let worktreePattern: String
    public let branchPrefix: String
    public let excludeDirs: [String]
    public let keywordSources: [String]

    public init(
        provider: String = "github",
        cli: String = "gh",
        worktreePattern: String = "{repo}-{feature}",
        branchPrefix: String = "feature/",
        excludeDirs: [String] = ["node_modules", ".git", "vendor", "dist", "build", "target"],
        keywordSources: [String] = ["CLAUDE.md", "README.md", "package.json", "Cargo.toml", "pyproject.toml", "go.mod"]
    ) {
        self.provider = provider
        self.cli = cli
        self.worktreePattern = worktreePattern
        self.branchPrefix = branchPrefix
        self.excludeDirs = excludeDirs
        self.keywordSources = keywordSources
    }
}
