import Foundation
import Testing
@testable import CrowGit

// MARK: - GitError Descriptions

@Test func commandFailedIncludesDetails() {
    let error = GitError.commandFailed(command: "git status", exitCode: 128, stderr: "fatal: not a git repository")
    let desc = error.errorDescription ?? ""
    #expect(desc.contains("git status"))
    #expect(desc.contains("128"))
    #expect(desc.contains("fatal: not a git repository"))
}

@Test func branchAlreadyExistsIncludesBranchName() {
    let error = GitError.branchAlreadyExists("feature/test")
    let desc = error.errorDescription ?? ""
    #expect(desc.contains("feature/test"))
}

@Test func noDefaultBranchIncludesRemoteName() {
    let error = GitError.noDefaultBranch(remote: "origin")
    let desc = error.errorDescription ?? ""
    #expect(desc.contains("origin"))
}
