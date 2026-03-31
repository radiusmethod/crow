import Foundation
import RmCore

/// Generates prompts and launches Claude Code in terminal sessions.
public actor ClaudeLauncher {
    public init() {}

    /// Generate the initial prompt for Claude Code (same template as /workspace skill).
    public func generatePrompt(
        session: Session,
        worktrees: [SessionWorktree],
        ticketURL: String?,
        provider: Provider?
    ) -> String {
        var lines: [String] = []
        lines.append("/plan")
        lines.append("")
        lines.append("# Workspace Context")
        lines.append("")
        lines.append("| Repository | Path | Branch | Description |")
        lines.append("|------------|------|--------|-------------|")

        for wt in worktrees {
            lines.append("| \(wt.repoName) | \(wt.worktreePath) | \(wt.branch) | \(descriptionFor(wt.repoName)) |")
        }

        if let url = ticketURL {
            lines.append("")
            lines.append("## Ticket")

            switch provider {
            case .github:
                lines.append("```bash")
                lines.append("gh issue view \(url) --comments")
                lines.append("```")
            case .gitlab:
                lines.append("```bash")
                lines.append("glab issue view \(url) --comments")
                lines.append("```")
            case nil:
                lines.append("URL: \(url)")
            }
        }

        lines.append("")
        lines.append("## Instructions")
        lines.append("1. Study the ticket thoroughly, including all comments and related tickets as well as each of the repos, with the intent of accomplishing the ticket")
        lines.append("2. Create an implementation plan")

        return lines.joined(separator: "\n")
    }

    /// Write prompt to temp file and return the launch command.
    public func launchCommand(sessionID: UUID, worktreePath: String, prompt: String) throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        let promptPath = tmpDir.appendingPathComponent("rmide-\(sessionID.uuidString)-prompt.md")
        try prompt.write(to: promptPath, atomically: true, encoding: .utf8)
        return "cd \(worktreePath) && claude \"$(cat \(promptPath.path))\"\n"
    }

    private func descriptionFor(_ repoName: String) -> String {
        switch repoName {
        case "bigbang": "Umbrella Helm chart that loads in specific product packages"
        case "overrides": "Helm install overrides used for testing; create overrides here when testing changes"
        case "codename-spotlight": "Infrastructure monorepo containing Citadel, SocketZero, and related services"
        default: ""
        }
    }
}
