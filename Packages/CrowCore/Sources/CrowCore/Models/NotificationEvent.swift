import Foundation

/// User-facing notification event categories, mapped from raw Claude Code hook events.
///
/// Only events that require human attention trigger notifications. Most hook events
/// (e.g., tool execution, streaming responses) are intentionally unmapped — they fire
/// too frequently and don't need the user's immediate attention.
public enum NotificationEvent: String, Codable, Sendable, CaseIterable, Identifiable {
    case taskComplete
    case agentWaiting

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .taskComplete: "Task Complete"
        case .agentWaiting: "Agent Waiting"
        }
    }

    public var description: String {
        switch self {
        case .taskComplete: "Claude finished responding"
        case .agentWaiting: "Claude needs your input or permission"
        }
    }

    public var defaultSound: String {
        switch self {
        case .taskComplete: "Glass"
        case .agentWaiting: "Funk"
        }
    }

    /// Map a raw hook event name to a notification category.
    /// Returns `nil` for events that don't require human attention.
    ///
    /// - Parameters:
    ///   - eventName: The raw hook event name (e.g. "Stop", "PermissionRequest").
    ///   - toolName: The tool name from the payload, if applicable (e.g. "AskUserQuestion").
    ///   - notificationType: The notification type from the payload, if applicable (e.g. "permission_prompt").
    public static func from(
        eventName: String,
        toolName: String? = nil,
        notificationType: String? = nil
    ) -> NotificationEvent? {
        switch eventName {
        case "Stop":
            return .taskComplete

        case "PreToolUse":
            if toolName == "AskUserQuestion" { return .agentWaiting }
            return nil

        case "PermissionRequest":
            return .agentWaiting

        case "Notification":
            if notificationType == "permission_prompt" { return .agentWaiting }
            return nil

        default:
            return nil
        }
    }
}
