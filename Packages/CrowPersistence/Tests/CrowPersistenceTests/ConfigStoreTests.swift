import Foundation
import Testing
@testable import CrowPersistence
@testable import CrowCore

@Test func configStoreRoundTrip() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let claudeDir = tmpDir.appendingPathComponent(".claude", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let config = AppConfig(
        workspaces: [WorkspaceInfo(name: "TestOrg")],
        defaults: ConfigDefaults(branchPrefix: "fix/"),
        notifications: NotificationSettings(globalMute: true),
        sidebar: SidebarSettings(hideSessionDetails: true)
    )

    try ConfigStore.saveConfig(config, to: claudeDir)

    let configURL = claudeDir.appendingPathComponent("config.json")
    let loaded = ConfigStore.loadConfig(from: configURL)

    #expect(loaded != nil)
    #expect(loaded?.workspaces.count == 1)
    #expect(loaded?.workspaces.first?.name == "TestOrg")
    #expect(loaded?.defaults.branchPrefix == "fix/")
    #expect(loaded?.notifications.globalMute == true)
    #expect(loaded?.sidebar.hideSessionDetails == true)
}

@Test func configStoreLoadMissingFileReturnsNil() {
    let missingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")
    let result = ConfigStore.loadConfig(from: missingURL)
    #expect(result == nil)
}

@Test func configStoreLoadMalformedJSONReturnsNil() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let configURL = tmpDir.appendingPathComponent("config.json")
    try "not valid json {{{".write(to: configURL, atomically: true, encoding: .utf8)

    let result = ConfigStore.loadConfig(from: configURL)
    #expect(result == nil)
}

@Test func configStoreSaveCreatesDirectory() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let claudeDir = tmpDir.appendingPathComponent(".claude", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    #expect(!FileManager.default.fileExists(atPath: claudeDir.path))

    try ConfigStore.saveConfig(AppConfig(), to: claudeDir)

    #expect(FileManager.default.fileExists(atPath: claudeDir.path))
    let configURL = claudeDir.appendingPathComponent("config.json")
    #expect(FileManager.default.fileExists(atPath: configURL.path))
}

@Test func configStoreSaveSetsPermissions() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let claudeDir = tmpDir.appendingPathComponent(".claude", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    try ConfigStore.saveConfig(AppConfig(), to: claudeDir)

    let configURL = claudeDir.appendingPathComponent("config.json")

    // Check file permissions (0o600 = owner read/write only)
    let fileAttrs = try FileManager.default.attributesOfItem(atPath: configURL.path)
    let filePerms = fileAttrs[.posixPermissions] as? Int
    #expect(filePerms == 0o600)

    // Check directory permissions (0o700 = owner read/write/execute only)
    let dirAttrs = try FileManager.default.attributesOfItem(atPath: claudeDir.path)
    let dirPerms = dirAttrs[.posixPermissions] as? Int
    #expect(dirPerms == 0o700)
}
