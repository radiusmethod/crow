import Foundation

/// Result of expanding a workspace's `alwaysInclude` specs into repos for the
/// Jobs form's repo picker.
///
/// Carries the resolved `owner/repo` slugs *and* any specs that couldn't be
/// resolved, so the UI can tell apart "nothing configured" / "invalid spec(s)" /
/// "valid specs that returned nothing" instead of showing a bare "No repos found".
public struct WorkspaceRepoListing: Sendable, Equatable {
    /// A spec that classified as unusable, with a suggested fix when there is a
    /// clean one (e.g. a bare org name `securityscorecard` → `securityscorecard/*`).
    public struct InvalidSpec: Sendable, Equatable {
        public let raw: String
        public let suggestion: String?
        public init(raw: String, suggestion: String?) {
            self.raw = raw
            self.suggestion = suggestion
        }
    }

    /// Resolved, sorted, de-duplicated `owner/repo` slugs.
    public let repos: [String]
    /// Specs that couldn't be resolved (surfaced to the user with a hint).
    public let invalidSpecs: [InvalidSpec]

    public init(repos: [String], invalidSpecs: [InvalidSpec]) {
        self.repos = repos
        self.invalidSpecs = invalidSpecs
    }

    public static let empty = WorkspaceRepoListing(repos: [], invalidSpecs: [])
}
