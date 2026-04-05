import Foundation

/// Shared validation helpers used by the app and socket server.
public enum Validation {
    /// Maximum allowed length for session names.
    public static let maxSessionNameLength = 256

    /// Check whether a path is within the given root directory (prevents path traversal).
    public static func isPathWithinRoot(_ path: String, root: String) -> Bool {
        let realPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let realRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return realPath.hasPrefix(realRoot + "/") || realPath == realRoot
    }

    /// Validate a session name contains no control characters and is within length limits.
    public static func isValidSessionName(_ name: String) -> Bool {
        !name.isEmpty
            && name.count <= maxSessionNameLength
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
