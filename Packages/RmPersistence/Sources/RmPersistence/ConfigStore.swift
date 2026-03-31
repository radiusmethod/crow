import Foundation
import RmCore

/// Manages the devRoot pointer and workspace config.
public final class ConfigStore: Sendable {
    private static let appSupportDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("rm-ai-ide", isDirectory: true)
    }()

    private static let devRootPointerPath: URL = appSupportDir.appendingPathComponent("devroot")

    // MARK: - devRoot Pointer

    /// Read the devRoot path from ~/Library/Application Support/rm-ai-ide/devroot
    public static func loadDevRoot() -> String? {
        guard let data = try? Data(contentsOf: devRootPointerPath),
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return path
    }

    /// Write the devRoot path.
    public static func saveDevRoot(_ path: String) throws {
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try path.write(to: devRootPointerPath, atomically: true, encoding: .utf8)
    }

    // MARK: - App Config

    /// Load config from {devRoot}/.claude/config.json
    public static func loadConfig(devRoot: String) -> AppConfig? {
        let configURL = URL(fileURLWithPath: devRoot)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Save config to {devRoot}/.claude/config.json
    public static func saveConfig(_ config: AppConfig, devRoot: String) throws {
        let claudeDir = URL(fileURLWithPath: devRoot).appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let configURL = claudeDir.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Import from CMUX workspace-repos.json

    /// Try to import config from ~/.claude/workspace-repos.json (CMUX format).
    public static func importFromCMUX() -> (devRoot: String, config: AppConfig)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cmuxPath = home.appendingPathComponent(".claude/workspace-repos.json")
        guard let data = try? Data(contentsOf: cmuxPath),
              let cmux = try? JSONDecoder().decode(WorkspaceConfig.self, from: data) else {
            return nil
        }

        let workspaces = cmux.workspaces.map { (name, entry) in
            WorkspaceInfo(
                name: name,
                provider: entry.provider,
                cli: entry.cli,
                host: entry.host,
                alwaysInclude: entry.alwaysInclude ?? []
            )
        }

        let config = AppConfig(
            workspaces: workspaces,
            defaults: ConfigDefaults(
                provider: cmux.defaults.provider,
                cli: cmux.defaults.cli,
                branchPrefix: cmux.defaults.branchPrefix,
                excludeDirs: cmux.defaults.excludeDirs
            )
        )

        return (devRoot: cmux.devRoot, config: config)
    }
}
