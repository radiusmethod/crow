import Foundation

/// Generates and manages Claude Code hook configuration for session worktrees.
struct HookConfigGenerator {

    /// All hook event names we register.
    private static let allEvents = [
        "SessionStart", "SessionEnd", "Stop", "StopFailure",
        "Notification", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "PermissionDenied", "UserPromptSubmit",
        "TaskCreated", "TaskCompleted", "SubagentStart", "SubagentStop",
        "PreCompact", "PostCompact",
    ]

    /// Post-execution events that can safely run async (fire-and-forget).
    /// PreToolUse is intentionally NOT async — it must arrive before
    /// PermissionRequest so the state machine ordering is reliable.
    private static let asyncEvents: Set<String> = [
        "PostToolUse", "PostToolUseFailure",
    ]

    /// Marker key to identify our hooks vs user hooks.
    private static let markerComment = "crow-managed"

    // MARK: - Generate Hook Configuration

    /// Generate the hooks dictionary for a session.
    static func generateHooks(sessionID: UUID, crowPath: String) -> [String: Any] {
        let sid = sessionID.uuidString
        var hooks: [String: Any] = [:]

        for event in allEvents {
            let command = "\(crowPath) hook-event --session \(sid) --event \(event)"
            var hookEntry: [String: Any] = [
                "type": "command",
                "command": command,
                "timeout": 5,
            ]
            if asyncEvents.contains(event) {
                hookEntry["async"] = true
            }
            // Omit matcher to match all occurrences (avoids invalid regex "*")
            hooks[event] = [
                [
                    "hooks": [hookEntry],
                ] as [String: Any]
            ]
        }

        return hooks
    }

    // MARK: - Write / Merge Configuration

    /// Write hook configuration to a worktree's .claude/settings.local.json.
    /// Uses a merge strategy: preserves user settings, only updates our hook entries.
    static func writeHookConfig(
        worktreePath: String,
        sessionID: UUID,
        crowPath: String
    ) throws {
        let claudeDir = (worktreePath as NSString).appendingPathComponent(".claude")
        try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.local.json")

        // Read existing settings if present
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }

        // Get existing hooks and preserve any non-crow-managed entries
        var existingHooks = settings["hooks"] as? [String: Any] ?? [:]

        // Generate our hooks
        let ourHooks = generateHooks(sessionID: sessionID, crowPath: crowPath)

        // Merge: our hooks overwrite matching event names, user hooks for other events are preserved
        for (eventName, hookConfig) in ourHooks {
            existingHooks[eventName] = hookConfig
        }

        settings["hooks"] = existingHooks

        // Write back
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }

    /// Remove our hook entries from a worktree's settings.local.json, preserving user settings.
    static func removeHookConfig(worktreePath: String) {
        let settingsPath = (worktreePath as NSString)
            .appendingPathComponent(".claude/settings.local.json")

        guard let data = FileManager.default.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        // Remove our managed event entries
        for event in allEvents {
            hooks.removeValue(forKey: event)
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        // If settings is now empty, remove the file
        if settings.isEmpty {
            do {
                try FileManager.default.removeItem(atPath: settingsPath)
            } catch {
                NSLog("[HookConfigGenerator] Failed to remove empty settings file at %@: %@",
                      settingsPath, error.localizedDescription)
            }
        } else {
            do {
                let updatedData = try JSONSerialization.data(
                    withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                try updatedData.write(to: URL(fileURLWithPath: settingsPath))
            } catch {
                NSLog("[HookConfigGenerator] Failed to write updated settings to %@: %@",
                      settingsPath, error.localizedDescription)
            }
        }
    }

    // MARK: - Find crow Binary

    /// Find the crow binary, checking common install locations.
    static func findCrowBinary() -> String? {
        // Check same directory as running executable first (development builds)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let buildDir = execURL.deletingLastPathComponent()
        let devPath = buildDir.appendingPathComponent("crow").path
        if FileManager.default.isExecutableFile(atPath: devPath) {
            return devPath
        }

        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/crow").path,
            "/usr/local/bin/crow",
            "/opt/homebrew/bin/crow",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
