import Foundation
import CrowCore

/// `CodingAgent` conformer for Claude Code. Wraps the existing `ClaudeLauncher`
/// prompt/launch-command logic and bundles the Claude-specific hook writer
/// and state-machine signal source so the main app can treat everything
/// through the generic `CodingAgent` interface.
public struct ClaudeCodeAgent: CodingAgent {
    public let kind: AgentKind = .claudeCode
    public let hookConfigWriter: any HookConfigWriter
    public let stateSignalSource: any StateSignalSource

    private let launcher: ClaudeLauncher

    public init(
        hookConfigWriter: any HookConfigWriter = ClaudeHookConfigWriter(),
        stateSignalSource: any StateSignalSource = ClaudeHookSignalSource()
    ) {
        self.hookConfigWriter = hookConfigWriter
        self.stateSignalSource = stateSignalSource
        self.launcher = ClaudeLauncher()
    }

    public func generatePrompt(
        session: Session,
        worktrees: [SessionWorktree],
        ticketURL: String?,
        provider: Provider?
    ) async -> String {
        await launcher.generatePrompt(
            session: session,
            worktrees: worktrees,
            ticketURL: ticketURL,
            provider: provider
        )
    }

    public func launchCommand(
        sessionID: UUID,
        worktreePath: String,
        prompt: String
    ) async throws -> String {
        try await launcher.launchCommand(
            sessionID: sessionID,
            worktreePath: worktreePath,
            prompt: prompt
        )
    }
}
