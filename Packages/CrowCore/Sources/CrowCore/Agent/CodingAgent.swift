import Foundation

/// A coding agent that Crow can launch in a terminal and observe via hook
/// events. Phase A wraps the existing Claude Code integration; later phases
/// introduce additional conformers.
public protocol CodingAgent: Sendable {
    /// Stable identifier for this agent implementation.
    var kind: AgentKind { get }

    /// Human-readable name shown in pickers, tooltips, and the session detail
    /// header (e.g. "Claude Code").
    var displayName: String { get }

    /// SF Symbol name rendered in the sidebar row and pickers. Kept as a
    /// string so `CrowCore` stays SwiftUI-free; consumers resolve it via
    /// `Image(systemName:)`.
    var iconSystemName: String { get }

    /// Writer for the per-worktree hook configuration file.
    var hookConfigWriter: any HookConfigWriter { get }

    /// State-machine implementation that converts hook events into
    /// `AgentStateTransition` values.
    var stateSignalSource: any StateSignalSource { get }

    /// Build the initial prompt for this agent based on the session context.
    func generatePrompt(
        session: Session,
        worktrees: [SessionWorktree],
        ticketURL: String?,
        provider: Provider?
    ) async -> String

    /// Materialize `prompt` to disk (if needed) and return the shell command
    /// that starts the agent with that prompt in `worktreePath`.
    func launchCommand(
        sessionID: UUID,
        worktreePath: String,
        prompt: String
    ) async throws -> String
}
