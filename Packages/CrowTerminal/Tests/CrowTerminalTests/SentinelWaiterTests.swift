import Foundation
import Testing
@testable import CrowTerminal

@Suite("SentinelWaiter")
struct SentinelWaiterTests {

    @Test func returnsImmediatelyWhenSentinelExists() async throws {
        let path = makeTempPath()
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let elapsed = await SentinelWaiter().waitForPrompt(
            sentinelPath: path,
            timeout: 1.0,
            pollInterval: 0.01
        )
        let unwrapped = try #require(elapsed)
        // First poll iteration sees the file before any sleep — sub-100ms.
        #expect(unwrapped < 0.1)
    }

    @Test func returnsNilOnTimeout() async throws {
        let path = makeTempPath()
        let elapsed = await SentinelWaiter().waitForPrompt(
            sentinelPath: path,
            timeout: 0.2,
            pollInterval: 0.05
        )
        #expect(elapsed == nil)
    }

    @Test func detectsSentinelAppearingMidWait() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Touch the sentinel after 100ms — well within the 1s budget.
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            FileManager.default.createFile(atPath: path, contents: Data())
        }

        let elapsed = await SentinelWaiter().waitForPrompt(
            sentinelPath: path,
            timeout: 1.0,
            pollInterval: 0.02
        )
        let unwrapped = try #require(elapsed)
        // Should be ~100ms, definitely under the 1s timeout.
        #expect(unwrapped >= 0.1)
        #expect(unwrapped < 1.0)
    }

    private func makeTempPath() -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("crow-test-sentinel-\(UUID().uuidString)")
    }
}
