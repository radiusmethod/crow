import Foundation
import Testing
@testable import CrowCore

// MARK: - AllowEntry Tests

@Test func allowEntryIsInGlobalWhenGlobalPresent() {
    let entry = AllowEntry(pattern: "Bash(npm test:*)", sources: [.global, .worktree(sessionName: "feat", path: "/p")])
    #expect(entry.isInGlobal == true)
}

@Test func allowEntryIsNotInGlobalWhenWorktreeOnly() {
    let entry = AllowEntry(pattern: "Read", sources: [.worktree(sessionName: "feat", path: "/p")])
    #expect(entry.isInGlobal == false)
}

@Test func allowEntryWorktreeSessionNamesSorted() {
    let entry = AllowEntry(pattern: "Edit", sources: [
        .global,
        .worktree(sessionName: "zeta-session", path: "/z"),
        .worktree(sessionName: "alpha-session", path: "/a"),
    ])
    #expect(entry.worktreeSessionNames == ["alpha-session", "zeta-session"])
}

@Test func allowEntryWorktreeSessionNamesEmptyForGlobalOnly() {
    let entry = AllowEntry(pattern: "Bash", sources: [.global])
    #expect(entry.worktreeSessionNames.isEmpty)
}

@Test func allowEntryIdMatchesPattern() {
    let entry = AllowEntry(pattern: "Bash(make build:*)", sources: [.global])
    #expect(entry.id == "Bash(make build:*)")
}
