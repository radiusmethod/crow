import Foundation
import Testing
@testable import CrowCore

// MARK: - isProtectedBranch

@Test func protectedBranchDetectsAllNames() {
    let names = ["main", "master", "develop", "dev", "trunk", "release"]
    for name in names {
        #expect(SessionWorktree.isProtectedBranch(name) == true, "Expected '\(name)' to be protected")
    }
}

@Test func protectedBranchStripsRefsHeadsPrefix() {
    #expect(SessionWorktree.isProtectedBranch("refs/heads/main") == true)
    #expect(SessionWorktree.isProtectedBranch("refs/heads/develop") == true)
}

@Test func protectedBranchStripsOriginPrefix() {
    #expect(SessionWorktree.isProtectedBranch("origin/main") == true)
    #expect(SessionWorktree.isProtectedBranch("origin/master") == true)
}

@Test func protectedBranchIsCaseInsensitive() {
    #expect(SessionWorktree.isProtectedBranch("Main") == true)
    #expect(SessionWorktree.isProtectedBranch("MASTER") == true)
}

@Test func protectedBranchReturnsFalseForFeatureBranches() {
    #expect(SessionWorktree.isProtectedBranch("feature/crow-70") == false)
    #expect(SessionWorktree.isProtectedBranch("fix/login-bug") == false)
    #expect(SessionWorktree.isProtectedBranch("main-feature") == false)
    #expect(SessionWorktree.isProtectedBranch("develop-next") == false)
}

// MARK: - isMainRepoCheckout

private func makeWorktree(
    repoPath: String = "/repo",
    worktreePath: String = "/worktree",
    branch: String = "feature/test"
) -> SessionWorktree {
    SessionWorktree(
        sessionID: UUID(),
        repoName: "repo",
        repoPath: repoPath,
        worktreePath: worktreePath,
        branch: branch
    )
}

@Test func isMainRepoCheckoutWhenPathsMatch() {
    let wt = makeWorktree(
        repoPath: "/Users/test/Dev/Org/repo",
        worktreePath: "/Users/test/Dev/Org/repo",
        branch: "feature/something"
    )
    #expect(wt.isMainRepoCheckout == true)
}

@Test func isMainRepoCheckoutForProtectedBranch() {
    let wt = makeWorktree(
        repoPath: "/repo",
        worktreePath: "/different/path",
        branch: "main"
    )
    #expect(wt.isMainRepoCheckout == true)
}

@Test func isMainRepoCheckoutReturnsFalseForFeatureBranch() {
    let wt = makeWorktree(
        repoPath: "/repo",
        worktreePath: "/worktree",
        branch: "feature/crow-70-quality-pass"
    )
    #expect(wt.isMainRepoCheckout == false)
}
