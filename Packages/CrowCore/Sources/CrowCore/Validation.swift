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

    /// Detect provider from a ticket URL.
    public static func detectProviderFromURL(_ url: String) -> Provider? {
        if url.contains("github.com") {
            return .github
        } else if isJiraSpec(url) {
            return .jira
        } else if url.contains("gitlab.com") || url.contains("gitlab") || url.contains("/-/issues") || url.contains("/-/merge_requests") {
            return .gitlab
        }
        return nil
    }

    /// Whether `spec` is a Jira work item: an Atlassian Cloud host, a `/browse/`
    /// URL whose tail is a well-formed key, or a bare `PROJ-123` key. The
    /// `/browse/`-with-valid-key check (rather than a bare `/browse/` substring)
    /// avoids misrouting unrelated URLs that merely contain that path segment.
    public static func isJiraSpec(_ spec: String) -> Bool {
        if spec.contains("atlassian.net") { return true }
        if spec.contains("/browse/") { return parseJiraKey(spec) != nil }
        // Bare key (no path/host) — e.g. a pasted "PROJ-123".
        if !spec.contains("/"), parseJiraKey(spec) != nil { return true }
        return false
    }

    /// Single validated Jira work-item key parser, shared by the provider layer
    /// and the launcher prompts.
    ///
    /// Accepts a browse URL (`https://<site>.atlassian.net/browse/PROJ-123`, with
    /// optional trailing path/query/fragment) or a bare `PROJ-123`. Splits on the
    /// **last** `-` and validates the shape: an uppercase-leading alphanumeric
    /// project key, a dash, and a numeric id. A validated key contains only
    /// `[A-Z0-9-]`, so it carries no shell metacharacters — callers can safely
    /// embed it in an `acli` command line.
    ///
    /// - Returns: `(project, number, key)` or `nil` when the input doesn't yield
    ///   a well-formed key.
    public static func parseJiraKey(_ spec: String) -> (project: String, number: Int, key: String)? {
        var token = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = token.range(of: "/browse/") {
            token = String(token[r.upperBound...])
        }
        if let stop = token.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            token = String(token[..<stop])
        }
        guard let dash = token.lastIndex(of: "-") else { return nil }
        let project = String(token[..<dash])
        let numberStr = String(token[token.index(after: dash)...])
        // Project: uppercase letter then 1+ uppercase-alphanumerics (Jira keys
        // are ≥2 chars). Number: digits only.
        guard project.range(of: "^[A-Z][A-Z0-9]+$", options: .regularExpression) != nil,
              let number = Int(numberStr) else { return nil }
        return (project, number, "\(project)-\(number)")
    }

    /// Convenience: the validated key string, or `nil` when `spec` isn't a
    /// well-formed Jira key/URL.
    public static func jiraKey(from spec: String) -> String? {
        parseJiraKey(spec)?.key
    }
}
