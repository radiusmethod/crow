import Foundation
import SwiftUI
import Testing
@testable import CrowCore
@testable import CrowUI

// MARK: - SessionStatus Display Names

@Test func sessionStatusDisplayNames() {
    #expect(SessionStatus.active.displayName == "Active")
    #expect(SessionStatus.paused.displayName == "Paused")
    #expect(SessionStatus.inReview.displayName == "In Review")
    #expect(SessionStatus.completed.displayName == "Completed")
    #expect(SessionStatus.archived.displayName == "Archived")
}

// MARK: - TicketStatus Colors

@Test func ticketStatusColorsAreDefined() {
    for status in TicketStatus.allCases {
        _ = status.color
    }
}

// MARK: - PR Check/Review Status Extensions

@Test func checkStatusIcons() {
    #expect(PRStatus.CheckStatus.passing.icon == "checkmark.circle.fill")
    #expect(PRStatus.CheckStatus.failing.icon == "xmark.circle.fill")
    #expect(PRStatus.CheckStatus.pending.icon == "clock.fill")
    #expect(PRStatus.CheckStatus.unknown.icon == "questionmark.circle")
}

@Test func checkStatusLabels() {
    #expect(PRStatus.CheckStatus.passing.label == "Checks pass")
    #expect(PRStatus.CheckStatus.failing.label == "Checks failing")
    #expect(PRStatus.CheckStatus.pending.label == "Checks running")
    #expect(PRStatus.CheckStatus.unknown.label == "No checks")
}

@Test func reviewStatusIcons() {
    #expect(PRStatus.ReviewStatus.approved.icon == "person.crop.circle.badge.checkmark")
    #expect(PRStatus.ReviewStatus.changesRequested.icon == "person.crop.circle.badge.exclamationmark")
    #expect(PRStatus.ReviewStatus.reviewRequired.icon == "person.crop.circle.badge.clock")
    #expect(PRStatus.ReviewStatus.unknown.icon == "person.crop.circle")
}

@Test func reviewStatusLabels() {
    #expect(PRStatus.ReviewStatus.approved.label == "Approved")
    #expect(PRStatus.ReviewStatus.changesRequested.label == "Changes requested")
    #expect(PRStatus.ReviewStatus.reviewRequired.label == "Needs review")
    #expect(PRStatus.ReviewStatus.unknown.label == "No reviews")
}

// MARK: - Branch Shortening

@Test func shortenBranchStripsFeaturePrefix() {
    #expect(shortenBranch("feature/crow-73-quality-pass") == "crow-73-quality-pass")
}

@Test func shortenBranchStripsRefsHeads() {
    #expect(shortenBranch("refs/heads/main") == "main")
}

@Test func shortenBranchStripsBothPrefixes() {
    #expect(shortenBranch("refs/heads/feature/my-branch") == "my-branch")
}

@Test func shortenBranchLeavesPlainBranch() {
    #expect(shortenBranch("main") == "main")
}

// MARK: - Helper to create test worktrees

private func makeWorktree(
    repoPath: String = "/repo",
    repoName: String = "repo",
    worktreePath: String = "/worktree",
    branch: String = "feature/test"
) -> SessionWorktree {
    SessionWorktree(
        sessionID: UUID(),
        repoName: repoName,
        repoPath: repoPath,
        worktreePath: worktreePath,
        branch: branch
    )
}

// MARK: - Worktree Classification (uses SessionWorktree.isMainRepoCheckout from CrowCore)

@Test func isMainCheckoutDetectsMatchingPaths() {
    let wt = makeWorktree(
        repoPath: "/Users/test/Dev/Org/repo",
        worktreePath: "/Users/test/Dev/Org/repo",
        branch: "feature/something"
    )
    #expect(wt.isMainRepoCheckout == true)
}

@Test func isMainCheckoutDetectsProtectedBranches() {
    let protectedBranches = ["main", "master", "develop", "dev", "trunk", "release"]
    for branch in protectedBranches {
        let wt = makeWorktree(branch: branch)
        #expect(wt.isMainRepoCheckout == true, "Expected \(branch) to be a main checkout")
    }
}

@Test func isMainCheckoutDetectsProtectedBranchesWithPrefix() {
    let wt = makeWorktree(branch: "refs/heads/main")
    #expect(wt.isMainRepoCheckout == true)
}

@Test func isMainCheckoutReturnsFalseForFeatureBranch() {
    let wt = makeWorktree(branch: "feature/crow-73-quality-pass")
    #expect(wt.isMainRepoCheckout == false)
}

// MARK: - Delete Session Message Logic

@Test func deleteMessageForSessionWithoutWorktrees() {
    let text = DeleteSessionMessageBuilder.buildMessage(
        sessionName: "test-session",
        realWorktrees: [],
        mainCheckouts: []
    )
    #expect(text == "This will remove the session \"test-session\".")
}

@Test func deleteMessageForSessionWithOnlyMainCheckout() {
    let wt = makeWorktree(
        repoPath: "/repo",
        worktreePath: "/repo",
        branch: "main"
    )
    let text = DeleteSessionMessageBuilder.buildMessage(
        sessionName: "test",
        realWorktrees: [],
        mainCheckouts: [wt]
    )
    #expect(text.contains("will not be affected"))
}

@Test func deleteButtonLabelReflectsWorktrees() {
    #expect(DeleteSessionMessageBuilder.buttonLabel(hasRealWorktrees: true) == "Delete Everything")
    #expect(DeleteSessionMessageBuilder.buttonLabel(hasRealWorktrees: false) == "Remove Session")
}

// MARK: - Bulk Delete Message Logic

@Test func bulkMessageForSessionsWithoutWorktrees() {
    let sessions = [
        Session(name: "alpha"),
        Session(name: "bravo"),
        Session(name: "charlie")
    ]
    let text = DeleteSessionMessageBuilder.buildBulkMessage(
        sessions: sessions,
        worktreesBySession: [:]
    )
    #expect(text == "This will remove 3 sessions.")
}

@Test func bulkMessageForSingleSessionUsesSingularNoun() {
    let session = Session(name: "solo")
    let text = DeleteSessionMessageBuilder.buildBulkMessage(
        sessions: [session],
        worktreesBySession: [:]
    )
    #expect(text == "This will remove 1 session.")
}

@Test func bulkMessageWithRealWorktreesMentionsCounts() {
    let session = Session(name: "feat")
    let wt = SessionWorktree(
        sessionID: session.id,
        repoName: "repo",
        repoPath: "/repo",
        worktreePath: "/worktrees/feat",
        branch: "feature/test"
    )
    let text = DeleteSessionMessageBuilder.buildBulkMessage(
        sessions: [session],
        worktreesBySession: [session.id: [wt]]
    )
    #expect(text.contains("This will delete 1 session."))
    #expect(text.contains("1 worktree"))
    #expect(text.contains("removed from disk"))
}

@Test func bulkMessageWithMixedWorktreesMentionsBoth() {
    let s1 = Session(name: "feat-a")
    let s2 = Session(name: "feat-b")
    let realWt = SessionWorktree(
        sessionID: s1.id,
        repoName: "repo",
        repoPath: "/repo",
        worktreePath: "/worktrees/feat-a",
        branch: "feature/a"
    )
    let mainWt = SessionWorktree(
        sessionID: s2.id,
        repoName: "repo",
        repoPath: "/repo",
        worktreePath: "/repo",
        branch: "main"
    )
    let text = DeleteSessionMessageBuilder.buildBulkMessage(
        sessions: [s1, s2],
        worktreesBySession: [s1.id: [realWt], s2.id: [mainWt]]
    )
    #expect(text.contains("This will delete 2 sessions."))
    #expect(text.contains("1 worktree"))
    #expect(text.contains("1 main repo checkout will not be affected"))
}

@Test func bulkMessageWithOnlyMainCheckoutsSkipsRealWorktreeLine() {
    let session = Session(name: "main-only")
    let mainWt = SessionWorktree(
        sessionID: session.id,
        repoName: "repo",
        repoPath: "/repo",
        worktreePath: "/repo",
        branch: "main"
    )
    let text = DeleteSessionMessageBuilder.buildBulkMessage(
        sessions: [session],
        worktreesBySession: [session.id: [mainWt]]
    )
    #expect(text.contains("This will delete 1 session."))
    #expect(text.contains("will not be affected"))
    #expect(!text.contains("removed from disk"))
}
