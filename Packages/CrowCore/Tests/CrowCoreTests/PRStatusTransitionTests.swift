import Foundation
import Testing
@testable import CrowCore

@Suite("PRStatus transitions")
struct PRStatusTransitionTests {
    private let sessionID = UUID()
    private let prURL = "https://github.com/foo/bar/pull/1"
    private let shaA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let shaB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    private func status(
        review: PRStatus.ReviewStatus = .reviewRequired,
        checks: PRStatus.CheckStatus = .pending,
        sha: String? = nil,
        failed: [String] = []
    ) -> PRStatus {
        PRStatus(
            checksPass: checks,
            reviewStatus: review,
            mergeable: .unknown,
            failedCheckNames: failed,
            headSha: sha
        )
    }

    private func compute(from old: PRStatus?, to new: PRStatus) -> [PRStatusTransition] {
        PRStatus.transitions(from: old, to: new, sessionID: sessionID, prURL: prURL, prNumber: 1)
    }

    // MARK: - First-observation gate

    @Test
    func firstObservationNeverFires() {
        // No prior status — even if the PR is already in a transition state,
        // we must not fire (it'd flood the user with notifications on every
        // app launch).
        #expect(compute(from: nil, to: status(review: .changesRequested)).isEmpty)
        #expect(compute(from: nil, to: status(checks: .failing, sha: shaA)).isEmpty)
        #expect(compute(from: nil, to: status(review: .changesRequested, checks: .failing, sha: shaA)).isEmpty)
    }

    // MARK: - Changes requested

    @Test
    func reviewRequiredToChangesRequestedFires() {
        let old = status(review: .reviewRequired)
        let new = status(review: .changesRequested)
        let ts = compute(from: old, to: new)
        #expect(ts.count == 1)
        #expect(ts.first?.kind == .changesRequested)
        #expect(ts.first?.sessionID == sessionID)
        #expect(ts.first?.prURL == prURL)
    }

    @Test
    func approvedToChangesRequestedFires() {
        let ts = compute(from: status(review: .approved), to: status(review: .changesRequested))
        #expect(ts.count == 1)
        #expect(ts.first?.kind == .changesRequested)
    }

    @Test
    func changesRequestedToChangesRequestedDoesNotFire() {
        // Status hasn't transitioned — every poll observes the same state.
        let ts = compute(from: status(review: .changesRequested), to: status(review: .changesRequested))
        #expect(ts.isEmpty)
    }

    @Test
    func changesRequestedToApprovedDoesNotFire() {
        // Reviewer approved — that's the rule clearing, not a new event to act on.
        let ts = compute(from: status(review: .changesRequested), to: status(review: .approved))
        #expect(ts.isEmpty)
    }

    // MARK: - Checks failing

    @Test
    func passingToFailingFires() {
        let old = status(checks: .passing, sha: shaA)
        let new = status(checks: .failing, sha: shaA, failed: ["lint"])
        let ts = compute(from: old, to: new)
        #expect(ts.count == 1)
        #expect(ts.first?.kind == .checksFailing)
        #expect(ts.first?.headSha == shaA)
        #expect(ts.first?.failedCheckNames == ["lint"])
    }

    @Test
    func pendingToFailingFires() {
        let ts = compute(from: status(checks: .pending, sha: shaA), to: status(checks: .failing, sha: shaA))
        #expect(ts.count == 1)
        #expect(ts.first?.kind == .checksFailing)
    }

    @Test
    func failingToFailingDoesNotFire() {
        // Pure transitions (no dedupe yet) treats this as no transition because
        // `old.checksPass == .failing` already.
        let ts = compute(from: status(checks: .failing, sha: shaA), to: status(checks: .failing, sha: shaA))
        #expect(ts.isEmpty)
    }

    @Test
    func failingToPassingDoesNotFire() {
        let ts = compute(from: status(checks: .failing, sha: shaA), to: status(checks: .passing, sha: shaA))
        #expect(ts.isEmpty)
    }

    // MARK: - Both transitions in one cycle

    @Test
    func simultaneousTransitionsFireBoth() {
        let old = status(review: .reviewRequired, checks: .pending, sha: shaA)
        let new = status(review: .changesRequested, checks: .failing, sha: shaA)
        let ts = compute(from: old, to: new)
        #expect(ts.count == 2)
        #expect(ts.contains(where: { $0.kind == .changesRequested }))
        #expect(ts.contains(where: { $0.kind == .checksFailing }))
    }

    // MARK: - Dedupe key

    @Test
    func dedupeKeyForChangesRequestedDoesNotIncludeSha() {
        // Once we've seen a changesRequested for a session, subsequent
        // re-observations of the same state must dedupe regardless of which
        // commit happens to be HEAD at the moment.
        let t1 = PRStatusTransition(kind: .changesRequested, sessionID: sessionID, prURL: prURL, prNumber: 1, headSha: shaA)
        let t2 = PRStatusTransition(kind: .changesRequested, sessionID: sessionID, prURL: prURL, prNumber: 1, headSha: shaB)
        #expect(t1.dedupeKey == t2.dedupeKey)
    }

    @Test
    func dedupeKeyForChecksFailingIncludesSha() {
        // A new commit that also fails CI must be allowed to re-fire.
        let t1 = PRStatusTransition(kind: .checksFailing, sessionID: sessionID, prURL: prURL, prNumber: 1, headSha: shaA)
        let t2 = PRStatusTransition(kind: .checksFailing, sessionID: sessionID, prURL: prURL, prNumber: 1, headSha: shaB)
        #expect(t1.dedupeKey != t2.dedupeKey)
    }
}
