import Foundation
import Testing
@testable import CrowCore

// MARK: - Validation.ticketKey(fromBranch:)
//
// Regression coverage for #520: worktree branches embed a repo-name prefix
// (`feature/max-monorepo-maxx-7035-…`) that the PR head branch drops. Reconcile
// derives the ticket key from the branch to recover the right PR.

@Test func ticketKeyExtractsJiraKeyFromPrefixedBranch() {
    #expect(
        Validation.ticketKey(fromBranch: "feature/max-monorepo-maxx-7035-citations-chain-of-custody")
            == "MAXX-7035"
    )
}

@Test func ticketKeyHandlesBranchWithoutRepoPrefix() {
    #expect(Validation.ticketKey(fromBranch: "feature/maxx-7035-citations") == "MAXX-7035")
}

@Test func ticketKeyExtractsAnyJiraShapedTokenAfterUppercasing() {
    // A lowercased branch can't tell a real Jira project ("maxx") from an
    // ordinary segment ("api"), so this pure extractor returns the first
    // Jira-*shaped* token — `api-197` → `API-197`. Guarding against false keys
    // on GitHub/GitLab issue branches is the caller's job (it gates the branch
    // fallback to task-only trackers), not this function's.
    #expect(Validation.ticketKey(fromBranch: "feature/acme-api-197-fix-tab-url-hash") == "API-197")
}

@Test func ticketKeyIsNilWhenNoJiraShapedToken() {
    // No LETTERS-DIGITS token at all.
    #expect(Validation.ticketKey(fromBranch: "feature/cleanup-readme") == nil)
    #expect(Validation.ticketKey(fromBranch: "feature/197-only-number") == nil)
    #expect(Validation.ticketKey(fromBranch: "") == nil)
}
