import Testing
import Foundation
@testable import CrowCLILib

// MARK: - UUID Validation

@Test func validUUIDAccepted() throws {
    try validateUUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")
}

@Test func uppercaseUUIDAccepted() throws {
    try validateUUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
}

@Test func nilUUIDAccepted() throws {
    try validateUUID("00000000-0000-0000-0000-000000000000")
}

@Test func invalidUUIDRejected() {
    #expect(throws: (any Error).self) {
        try validateUUID("not-a-uuid")
    }
}

@Test func emptyStringUUIDRejected() {
    #expect(throws: (any Error).self) {
        try validateUUID("")
    }
}

@Test func uuidWithoutDashesRejected() {
    // Foundation's UUID(uuidString:) requires dashes
    #expect(throws: (any Error).self) {
        try validateUUID("a1b2c3d4e5f67890abcdef1234567890")
    }
}

// MARK: - Session Status Validation

@Test func allValidStatusesAccepted() throws {
    for status in ["active", "paused", "inReview", "completed", "archived"] {
        try validateSessionStatus(status)
    }
}

@Test func invalidStatusRejected() {
    #expect(throws: (any Error).self) {
        try validateSessionStatus("invalid")
    }
}

@Test func statusIsCaseSensitive() {
    #expect(throws: (any Error).self) {
        try validateSessionStatus("Active")
    }
}

@Test func emptyStatusRejected() {
    #expect(throws: (any Error).self) {
        try validateSessionStatus("")
    }
}

// MARK: - Link Type Validation

@Test func allValidLinkTypesAccepted() throws {
    for linkType in ["ticket", "pr", "repo", "custom"] {
        try validateLinkType(linkType)
    }
}

@Test func invalidLinkTypeRejected() {
    #expect(throws: (any Error).self) {
        try validateLinkType("unknown")
    }
}

@Test func linkTypeIsCaseSensitive() {
    #expect(throws: (any Error).self) {
        try validateLinkType("Ticket")
    }
}

// MARK: - Set Ticket Field Validation

@Test func setTicketWithURLAccepted() throws {
    try validateSetTicketHasField(url: "https://example.com", title: nil, number: nil)
}

@Test func setTicketWithTitleAccepted() throws {
    try validateSetTicketHasField(url: nil, title: "My Ticket", number: nil)
}

@Test func setTicketWithNumberAccepted() throws {
    try validateSetTicketHasField(url: nil, title: nil, number: 42)
}

@Test func setTicketWithAllFieldsAccepted() throws {
    try validateSetTicketHasField(url: "https://example.com", title: "Ticket", number: 1)
}

@Test func setTicketWithNoFieldsRejected() {
    #expect(throws: (any Error).self) {
        try validateSetTicketHasField(url: nil, title: nil, number: nil)
    }
}
