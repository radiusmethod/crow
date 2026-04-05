import Foundation
import Testing
@testable import CrowCore

// MARK: - Validation Tests

@Test func validSessionName() {
    #expect(Validation.isValidSessionName("my-session"))
    #expect(Validation.isValidSessionName("feature/crow-123-fix"))
    #expect(Validation.isValidSessionName("a"))
    #expect(Validation.isValidSessionName(String(repeating: "x", count: 256)))
}

@Test func invalidSessionName_empty() {
    #expect(!Validation.isValidSessionName(""))
}

@Test func invalidSessionName_tooLong() {
    #expect(!Validation.isValidSessionName(String(repeating: "x", count: 257)))
}

@Test func invalidSessionName_controlChars() {
    #expect(!Validation.isValidSessionName("hello\u{0000}world"))
    #expect(!Validation.isValidSessionName("line\nbreak"))
    #expect(!Validation.isValidSessionName("tab\there"))
}

@Test func pathWithinRoot_normalPaths() {
    #expect(Validation.isPathWithinRoot("/Users/dev/project/file.txt", root: "/Users/dev"))
    #expect(Validation.isPathWithinRoot("/Users/dev/project", root: "/Users/dev"))
    #expect(Validation.isPathWithinRoot("/Users/dev", root: "/Users/dev"))
}

@Test func pathWithinRoot_rejectsOutsidePaths() {
    #expect(!Validation.isPathWithinRoot("/Users/other/file.txt", root: "/Users/dev"))
    #expect(!Validation.isPathWithinRoot("/etc/passwd", root: "/Users/dev"))
}

@Test func pathWithinRoot_traversalAttempt() {
    // ".." traversal should be resolved and rejected
    #expect(!Validation.isPathWithinRoot("/Users/dev/../other/file.txt", root: "/Users/dev"))
    #expect(!Validation.isPathWithinRoot("/Users/dev/project/../../etc/passwd", root: "/Users/dev"))
}

@Test func pathWithinRoot_prefixTrick() {
    // "/Users/devious" should NOT match root "/Users/dev" (prefix boundary check)
    #expect(!Validation.isPathWithinRoot("/Users/devious/file.txt", root: "/Users/dev"))
}

// MARK: - AppConfig Codable Tests

@Test func appConfigRoundTrip() throws {
    let config = AppConfig(
        workspaces: [
            WorkspaceInfo(name: "TestOrg", provider: "github", cli: "gh", host: nil)
        ],
        defaults: ConfigDefaults(provider: "github", cli: "gh", branchPrefix: "feature/")
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.workspaces.count == 1)
    #expect(decoded.workspaces[0].name == "TestOrg")
    #expect(decoded.defaults.branchPrefix == "feature/")
}

@Test func appConfigDefaults() {
    let config = AppConfig()
    #expect(config.workspaces.isEmpty)
    #expect(config.defaults.provider == "github")
    #expect(config.defaults.branchPrefix == "feature/")
}
