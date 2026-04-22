import Foundation

/// Application configuration stored at `{devRoot}/.claude/config.json`.
///
/// All top-level fields are optional on decode — missing keys fall back to defaults.
/// This means existing config files continue to work when new settings are added
/// (forward compatibility).
public struct AppConfig: Codable, Sendable, Equatable {
    public var workspaces: [WorkspaceInfo]
    public var defaults: ConfigDefaults
    public var notifications: NotificationSettings
    public var sidebar: SidebarSettings
    public var remoteControlEnabled: Bool
    public var managerAutoPermissionMode: Bool
    public var telemetry: TelemetryConfig

    public init(
        workspaces: [WorkspaceInfo] = [],
        defaults: ConfigDefaults = ConfigDefaults(),
        notifications: NotificationSettings = NotificationSettings(),
        sidebar: SidebarSettings = SidebarSettings(),
        remoteControlEnabled: Bool = false,
        managerAutoPermissionMode: Bool = true,
        telemetry: TelemetryConfig = TelemetryConfig()
    ) {
        self.workspaces = workspaces
        self.defaults = defaults
        self.notifications = notifications
        self.sidebar = sidebar
        self.remoteControlEnabled = remoteControlEnabled
        self.managerAutoPermissionMode = managerAutoPermissionMode
        self.telemetry = telemetry
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try container.decodeIfPresent([WorkspaceInfo].self, forKey: .workspaces) ?? []
        defaults = try container.decodeIfPresent(ConfigDefaults.self, forKey: .defaults) ?? ConfigDefaults()
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? NotificationSettings()
        sidebar = try container.decodeIfPresent(SidebarSettings.self, forKey: .sidebar) ?? SidebarSettings()
        remoteControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteControlEnabled) ?? false
        managerAutoPermissionMode = try container.decodeIfPresent(Bool.self, forKey: .managerAutoPermissionMode) ?? true
        telemetry = try container.decodeIfPresent(TelemetryConfig.self, forKey: .telemetry) ?? TelemetryConfig()
    }

    private enum CodingKeys: String, CodingKey {
        case workspaces, defaults, notifications, sidebar, remoteControlEnabled, managerAutoPermissionMode, telemetry
    }
}

/// A workspace folder configuration.
///
/// Each workspace maps to a directory under the dev root (e.g., `~/Dev/MyOrg`).
/// The `provider` field determines which forge is used (GitHub or GitLab),
/// and `cli` stores the corresponding CLI tool name for backward compatibility.
/// Prefer `derivedCLI` in new code — it's always consistent with `provider`.
public struct WorkspaceInfo: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var provider: String       // "github" or "gitlab"
    public var cli: String            // "gh" or "glab" — kept for config file compat
    public var host: String?          // GitLab host (e.g., "gitlab.example.com")
    public var alwaysInclude: [String] // repos to always list in prompt table

    /// The CLI tool name derived from the current `provider` value.
    /// Unlike `cli` (which may be stale from an old config file), this is always correct.
    public var derivedCLI: String {
        provider == "github" ? "gh" : "glab"
    }

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

    /// Characters that are unsafe in directory names (workspace names become directory names).
    private static let unsafeCharacters = CharacterSet(charactersIn: "/:\0")

    /// Validate a workspace name, returning an error message or `nil` if valid.
    ///
    /// - Parameters:
    ///   - name: The trimmed workspace name to validate.
    ///   - existingNames: Names of other workspaces (for duplicate detection).
    /// - Returns: A human-readable error string, or `nil` if the name is valid.
    public static func validateName(_ name: String, existingNames: [String]) -> String? {
        if name.isEmpty {
            return "Name is required"
        }
        if name.unicodeScalars.contains(where: { unsafeCharacters.contains($0) }) {
            return "Name cannot contain /, :, or null characters"
        }
        let lowercased = name.lowercased()
        if existingNames.contains(where: { $0.lowercased() == lowercased }) {
            return "A workspace with this name already exists"
        }
        return nil
    }
}

/// Default settings applied when creating new workspaces or sessions.
public struct ConfigDefaults: Codable, Sendable, Equatable {
    public var provider: String
    public var cli: String
    public var branchPrefix: String
    public var excludeDirs: [String]

    /// Characters that are invalid in git ref names (see `git check-ref-format`).
    private static let invalidBranchChars = CharacterSet(charactersIn: " ~^:?*[\\")

    /// Check whether a branch prefix is valid for use in git ref names.
    ///
    /// Rejects prefixes containing characters forbidden by `git check-ref-format`,
    /// as well as patterns like consecutive dots or a trailing dot/slash.
    public static func isValidBranchPrefix(_ prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true } // empty is allowed (means no prefix)
        if prefix.unicodeScalars.contains(where: { invalidBranchChars.contains($0) }) {
            return false
        }
        if prefix.contains("..") { return false }
        if prefix.hasSuffix(".") { return false }
        if prefix.contains("@{") { return false }
        return true
    }

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
public struct SidebarSettings: Codable, Sendable, Equatable {
    public var hideSessionDetails: Bool

    public init(hideSessionDetails: Bool = false) {
        self.hideSessionDetails = hideSessionDetails
    }
}

/// Telemetry collection settings for Claude Code OTLP metrics.
public struct TelemetryConfig: Codable, Sendable, Equatable {
    /// Whether the OTLP receiver is enabled.
    public var enabled: Bool
    /// Port for the OTLP HTTP receiver (default: 4318).
    public var port: UInt16
    /// Number of days to retain telemetry data. 0 disables pruning (keep forever).
    public var retentionDays: Int

    public init(enabled: Bool = false, port: UInt16 = 4318, retentionDays: Int = 180) {
        self.enabled = enabled
        self.port = port
        self.retentionDays = retentionDays
    }
}
