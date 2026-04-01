import Foundation

/// Status of a pull request associated with a session.
public struct PRStatus: Codable, Sendable {
    public var checksPass: CheckStatus
    public var reviewStatus: ReviewStatus
    public var mergeable: MergeStatus
    public var failedCheckNames: [String]

    public init(
        checksPass: CheckStatus = .unknown,
        reviewStatus: ReviewStatus = .unknown,
        mergeable: MergeStatus = .unknown,
        failedCheckNames: [String] = []
    ) {
        self.checksPass = checksPass
        self.reviewStatus = reviewStatus
        self.mergeable = mergeable
        self.failedCheckNames = failedCheckNames
    }

    public enum CheckStatus: String, Codable, Sendable {
        case passing
        case failing
        case pending
        case unknown
    }

    public enum ReviewStatus: String, Codable, Sendable {
        case approved
        case changesRequested
        case reviewRequired
        case unknown
    }

    public enum MergeStatus: String, Codable, Sendable {
        case mergeable
        case conflicting
        case unknown
    }

    /// True if the PR is ready to merge (checks pass, approved, no conflicts).
    public var isReadyToMerge: Bool {
        checksPass == .passing && reviewStatus == .approved && mergeable == .mergeable
    }

    /// True if there are blockers preventing merge.
    public var hasBlockers: Bool {
        checksPass == .failing || reviewStatus == .changesRequested || mergeable == .conflicting
    }
}
