import Foundation

/// Application configuration stored at {devRoot}/.claude/config.json
public struct AppConfig: Codable, Sendable {
    public var workspaces: [WorkspaceInfo]
    public var defaults: ConfigDefaults
    public var notifications: NotificationSettings
    public var sidebar: SidebarSettings

    public init(
        workspaces: [WorkspaceInfo] = [],
        defaults: ConfigDefaults = ConfigDefaults(),
        notifications: NotificationSettings = NotificationSettings(),
        sidebar: SidebarSettings = SidebarSettings()
    ) {
        self.workspaces = workspaces
        self.defaults = defaults
        self.notifications = notifications
        self.sidebar = sidebar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try container.decodeIfPresent([WorkspaceInfo].self, forKey: .workspaces) ?? []
        defaults = try container.decodeIfPresent(ConfigDefaults.self, forKey: .defaults) ?? ConfigDefaults()
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? NotificationSettings()
        sidebar = try container.decodeIfPresent(SidebarSettings.self, forKey: .sidebar) ?? SidebarSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case workspaces, defaults, notifications, sidebar
    }
}

/// A workspace folder configuration.
public struct WorkspaceInfo: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: String       // "github" or "gitlab"
    public var cli: String            // "gh" or "glab"
    public var host: String?          // GitLab host (e.g., "gitlab.example.com")
    public var alwaysInclude: [String] // repos to always list in prompt table

    public init(
        id: UUID = UUID(),
        name: String,
        provider: String = "github",
        cli: String = "gh",
        host: String? = nil,
        alwaysInclude: [String] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.cli = cli
        self.host = host
        self.alwaysInclude = alwaysInclude
    }
}

/// Default settings for new workspaces.
public struct ConfigDefaults: Codable, Sendable {
    public var provider: String
    public var cli: String
    public var branchPrefix: String
    public var excludeDirs: [String]

    public init(
        provider: String = "github",
        cli: String = "gh",
        branchPrefix: String = "feature/",
        excludeDirs: [String] = ["node_modules", ".git", "vendor", "dist", "build", "target"]
    ) {
        self.provider = provider
        self.cli = cli
        self.branchPrefix = branchPrefix
        self.excludeDirs = excludeDirs
    }
}

/// Sidebar display preferences.
public struct SidebarSettings: Codable, Sendable {
    public var hideSessionDetails: Bool

    public init(hideSessionDetails: Bool = false) {
        self.hideSessionDetails = hideSessionDetails
    }
}
