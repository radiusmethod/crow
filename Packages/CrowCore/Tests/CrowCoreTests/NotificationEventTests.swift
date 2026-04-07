import Foundation
import Testing
@testable import CrowCore

@Test func notificationEventAllCasesCount() {
    #expect(NotificationEvent.allCases.count == 2)
}

@Test func notificationEventDefaultSoundsNonEmpty() {
    for event in NotificationEvent.allCases {
        #expect(!event.defaultSound.isEmpty)
    }
}

@Test func notificationEventDisplayNamesNonEmpty() {
    for event in NotificationEvent.allCases {
        #expect(!event.displayName.isEmpty)
        #expect(!event.description.isEmpty)
    }
}

// MARK: - from() mapping

@Test func fromStopMapsToTaskComplete() {
    #expect(NotificationEvent.from(eventName: "Stop") == .taskComplete)
}

@Test func fromPreToolUseAskUserQuestionMapsToAgentWaiting() {
    #expect(NotificationEvent.from(eventName: "PreToolUse", toolName: "AskUserQuestion") == .agentWaiting)
}

@Test func fromPreToolUseOtherToolReturnsNil() {
    #expect(NotificationEvent.from(eventName: "PreToolUse", toolName: "Bash") == nil)
    #expect(NotificationEvent.from(eventName: "PreToolUse") == nil)
}

@Test func fromPermissionRequestMapsToAgentWaiting() {
    #expect(NotificationEvent.from(eventName: "PermissionRequest") == .agentWaiting)
}

@Test func fromNotificationPermissionPromptMapsToAgentWaiting() {
    #expect(NotificationEvent.from(eventName: "Notification", notificationType: "permission_prompt") == .agentWaiting)
}

@Test func fromNotificationOtherTypeReturnsNil() {
    #expect(NotificationEvent.from(eventName: "Notification", notificationType: "info") == nil)
    #expect(NotificationEvent.from(eventName: "Notification") == nil)
}

@Test func fromUnknownEventReturnsNil() {
    #expect(NotificationEvent.from(eventName: "Start") == nil)
    #expect(NotificationEvent.from(eventName: "PostToolUse") == nil)
    #expect(NotificationEvent.from(eventName: "") == nil)
}

// MARK: - Codable round-trip

@Test func notificationEventCodableRoundTrip() throws {
    for event in NotificationEvent.allCases {
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NotificationEvent.self, from: data)
        #expect(decoded == event)
    }
}
