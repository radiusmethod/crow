import Foundation
import Testing
import CrowCore
import CrowProvider
@testable import Crow

/// Minimal `CodeBackend` for prompt-rendering tests — only `provider` and
/// `cliName` are read by the builders. The other protocol methods are
/// unused, so trivial stubs are fine.
private struct FakeCodeBackend: CodeBackend {
    let provider: Provider
    let cliName: String
    let capabilities: Set<CodeCapability> = []
    func linkedPR(repo: String, branch: String) async throws -> LinkedPR? { nil }
    func ensureMergeLabel(repo: String) async throws {}
}

@Suite("QuickActionPrompts.mergePR")
struct QuickActionPromptsTests {

    @Test func githubMergeHintRunsFromTmpdirToAvoidWorktreeConflict() {
        let prompt = QuickActionPrompts.build(
            action: .mergePR,
            codeBackend: FakeCodeBackend(provider: .github, cliName: "gh"),
            prURL: "https://github.com/radiusmethod/crow/pull/123",
            prNumber: 123
        )
        #expect(prompt.contains("cd \"$TMPDIR\" && gh pr merge https://github.com/radiusmethod/crow/pull/123 --squash --delete-branch"))
        #expect(prompt.contains("worktree"))
        #expect(prompt.hasSuffix("\n"))
    }

    @Test func gitlabMergeHintIsUnaffected() {
        let prompt = QuickActionPrompts.build(
            action: .mergePR,
            codeBackend: FakeCodeBackend(provider: .gitlab, cliName: "glab"),
            prURL: "https://gitlab.example.com/org/repo/-/merge_requests/45",
            prNumber: 45
        )
        #expect(prompt.contains("glab mr merge https://gitlab.example.com/org/repo/-/merge_requests/45"))
        #expect(!prompt.contains("$TMPDIR"))
        #expect(prompt.hasSuffix("\n"))
    }
}
