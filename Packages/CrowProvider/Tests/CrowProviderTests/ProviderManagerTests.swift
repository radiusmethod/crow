import Foundation
import Testing
@testable import CrowProvider

@Suite("ProviderManager")
struct ProviderManagerTests {

    let manager = ProviderManager()

    // MARK: - detectProvider

    @Test func detectProviderGitHub() async {
        let result = await manager.detectProvider(from: "https://github.com/org/repo/issues/1")
        #expect(result.provider == .github)
        #expect(result.cli == "gh")
        #expect(result.host == nil)
    }

    @Test func detectProviderGitLab() async {
        let result = await manager.detectProvider(from: "https://gitlab.com/org/repo/-/issues/1")
        #expect(result.provider == .gitlab)
        #expect(result.cli == "glab")
        #expect(result.host == "gitlab.com")
    }

    @Test func detectProviderCustomGitLabHost() async {
        let mgr = ProviderManager(additionalGitLabHosts: ["gitlab.internal.io"])
        let result = await mgr.detectProvider(from: "https://gitlab.internal.io/org/repo/-/issues/5")
        #expect(result.provider == .gitlab)
        #expect(result.cli == "glab")
        #expect(result.host == "gitlab.internal.io")
    }

    @Test func detectProviderFallsBackToGitHub() async {
        let result = await manager.detectProvider(from: "https://unknown.host/org/repo")
        #expect(result.provider == .github)
        #expect(result.cli == "gh")
    }

    // MARK: - parseTicketURLComponents (static)

    @Test func parseGitHubIssueURL() {
        let result = ProviderManager.parseTicketURLComponents("https://github.com/radiusmethod/crow/issues/74")
        #expect(result?.org == "radiusmethod")
        #expect(result?.repo == "crow")
        #expect(result?.number == 74)
        #expect(result?.isMR == false)
    }

    @Test func parseGitHubPullURL() {
        let result = ProviderManager.parseTicketURLComponents("https://github.com/org/repo/pull/123")
        #expect(result?.org == "org")
        #expect(result?.repo == "repo")
        #expect(result?.number == 123)
        #expect(result?.isMR == true)
    }

    @Test func parseGitLabIssueURL() {
        let result = ProviderManager.parseTicketURLComponents("https://gitlab.com/org/repo/-/issues/42")
        #expect(result?.org == "org")
        #expect(result?.repo == "repo")
        #expect(result?.number == 42)
        #expect(result?.isMR == false)
    }

    @Test func parseGitLabMergeRequestURL() {
        let result = ProviderManager.parseTicketURLComponents("https://gitlab.internal.io/team/project/-/merge_requests/99")
        #expect(result?.org == "team")
        #expect(result?.repo == "project")
        #expect(result?.number == 99)
        #expect(result?.isMR == true)
    }

    @Test func parseURLTooShort() {
        let result = ProviderManager.parseTicketURLComponents("https://github.com/org")
        #expect(result == nil)
    }

    @Test func parseURLNonNumericNumber() {
        let result = ProviderManager.parseTicketURLComponents("https://github.com/org/repo/issues/abc")
        #expect(result == nil)
    }
}
