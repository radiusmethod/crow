import Foundation
import Testing
@testable import CrowClaude
@testable import CrowCore

// MARK: - generatePrompt()

@Test func generatePromptWithGitHubProvider() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "test-session")
    let worktree = SessionWorktree(
        sessionID: session.id,
        repoName: "my-repo",
        repoPath: "/repos/my-repo",
        worktreePath: "/worktrees/my-repo-42-feature",
        branch: "feature/42-cool"
    )

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [worktree],
        ticketURL: "https://github.com/org/repo/issues/42",
        provider: .github
    )

    #expect(prompt.hasPrefix("/plan"))
    #expect(prompt.contains("| my-repo |"))
    #expect(prompt.contains("feature/42-cool"))
    #expect(prompt.contains("gh issue view"))
    #expect(prompt.contains("dangerouslyDisableSandbox"))
}

@Test func generatePromptWithGitLabProvider() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "test-session")

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [],
        ticketURL: "https://gitlab.com/org/repo/-/issues/10",
        provider: .gitlab
    )

    #expect(prompt.contains("glab issue view"))
    #expect(prompt.contains("dangerouslyDisableSandbox"))
}

@Test func generatePromptWithNilProvider() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "test-session")

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [],
        ticketURL: "https://example.com/ticket/1",
        provider: nil
    )

    #expect(prompt.contains("URL: https://example.com/ticket/1"))
    #expect(!prompt.contains("gh issue"))
    #expect(!prompt.contains("glab issue"))
}

@Test func generatePromptWithNoTicket() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "test-session")
    let worktree = SessionWorktree(
        sessionID: session.id,
        repoName: "repo",
        repoPath: "/repos/repo",
        worktreePath: "/worktrees/repo-1-feat",
        branch: "feature/1-feat"
    )

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [worktree],
        ticketURL: nil,
        provider: nil
    )

    #expect(prompt.hasPrefix("/plan"))
    #expect(prompt.contains("| repo |"))
    #expect(!prompt.contains("## Ticket"))
}

@Test func generatePromptWithEmptyWorktrees() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "test-session")

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [],
        ticketURL: nil,
        provider: nil
    )

    #expect(prompt.contains("| Repository | Path | Branch | Description |"))
    #expect(prompt.contains("## Instructions"))
}

// MARK: - launchCommand()

@Test func launchCommandWritesTempFile() async throws {
    let launcher = ClaudeLauncher()
    let sessionID = UUID()
    let command = try await launcher.launchCommand(
        sessionID: sessionID,
        worktreePath: "/test/path",
        prompt: "test prompt"
    )

    #expect(command.contains("claude"))
    #expect(command.contains("cd"))

    // Verify temp file was created
    let tmpDir = FileManager.default.temporaryDirectory
    let promptPath = tmpDir.appendingPathComponent("rmide-\(sessionID.uuidString)-prompt.md")
    let content = try String(contentsOf: promptPath, encoding: .utf8)
    #expect(content == "test prompt")

    // Verify file permissions (owner-only read/write)
    let attrs = try FileManager.default.attributesOfItem(atPath: promptPath.path)
    let permissions = attrs[.posixPermissions] as? Int
    #expect(permissions == 0o600)

    // Clean up
    try? FileManager.default.removeItem(at: promptPath)
}

@Test func launchCommandEscapesSingleQuotes() async throws {
    let launcher = ClaudeLauncher()
    let command = try await launcher.launchCommand(
        sessionID: UUID(),
        worktreePath: "/path/with'quote",
        prompt: "test"
    )

    // The path should be shell-escaped with single-quote handling
    #expect(command.contains("'\\''"))
}

// MARK: - Prompt structure

@Test func generatePromptMultipleWorktrees() async {
    let launcher = ClaudeLauncher()
    let session = Session(name: "multi-repo")
    let wt1 = SessionWorktree(
        sessionID: session.id,
        repoName: "frontend",
        repoPath: "/repos/frontend",
        worktreePath: "/wt/frontend-1-feat",
        branch: "feature/1-feat"
    )
    let wt2 = SessionWorktree(
        sessionID: session.id,
        repoName: "backend",
        repoPath: "/repos/backend",
        worktreePath: "/wt/backend-1-feat",
        branch: "feature/1-feat"
    )

    let prompt = await launcher.generatePrompt(
        session: session,
        worktrees: [wt1, wt2],
        ticketURL: nil,
        provider: nil
    )

    #expect(prompt.contains("| frontend |"))
    #expect(prompt.contains("| backend |"))
}
