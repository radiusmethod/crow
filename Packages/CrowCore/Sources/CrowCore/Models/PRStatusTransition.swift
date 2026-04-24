import Foundation

/// A detected change in a session's `PRStatus` that warrants user attention.
///
/// Computed by `IssueTracker` once per polling cycle by comparing the new
/// `PRStatus` against the previous one. Pure value type — no UI/AppState deps —
/// so the comparison logic stays unit-testable.
public struct PRStatusTransition: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// A reviewer transitioned the PR into "changes requested".
        case changesRequested
        /// At least one CI/CD check newly transitioned to failing on the
        /// current head commit.
        case checksFailing
    }

    public let kind: Kind
    public let sessionID: UUID
    public let prURL: String
    public let prNumber: Int?
    /// Head commit SHA at the moment of the transition. Used as part of the
    /// dedupe key for `.checksFailing` so re-runs on the same commit don't
    /// re-fire.
    public let headSha: String?
    /// Names of failing checks (empty for `.changesRequested`).
    public let failedCheckNames: [String]

    public init(
        kind: Kind,
        sessionID: UUID,
        prURL: String,
        prNumber: Int? = nil,
        headSha: String? = nil,
        failedCheckNames: [String] = []
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.prURL = prURL
        self.prNumber = prNumber
        self.headSha = headSha
        self.failedCheckNames = failedCheckNames
    }

    /// Stable key used to suppress duplicate fires across polling cycles.
    /// `.changesRequested` keys on `(session, kind)` — the rule re-arms when
    /// the status moves away from `.changesRequested`. `.checksFailing` keys
    /// on `(session, kind, headSha)` so a new commit can re-fire.
    public var dedupeKey: String {
        switch kind {
        case .changesRequested:
            return "\(sessionID.uuidString)|changesRequested"
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

        if old.reviewStatus != .changesRequested && new.reviewStatus == .changesRequested {
            out.append(PRStatusTransition(
                kind: .changesRequested,
                sessionID: sessionID,
                prURL: prURL,
                prNumber: prNumber,
                headSha: new.headSha,
                failedCheckNames: []
            ))
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
