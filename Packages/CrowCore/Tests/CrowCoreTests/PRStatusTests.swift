import Foundation
import Testing
@testable import CrowCore

@Suite("PRStatus")
struct PRStatusTests {

    @Test func defaultInitAllUnknown() {
        let status = PRStatus()
        #expect(status.isMerged == false)
        #expect(status.isReadyToMerge == false)
        #expect(status.hasBlockers == false)
    }

    @Test func isReadyToMerge() {
        let status = PRStatus(checksPass: .passing, reviewStatus: .approved, mergeable: .mergeable)
        #expect(status.isReadyToMerge == true)
        #expect(status.hasBlockers == false)
    }

    @Test func isMerged() {
        let status = PRStatus(mergeable: .merged)
        #expect(status.isMerged == true)
        #expect(status.isReadyToMerge == false)
        #expect(status.hasBlockers == false)
    }

    @Test func hasBlockersFailingChecks() {
        let status = PRStatus(checksPass: .failing, reviewStatus: .approved, mergeable: .mergeable)
        #expect(status.hasBlockers == true)
        #expect(status.isReadyToMerge == false)
    }

    @Test func hasBlockersChangesRequested() {
        let status = PRStatus(checksPass: .passing, reviewStatus: .changesRequested, mergeable: .mergeable)
        #expect(status.hasBlockers == true)
    }

    @Test func hasBlockersConflicting() {
        let status = PRStatus(checksPass: .passing, reviewStatus: .approved, mergeable: .conflicting)
        #expect(status.hasBlockers == true)
    }

    @Test func notReadyWhenPending() {
        let status = PRStatus(checksPass: .pending, reviewStatus: .approved, mergeable: .mergeable)
        #expect(status.isReadyToMerge == false)
        #expect(status.hasBlockers == false)
    }
}
