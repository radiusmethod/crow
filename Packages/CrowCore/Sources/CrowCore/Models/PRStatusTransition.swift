import Foundation

/// A detected change in a session's `PRStatus` that warrants user attention.
///
/// Computed by `IssueTracker` once per polling cycle by comparing the new
/// `PRStatus` against the previous one. Pure value type — no UI/AppState deps —
/// so the comparison logic stays unit-testable.
public struct PRStatusTransition: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// A reviewer transitioned the PR into "changes requested", or a new
        /// round of changes-requested activity occurred while the PR was still
        /// in `.changesRequested` (new formal review, or new commit pushed
        /// after the prior review). See `transitions(from:to:…)` for the
        /// round-2 detection rules.
        case changesRequested
        /// At least one CI/CD check newly transitioned to failing on the
        /// current head commit.
        case checksFailing
    }

    public let kind: Kind
    public let sessionID: UUID
    public let prURL: String
    public let prNumber: Int?
    /// Head commit SHA at the moment of the transition. Part of the dedupe key
    /// for both `.checksFailing` (re-runs on the same commit must not re-fire)
    /// and `.changesRequested` (a post-commit push while still in
    /// changes-requested must re-arm — CROW-456).
    public let headSha: String?
    /// Node ID of the most recent CHANGES_REQUESTED review when the transition
    /// fired. Part of the `.changesRequested` dedupe key so a second formal
    /// "Request changes" submission re-arms auto-respond even when the bucket
    /// hasn't moved. `nil` for providers that don't expose review IDs.
    public let latestReviewID: String?
    /// Names of failing checks (empty for `.changesRequested`).
    public let failedCheckNames: [String]

    public init(
        kind: Kind,
        sessionID: UUID,
        prURL: String,
        prNumber: Int? = nil,
        headSha: String? = nil,
        latestReviewID: String? = nil,
        failedCheckNames: [String] = []
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.prURL = prURL
        self.prNumber = prNumber
        self.headSha = headSha
        self.latestReviewID = latestReviewID
        self.failedCheckNames = failedCheckNames
    }

    /// Stable key used to suppress duplicate fires across polling cycles.
    ///
    /// `.changesRequested` includes both the latest CHANGES_REQUESTED review
    /// ID and the head SHA, so:
    /// - the same review observed twice → same key → deduped
    /// - a new formal "Request changes" → new review ID → fires
    /// - a new commit after the prior review → new SHA → fires
    ///
    /// `.checksFailing` keys on `(session, kind, headSha)` so a new commit
    /// that also fails CI can re-fire.
    public var dedupeKey: String {
        switch kind {
        case .changesRequested:
            return "\(sessionID.uuidString)|changesRequested|\(latestReviewID ?? "")|\(headSha ?? "")"
        case .checksFailing:
            return "\(sessionID.uuidString)|checksFailing|\(headSha ?? "")"
        }
    }
}

extension PRStatus {
    /// Compute the transitions implied by moving from `old` to `new`.
    ///
    /// Returns an empty array on the first observation (`old == nil`) so
    /// existing PR state never triggers a fire-on-startup. Otherwise emits
    /// at most one `.changesRequested` and one `.checksFailing`, in that order.
    ///
    /// For `.changesRequested`, fires on any of:
    /// - Entering the bucket (old wasn't in `.changesRequested`).
    /// - Same bucket, new review ID (a second formal "Request changes").
    /// - Same bucket, new head SHA (agent pushed a fix after the prior
    ///   review; reviewer's next pass should re-prompt the agent).
    ///
    /// - Note: This is the pure piece of the transition pipeline; the
    ///   stateful dedupe (across polls) lives in `IssueTracker`.
    public static func transitions(
        from old: PRStatus?,
        to new: PRStatus,
        sessionID: UUID,
        prURL: String,
        prNumber: Int?
    ) -> [PRStatusTransition] {
        guard let old else { return [] } // first observation — never fire

        var out: [PRStatusTransition] = []

        if new.reviewStatus == .changesRequested {
            let entering = old.reviewStatus != .changesRequested
            let newReview = old.latestReviewID != nil
                && new.latestReviewID != nil
                && old.latestReviewID != new.latestReviewID
            let postCommitPush = old.reviewStatus == .changesRequested
                && old.headSha != new.headSha
                && new.headSha != nil
            if entering || newReview || postCommitPush {
                out.append(PRStatusTransition(
                    kind: .changesRequested,
                    sessionID: sessionID,
                    prURL: prURL,
                    prNumber: prNumber,
                    headSha: new.headSha,
                    latestReviewID: new.latestReviewID,
                    failedCheckNames: []
                ))
            }
        }

        if old.checksPass != .failing && new.checksPass == .failing {
            out.append(PRStatusTransition(
                kind: .checksFailing,
                sessionID: sessionID,
                prURL: prURL,
                prNumber: prNumber,
                headSha: new.headSha,
                failedCheckNames: new.failedCheckNames
            ))
        }

        return out
    }
}
