import Foundation

/// A detected change in a session's `PRStatus` that warrants user attention.
///
/// Computed by `IssueTracker` once per polling cycle by comparing the new
/// `PRStatus` against the previous one. Pure value type — no UI/AppState deps —
/// so the comparison logic stays unit-testable.
public struct PRStatusTransition: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// A reviewer transitioned the PR into "changes requested", or a fresh
        /// formal "Request changes" review was submitted while the PR was
        /// already in `.changesRequested` (round-2; identified by review-id
        /// rotation). See `transitions(from:to:…)` for the detection rules.
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
    /// for `.checksFailing` so re-runs on the same commit don't re-fire.
    /// Carried on `.changesRequested` for downstream telemetry/UI but is not
    /// part of that dedupe key (see `dedupeKey`).
    public let headSha: String?
    /// Node ID of the most recent CHANGES_REQUESTED review when the transition
    /// fired. Sole round-2 discriminator in the `.changesRequested` dedupe
    /// key — a fresh formal review rotates this and re-arms auto-respond,
    /// while the author's own response push (which doesn't dismiss the
    /// reviewer's CHANGES_REQUESTED decision) leaves it alone and stays
    /// deduped. `nil` for providers that don't expose review IDs.
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
    /// `.changesRequested` keys on `(session, kind, latestReviewID)`. The
    /// review ID rotates only when a reviewer submits a new formal review —
    /// not when the author pushes a fix — so the auto-respond prompt that
    /// instructs the agent to "commit the fix, push, re-request review"
    /// can't trigger itself on the next poll (CROW-456 review feedback).
    ///
    /// `.checksFailing` keys on `(session, kind, headSha)` so a new commit
    /// that also fails CI can re-fire.
    public var dedupeKey: String {
        switch kind {
        case .changesRequested:
            return "\(sessionID.uuidString)|changesRequested|\(latestReviewID ?? "")"
        case .checksFailing:
            return "\(sessionID.uuidString)|checksFailing|\(headSha ?? "")"
        }
    }
}

/// Per-emitted-transition metadata persisted alongside the dedup key.
///
/// `emittedAt` lets the stalled-re-fire pass (CROW-505) enforce a quiet
/// window before re-prompting; `headShaAtEmit` is the head SHA observed at
/// dispatch, which preserves the anti-loop guarantee — a real agent push
/// advances the head SHA, so re-fire only triggers when the author has not
/// pushed since the original prompt fired.
public struct EmittedTransitionMeta: Codable, Sendable, Equatable {
    public var emittedAt: Date
    public var headShaAtEmit: String?

    public init(emittedAt: Date, headShaAtEmit: String?) {
        self.emittedAt = emittedAt
        self.headShaAtEmit = headShaAtEmit
    }
}

extension PRStatus {
    /// Compute the transitions implied by moving from `old` to `new`.
    ///
    /// On the first observation (`old == nil`), emits a transition only when
    /// the new state is itself a "needs attention" condition — `.changesRequested`
    /// or failing checks. A PR first observed as `.open` with passing/pending
    /// checks emits nothing (the startup-flood safety the bare guard used to
    /// provide). Persisted `emittedTransitionKeys` in `IssueTracker` (CROW-456)
    /// suppress restart re-fires of transitions already emitted by a prior run.
    ///
    /// Otherwise emits at most one `.changesRequested` and one `.checksFailing`,
    /// in that order.
    ///
    /// `.changesRequested` fires when the bucket is entered (`old` wasn't
    /// `.changesRequested`) or when the latest CHANGES_REQUESTED review ID
    /// rotates while still in the bucket (a fresh formal "Request changes"
    /// submission). A head-SHA change alone does **not** fire — `reviewDecision`
    /// stays `CHANGES_REQUESTED` after the author pushes, so any such trigger
    /// would re-fire on the agent's own response push and create an auto-respond
    /// loop. Real "round 2 after a fix" always involves the reviewer submitting
    /// a new formal review, which rotates the review ID.
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
        guard let old else {
            // First observation (CROW-477): emit only when the new state is
            // itself attention-needing, so a PR Crow first sees already in
            // CHANGES_REQUESTED (or with failing checks) still routes to
            // auto-respond. Restart-spurious re-fires are prevented by the
            // persisted dedupe keys at the IssueTracker layer, not here.
            var out: [PRStatusTransition] = []
            if new.reviewStatus == .changesRequested {
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
            if new.checksPass == .failing {
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

        var out: [PRStatusTransition] = []

        if new.reviewStatus == .changesRequested {
            let entering = old.reviewStatus != .changesRequested
            // Require both ids to be non-nil. If a CHANGES_REQUESTED review is
            // briefly absent from `latestReviews(first: 5)` (buried behind 5+
            // other reviewers' latest reviews) and then resurfaces with a new
            // id, the nil → id step intentionally won't fire. We prefer a
            // missed re-prompt to a spurious one — `reviewDecision` and the
            // `latestReviews`-derived id can legitimately disagree during a
            // single CHANGES_REQUESTED tenure, and a spurious fire would
            // re-prompt the agent for no reviewer action.
            let newReview = old.latestReviewID != nil
                && new.latestReviewID != nil
                && old.latestReviewID != new.latestReviewID
            if entering || newReview {
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
