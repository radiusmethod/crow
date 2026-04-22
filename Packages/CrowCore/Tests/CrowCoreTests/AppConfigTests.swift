import Foundation
import Testing
@testable import CrowCore

@Test func appConfigRoundTrip() throws {
    let config = AppConfig(
        workspaces: [
            WorkspaceInfo(name: "TestOrg", provider: "github", cli: "gh", alwaysInclude: ["repo1"]),
            WorkspaceInfo(name: "GitLabOrg", provider: "gitlab", cli: "glab", host: "gitlab.example.com"),
        ],
        defaults: ConfigDefaults(provider: "gitlab", cli: "glab", branchPrefix: "fix/", excludeDirs: ["vendor"]),
        notifications: NotificationSettings(globalMute: true),
        sidebar: SidebarSettings(hideSessionDetails: true)
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.workspaces.count == 2)
    #expect(decoded.workspaces[0].name == "TestOrg")
    #expect(decoded.workspaces[0].alwaysInclude == ["repo1"])
    #expect(decoded.workspaces[1].host == "gitlab.example.com")
    #expect(decoded.defaults.provider == "gitlab")
    #expect(decoded.defaults.branchPrefix == "fix/")
    #expect(decoded.defaults.excludeDirs == ["vendor"])
    #expect(decoded.notifications.globalMute == true)
    #expect(decoded.sidebar.hideSessionDetails == true)
}

@Test func appConfigDecodeFromEmptyJSON() throws {
    let json = "{}".data(using: .utf8)!
    let config = try JSONDecoder().decode(AppConfig.self, from: json)

    #expect(config.workspaces.isEmpty)
    #expect(config.defaults.provider == "github")
    #expect(config.defaults.branchPrefix == "feature/")
    #expect(config.notifications.globalMute == false)
    #expect(config.sidebar.hideSessionDetails == false)
    #expect(config.remoteControlEnabled == false)
    #expect(config.managerAutoPermissionMode == true)
}

@Test func appConfigRemoteControlRoundTrip() throws {
    var config = AppConfig()
    config.remoteControlEnabled = true

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.remoteControlEnabled == true)
}

@Test func appConfigManagerAutoPermissionModeRoundTrip() throws {
    var config = AppConfig()
    config.managerAutoPermissionMode = false

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.managerAutoPermissionMode == false)

    config.managerAutoPermissionMode = true
    let data2 = try JSONEncoder().encode(config)
    let decoded2 = try JSONDecoder().decode(AppConfig.self, from: data2)
    #expect(decoded2.managerAutoPermissionMode == true)
}

@Test func appConfigManagerAutoPermissionModeDefaultsTrueWhenKeyMissing() throws {
    // Legacy configs without the key should opt in by default so the Manager
    // benefits from auto mode without requiring users to re-save settings.
    let json = #"{"workspaces": [], "remoteControlEnabled": false}"#.data(using: .utf8)!
    let config = try JSONDecoder().decode(AppConfig.self, from: json)
    #expect(config.managerAutoPermissionMode == true)
}

@Test func appConfigDecodeWithPartialKeys() throws {
    let json = """
    {"workspaces": [{"id": "00000000-0000-0000-0000-000000000001", "name": "Org", "provider": "github", "cli": "gh", "alwaysInclude": []}]}
    """.data(using: .utf8)!
    let config = try JSONDecoder().decode(AppConfig.self, from: json)

    #expect(config.workspaces.count == 1)
    // Other fields should be defaults
    #expect(config.defaults.provider == "github")
    #expect(config.notifications.soundEnabled == true)
    #expect(config.sidebar.hideSessionDetails == false)
}

@Test func appConfigIgnoresUnknownKeys() throws {
    let json = """
    {"futureFeature": true, "workspaces": []}
    """.data(using: .utf8)!
    // Should not throw
    let config = try JSONDecoder().decode(AppConfig.self, from: json)
    #expect(config.workspaces.isEmpty)
}

@Test func appConfigEquality() {
    let a = AppConfig()
    let b = AppConfig()
    #expect(a == b)

    var c = AppConfig()
    c.defaults.branchPrefix = "fix/"
    #expect(a != c)
}

// MARK: - WorkspaceInfo

@Test func workspaceInfoDerivedCLI() {
    let github = WorkspaceInfo(name: "Test", provider: "github", cli: "gh")
    #expect(github.derivedCLI == "gh")

    let gitlab = WorkspaceInfo(name: "Test", provider: "gitlab", cli: "glab")
    #expect(gitlab.derivedCLI == "glab")

    // Even if cli is stale, derivedCLI is correct
    let stale = WorkspaceInfo(name: "Test", provider: "gitlab", cli: "gh")
    #expect(stale.derivedCLI == "glab")
}

@Test func workspaceNameValidation() {
    // Valid name
    #expect(WorkspaceInfo.validateName("MyOrg", existingNames: []) == nil)

    // Empty name
    #expect(WorkspaceInfo.validateName("", existingNames: []) != nil)

    // Duplicate name (case-insensitive)
    #expect(WorkspaceInfo.validateName("MyOrg", existingNames: ["myorg"]) != nil)
    #expect(WorkspaceInfo.validateName("MYORG", existingNames: ["MyOrg"]) != nil)

    // Filesystem-unsafe characters
    #expect(WorkspaceInfo.validateName("My/Org", existingNames: []) != nil)
    #expect(WorkspaceInfo.validateName("My:Org", existingNames: []) != nil)

    // Valid with existing names that don't conflict
    #expect(WorkspaceInfo.validateName("NewOrg", existingNames: ["OtherOrg"]) == nil)
}

// MARK: - ConfigDefaults

@Test func branchPrefixValidation() {
    // Valid prefixes
    #expect(ConfigDefaults.isValidBranchPrefix("feature/") == true)
    #expect(ConfigDefaults.isValidBranchPrefix("fix/") == true)
    #expect(ConfigDefaults.isValidBranchPrefix("") == true) // empty allowed

    // Invalid prefixes
    #expect(ConfigDefaults.isValidBranchPrefix("feature branch/") == false)  // space
    #expect(ConfigDefaults.isValidBranchPrefix("feature~/") == false)        // tilde
    #expect(ConfigDefaults.isValidBranchPrefix("feature^/") == false)        // caret
    #expect(ConfigDefaults.isValidBranchPrefix("feature:/") == false)        // colon
    #expect(ConfigDefaults.isValidBranchPrefix("feature?/") == false)        // question mark
    #expect(ConfigDefaults.isValidBranchPrefix("feature*/") == false)        // asterisk
    #expect(ConfigDefaults.isValidBranchPrefix("feature[/") == false)        // bracket
    #expect(ConfigDefaults.isValidBranchPrefix("feat..ure/") == false)       // consecutive dots
    #expect(ConfigDefaults.isValidBranchPrefix("feature.") == false)         // trailing dot
    #expect(ConfigDefaults.isValidBranchPrefix("feature@{/") == false)       // @{
}
