import Foundation

/// Creates the devRoot directory structure and copies bundled resources.
struct Scaffolder {
    let devRoot: String

    /// Create the full workspace scaffold.
    func scaffold(workspaceNames: [String]) throws {
        let fm = FileManager.default

        // Create devRoot
        try fm.createDirectory(atPath: devRoot, withIntermediateDirectories: true)

        // Create workspace subdirectories
        for name in workspaceNames {
            let wsPath = (devRoot as NSString).appendingPathComponent(name)
            try fm.createDirectory(atPath: wsPath, withIntermediateDirectories: true)
        }

        // Create .claude directory structure
        let claudeDir = (devRoot as NSString).appendingPathComponent(".claude")
        let skillsDir = (claudeDir as NSString).appendingPathComponent("skills/ride-workspace")
        try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        // Always update CLAUDE.md — but preserve the "Known Issues / Corrections" section
        let claudeMDPath = (claudeDir as NSString).appendingPathComponent("CLAUDE.md")
        let template = Self.bundledCLAUDEMD()
        if fm.fileExists(atPath: claudeMDPath),
           let existing = try? String(contentsOfFile: claudeMDPath, encoding: .utf8),
           let range = existing.range(of: "## Known Issues / Corrections") {
            // Preserve user corrections, replace everything above
            let userCorrections = String(existing[range.lowerBound...])
            let templateBase: String
            if let templateRange = template.range(of: "## Known Issues / Corrections") {
                templateBase = String(template[..<templateRange.lowerBound])
            } else {
                templateBase = template + "\n\n"
            }
            try (templateBase + userCorrections).write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        } else {
            try template.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        }

        // Always overwrite the skill with the latest version from the app
        let skillPath = (skillsDir as NSString).appendingPathComponent("SKILL.md")
        let skillTemplate = Self.bundledSkill()
        try skillTemplate.write(toFile: skillPath, atomically: true, encoding: .utf8)

        // Always overwrite settings.json (permissions for ride, gh, git commands)
        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.json")
        let settingsTemplate = Self.bundledSettings()
        try settingsTemplate.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        // Create prompts directory for ride-workspace prompt files
        let promptsDir = (claudeDir as NSString).appendingPathComponent("prompts")
        try fm.createDirectory(atPath: promptsDir, withIntermediateDirectories: true)
    }

    // MARK: - Bundled Templates

    /// The CLAUDE.md template bundled with the app.
    static func bundledCLAUDEMD() -> String {
        // Try loading from the repo's CLAUDE.md (for development builds)
        if let content = loadFromRepo("CLAUDE.md") {
            return content
        }
        // Try Bundle.main (for .app bundles)
        if let url = Bundle.main.url(forResource: "CLAUDE", withExtension: "md"),
           let content = try? String(contentsOf: url) {
            return content
        }
        // Minimal fallback
        return """
        # rm-ai-ide (ride) — Manager Context

        See ride --help for CLI reference.
        All ride commands require dangerouslyDisableSandbox: true.
        All gh/glab commands require dangerouslyDisableSandbox: true.
        Write temp files to $TMPDIR, not /tmp.

        ## Known Issues / Corrections
        """
    }

    /// The ride-workspace SKILL.md template bundled with the app.
    static func bundledSkill() -> String {
        if let content = loadFromRepo("skills/ride-workspace/SKILL.md") {
            return content
        }
        if let url = Bundle.main.url(forResource: "ride-workspace-SKILL.md", withExtension: "template"),
           let content = try? String(contentsOf: url) {
            return content
        }
        return """
        # ride Workspace Setup Skill

        ## Activation
        This skill activates when user invokes `/ride-workspace` command.

        ## Important
        All `ride` CLI commands require `dangerouslyDisableSandbox: true`.
        See the CLAUDE.md in this directory for the full ride CLI reference.
        """
    }

    /// The settings.json template with pre-approved permissions.
    static func bundledSettings() -> String {
        if let content = loadFromRepo("settings.json") {
            return content
        }
        // Fallback
        return """
        {
          "permissions": {
            "allow": [
              "Bash(ride *)",
              "Bash(gh issue view:*)",
              "Bash(gh pr view:*)",
              "Bash(GITLAB_HOST=* glab issue view:*)",
              "Bash(GITLAB_HOST=* glab mr view:*)",
              "Bash(git -C:*)",
              "Bash(git fetch:*)",
              "Bash(git worktree:*)",
              "Bash(git ls-remote:*)",
              "Bash(git branch:*)",
              "Bash(mkdir -p:*)",
              "Bash(cat >:*)",
              "Bash(ls:*)",
              "Bash(which:*)",
              "Bash(sleep:*)"
            ]
          }
        }
        """
    }

    /// Try to load a file from the repo root (for development builds).
    private static func loadFromRepo(_ relativePath: String) -> String? {
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                let filePath = dir.appendingPathComponent(relativePath)
                return try? String(contentsOf: filePath)
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
