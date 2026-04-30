import Foundation

/// Status of a pull request associated with a session.
public struct PRStatus: Codable, Sendable, Equatable {
    public var checksPass: CheckStatus
    public var reviewStatus: ReviewStatus
    public var mergeable: MergeStatus
    public var failedCheckNames: [String]
    /// Head commit SHA. Used to dedupe per-commit transition events
    /// (e.g. don't re-fire "checks failing" when the same commit is re-run).
    public var headSha: String?

    public init(
        checksPass: CheckStatus = .unknown,
        reviewStatus: ReviewStatus = .unknown,
        mergeable: MergeStatus = .unknown,
        failedCheckNames: [String] = [],
        headSha: String? = nil
    ) {
        self.checksPass = checksPass
        self.reviewStatus = reviewStatus
        self.mergeable = mergeable
        self.failedCheckNames = failedCheckNames
        self.headSha = headSha
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checksPass = try c.decodeIfPresent(CheckStatus.self, forKey: .checksPass) ?? .unknown
        reviewStatus = try c.decodeIfPresent(ReviewStatus.self, forKey: .reviewStatus) ?? .unknown
        mergeable = try c.decodeIfPresent(MergeStatus.self, forKey: .mergeable) ?? .unknown
        failedCheckNames = try c.decodeIfPresent([String].self, forKey: .failedCheckNames) ?? []
        headSha = try c.decodeIfPresent(String.self, forKey: .headSha)
    }

    private enum CodingKeys: String, CodingKey {
        case checksPass, reviewStatus, mergeable, failedCheckNames, headSha
    }

    public enum CheckStatus: String, Codable, Sendable {
        /// All CI/CD checks have passed.
        case passing
        /// One or more CI/CD checks have failed.
        case failing
        /// Checks are still running.
        case pending
        /// Check status could not be determined (e.g. no checks configured).
        case unknown
    }

    public enum ReviewStatus: String, Codable, Sendable {
        /// PR has been approved by required reviewers.
        case approved
        /// A reviewer has requested changes.
        case changesRequested
        /// Review is required but not yet submitted.
        case reviewRequired
        /// Review status could not be determined.
        case unknown
    }

    public enum MergeStatus: String, Codable, Sendable {
        /// PR can be merged (no conflicts, requirements met).
        case mergeable
        /// PR has merge conflicts that must be resolved.
        case conflicting
        /// PR has already been merged.
        case merged
        /// Merge status could not be determined.
        case unknown
    }

    /// True if the PR has been merged.
    public var isMerged: Bool {
        mergeable == .merged
    }

    /// True if the PR is ready to merge (checks pass, approved, no conflicts).
    public var isReadyToMerge: Bool {
        checksPass == .passing && reviewStatus == .approved && mergeable == .mergeable
    }

    /// True if there are blockers preventing merge.
    public var hasBlockers: Bool {
        !isMerged && (checksPass == .failing || reviewStatus == .changesRequested || mergeable == .conflicting)
    }
}
