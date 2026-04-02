import Foundation

/// A pending notification from Claude Code that needs user attention.
public struct HookNotification: Sendable {
    public let message: String
    public let notificationType: String
    public let timestamp: Date

    public init(message: String, notificationType: String, timestamp: Date = Date()) {
        self.message = message
        self.notificationType = notificationType
        self.timestamp = timestamp
    }
}
