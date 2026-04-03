import Foundation

/// Tracks the current tool being used by Claude Code in a session.
public struct ToolActivity: Sendable {
    public let toolName: String
    public let timestamp: Date
    public let isActive: Bool

    public init(toolName: String, timestamp: Date = Date(), isActive: Bool = true) {
        self.toolName = toolName
        self.timestamp = timestamp
        self.isActive = isActive
    }
}
