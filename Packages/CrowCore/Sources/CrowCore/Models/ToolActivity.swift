import Foundation

/// Tracks the current tool being used by Claude Code in a session.
///
/// Updated via `PreToolUse` and `PostToolUse` hook events to show which tool
/// Claude is actively executing (e.g. "Bash", "Read", "Edit").
public struct ToolActivity: Sendable {
    /// The name of the tool (e.g. "Bash", "Read", "Edit").
    public let toolName: String
    /// When this activity was recorded.
    public let timestamp: Date
    /// Whether the tool is currently executing (`true`) or has completed (`false`).
    public let isActive: Bool

    public init(toolName: String, timestamp: Date = Date(), isActive: Bool = true) {
        self.toolName = toolName
        self.timestamp = timestamp
        self.isActive = isActive
    }
}
