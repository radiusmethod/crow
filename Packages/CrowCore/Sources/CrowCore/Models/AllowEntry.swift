import Foundation

/// Where an allow-list pattern was found.
public enum AllowSource: Hashable, Sendable {
    /// Found in `~/.claude/settings.json`.
    case global
    /// Found in `{devRoot}/.claude/settings.json` (Crow-managed workspace permissions).
    case workspace
    /// Found in a worktree's `.claude/settings.local.json`.
    case worktree(sessionName: String, path: String)
}

/// An aggregated allow-list entry collected from one or more sources.
public struct AllowEntry: Identifiable, Hashable, Sendable {
    /// The permission pattern string (e.g. `"Bash(npm test:*)"`, `"Read"`).
    public let pattern: String
    /// All locations where this pattern was found.
    public var sources: Set<AllowSource>

    public var id: String { pattern }

    /// Whether this pattern already exists in the global `~/.claude/settings.json`.
    public var isInGlobal: Bool {
        sources.contains(.global)
    }

    /// Whether this pattern exists in the workspace-level settings.
    public var isInWorkspace: Bool {
        sources.contains(.workspace)
    }

    /// Session names from worktree sources.
    public var worktreeSessionNames: [String] {
        sources.compactMap {
            if case .worktree(let name, _) = $0 { return name }
            return nil
        }.sorted()
    }

    public init(pattern: String, sources: Set<AllowSource>) {
        self.pattern = pattern
        self.sources = sources
    }
}
