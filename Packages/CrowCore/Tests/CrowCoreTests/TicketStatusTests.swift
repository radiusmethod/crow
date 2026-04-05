import Foundation
import Testing
@testable import CrowCore

@Suite("TicketStatus")
struct TicketStatusTests {

    @Test func canonicalNames() {
        #expect(TicketStatus(projectBoardName: "Backlog") == .backlog)
        #expect(TicketStatus(projectBoardName: "Ready") == .ready)
        #expect(TicketStatus(projectBoardName: "In Progress") == .inProgress)
        #expect(TicketStatus(projectBoardName: "In Review") == .inReview)
        #expect(TicketStatus(projectBoardName: "Done") == .done)
    }

    @Test func caseInsensitive() {
        #expect(TicketStatus(projectBoardName: "BACKLOG") == .backlog)
        #expect(TicketStatus(projectBoardName: "in progress") == .inProgress)
        #expect(TicketStatus(projectBoardName: "IN REVIEW") == .inReview)
    }

    @Test func aliases() {
        #expect(TicketStatus(projectBoardName: "Todo") == .ready)
        #expect(TicketStatus(projectBoardName: "To Do") == .ready)
        #expect(TicketStatus(projectBoardName: "Doing") == .inProgress)
        #expect(TicketStatus(projectBoardName: "Active") == .inProgress)
        #expect(TicketStatus(projectBoardName: "Review") == .inReview)
        #expect(TicketStatus(projectBoardName: "Closed") == .done)
        #expect(TicketStatus(projectBoardName: "Complete") == .done)
        #expect(TicketStatus(projectBoardName: "Completed") == .done)
    }

    @Test func whitspaceTrimming() {
        #expect(TicketStatus(projectBoardName: "  in review  ") == .inReview)
        #expect(TicketStatus(projectBoardName: " backlog ") == .backlog)
    }

    @Test func unknownStrings() {
        #expect(TicketStatus(projectBoardName: "Custom Status") == .unknown)
        #expect(TicketStatus(projectBoardName: "") == .unknown)
        #expect(TicketStatus(projectBoardName: "Blocked") == .unknown)
    }
}
