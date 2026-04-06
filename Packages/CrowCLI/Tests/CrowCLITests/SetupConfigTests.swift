import Testing
import Foundation
@testable import CrowCLILib

// MARK: - Setup Config Encoding

@Test func setupConfigEncodesValidJSON() throws {
    let config = SetupConfig(
        workspaces: [
            SetupWorkspace(name: "MyOrg", provider: "github", cli: "gh", host: nil, alwaysInclude: [])
        ],
        defaults: SetupDefaults(
            provider: "github",
            cli: "gh",
            branchPrefix: "feature/",
            excludeDirs: ["node_modules", ".git"]
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(config)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"MyOrg\""))
    #expect(json.contains("\"github\""))
    #expect(json.contains("feature"))
}

@Test func setupConfigHandlesSpecialCharactersInWorkspaceName() throws {
    let config = SetupConfig(
        workspaces: [
            SetupWorkspace(name: "My \"Org\" / Test", provider: "github", cli: "gh", host: nil, alwaysInclude: [])
        ],
        defaults: SetupDefaults(
            provider: "github",
            cli: "gh",
            branchPrefix: "feature/",
            excludeDirs: []
        )
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    let json = try #require(String(data: data, encoding: .utf8))

    // Should produce valid JSON with escaped quotes
    let decoded = try JSONDecoder().decode(SetupConfig.self, from: data)
    #expect(decoded.workspaces.first?.name == "My \"Org\" / Test")
}

@Test func setupConfigHandlesGitLabHostField() throws {
    let config = SetupConfig(
        workspaces: [
            SetupWorkspace(name: "GitLabOrg", provider: "gitlab", cli: "glab", host: "gitlab.example.com", alwaysInclude: [])
        ],
        defaults: SetupDefaults(
            provider: "github",
            cli: "gh",
            branchPrefix: "feature/",
            excludeDirs: []
        )
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("gitlab.example.com"))
}

@Test func setupConfigOmitsNullHost() throws {
    let config = SetupConfig(
        workspaces: [
            SetupWorkspace(name: "Org", provider: "github", cli: "gh", host: nil, alwaysInclude: [])
        ],
        defaults: SetupDefaults(
            provider: "github",
            cli: "gh",
            branchPrefix: "feature/",
            excludeDirs: []
        )
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    let decoded = try JSONDecoder().decode(SetupConfig.self, from: data)

    #expect(decoded.workspaces.first?.host == nil)
}

@Test func setupConfigRoundTrips() throws {
    let original = SetupConfig(
        workspaces: [
            SetupWorkspace(name: "Org1", provider: "github", cli: "gh", host: nil, alwaysInclude: ["repo-a"]),
            SetupWorkspace(name: "Org2", provider: "gitlab", cli: "glab", host: "gitlab.internal", alwaysInclude: []),
        ],
        defaults: SetupDefaults(
            provider: "github",
            cli: "gh",
            branchPrefix: "feature/",
            excludeDirs: ["node_modules", ".git", "vendor"]
        )
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SetupConfig.self, from: data)

    #expect(decoded.workspaces.count == 2)
    #expect(decoded.workspaces[0].name == "Org1")
    #expect(decoded.workspaces[1].host == "gitlab.internal")
    #expect(decoded.defaults.excludeDirs.count == 3)
}
