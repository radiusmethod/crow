import Foundation
import Testing
@testable import CrowCore

// MARK: - ToolActivity Tests

@Test func toolActivityDefaultsActiveTrue() {
    let activity = ToolActivity(toolName: "Bash")
    #expect(activity.isActive == true)
}

@Test func toolActivityInactiveState() {
    let activity = ToolActivity(toolName: "Read", isActive: false)
    #expect(activity.isActive == false)
}

@Test func toolActivityToolNameStored() {
    let activity = ToolActivity(toolName: "Edit")
    #expect(activity.toolName == "Edit")
}

@Test func toolActivityTimestampDefault() {
    let before = Date()
    let activity = ToolActivity(toolName: "Write")
    let after = Date()
    #expect(activity.timestamp >= before && activity.timestamp <= after)
}
