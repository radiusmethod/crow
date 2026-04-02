import Foundation

/// Terminal configuration for a session.
public struct TerminalConfig: Sendable {
    public var workingDirectory: String
    public var claudeCommand: String?

    public init(workingDirectory: String, claudeCommand: String? = nil) {
        self.workingDirectory = workingDirectory
        self.claudeCommand = claudeCommand
    }
}
