import Foundation

/// User-facing notification event categories, mapped from raw Claude Code hook events.
public enum NotificationEvent: String, Codable, Sendable, CaseIterable, Identifiable {
    case taskComplete
    case agentWaiting
    case sessionError
    case sessionLifecycle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .taskComplete: "Task Complete"
        case .agentWaiting: "Agent Waiting"
        case .sessionError: "Session Error"
        case .sessionLifecycle: "Session Lifecycle"
        }
    }

    public var description: String {
        switch self {
        case .taskComplete: "Claude finished responding"
        case .agentWaiting: "Claude needs your input or permission"
        case .sessionError: "An error or failure occurred"
        case .sessionLifecycle: "Session started or ended"
        }
    }

    public var defaultSound: String {
        switch self {
        case .taskComplete: "Glass"
        case .agentWaiting: "Ping"
        case .sessionError: "Basso"
        case .sessionLifecycle: "Pop"
        }
    }

    /// Map a raw hook event name to a notification category.
    /// Returns `nil` for events that should not trigger notifications.
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
            // Only notify for AskUserQuestion (agent waiting for user input)
            if toolName == "AskUserQuestion" { return .agentWaiting }
            return nil

        case "PermissionRequest":
            return .agentWaiting

        case "Notification":
            if notificationType == "permission_prompt" { return .agentWaiting }
            return nil

        case "StopFailure", "PostToolUseFailure":
            return .sessionError

        case "SessionStart", "SessionEnd":
            return .sessionLifecycle

        default:
            return nil
        }
    }
}
