import Foundation
import Testing
@testable import CrowCore

// MARK: - Provider Detection

@Test func detectGitHubProvider() {
    #expect(Validation.detectProviderFromURL("https://github.com/org/repo/issues/1") == .github)
    #expect(Validation.detectProviderFromURL("https://github.com/org/repo/pull/42") == .github)
}

@Test func detectGitLabProvider() {
    #expect(Validation.detectProviderFromURL("https://gitlab.com/org/repo/-/issues/1") == .gitlab)
    #expect(Validation.detectProviderFromURL("https://gitlab.example.com/org/repo") == .gitlab)
    #expect(Validation.detectProviderFromURL("https://code.company.com/-/issues/5") == .gitlab)
    #expect(Validation.detectProviderFromURL("https://code.company.com/-/merge_requests/3") == .gitlab)
}

@Test func detectUnknownProvider() {
    #expect(Validation.detectProviderFromURL("https://bitbucket.org/org/repo") == nil)
    #expect(Validation.detectProviderFromURL("https://example.com/issues/1") == nil)
}

@Test func detectEmptyURLProvider() {
    #expect(Validation.detectProviderFromURL("") == nil)
}
