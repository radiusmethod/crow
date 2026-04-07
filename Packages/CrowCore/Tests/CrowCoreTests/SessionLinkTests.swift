import Foundation
import Testing
@testable import CrowCore

// MARK: - SessionLink Tests

@Test func sessionLinkCodableRoundTrip() throws {
    let sessionID = UUID()
    let link = SessionLink(sessionID: sessionID, label: "Issue", url: "https://github.com/org/repo/issues/1", linkType: .ticket)
    let data = try JSONEncoder().encode(link)
    let decoded = try JSONDecoder().decode(SessionLink.self, from: data)
    #expect(decoded.id == link.id)
    #expect(decoded.sessionID == sessionID)
    #expect(decoded.label == "Issue")
    #expect(decoded.url == "https://github.com/org/repo/issues/1")
    #expect(decoded.linkType == .ticket)
}

@Test func sessionLinkAllLinkTypes() throws {
    let sessionID = UUID()
    for linkType in [LinkType.ticket, .pr, .repo, .custom] {
        let link = SessionLink(sessionID: sessionID, label: "L", url: "u", linkType: linkType)
        let data = try JSONEncoder().encode(link)
        let decoded = try JSONDecoder().decode(SessionLink.self, from: data)
        #expect(decoded.linkType == linkType)
    }
}

@Test func sessionLinkDefaultIDIsValidUUID() {
    let link = SessionLink(sessionID: UUID(), label: "PR", url: "https://example.com", linkType: .pr)
    // The id is auto-generated — just verify it's a valid UUID by checking it's not empty
    #expect(link.id.uuidString.isEmpty == false)
}
