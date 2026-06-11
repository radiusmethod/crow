import Foundation
import Testing
@testable import CrowCore

@Suite("ShellEnvironment")
struct ShellEnvironmentTests {
    /// `sh` is guaranteed present in `/bin/sh` on macOS, and `/bin` is part of
    /// any sane PATH (login shell or fallback). The exact resolved path may be
    /// `/bin/sh` or a homebrew-installed sh earlier in PATH — we just verify
    /// the helper returns *something* executable matching the requested name.
    @Test func findExecutableResolvesKnownBinary() {
        let resolved = ShellEnvironment.shared.findExecutable("sh")
        #expect(resolved != nil)
        if let resolved {
            #expect(FileManager.default.isExecutableFile(atPath: resolved))
            #expect(resolved.hasSuffix("/sh"))
        }
    }

    @Test func findExecutableReturnsNilForUnknownBinary() {
        // A name no PATH directory should plausibly contain.
        let resolved = ShellEnvironment.shared.findExecutable("crow-nonexistent-binary-xyzzy-12345")
        #expect(resolved == nil)
    }

    @Test func hasCommandAgreesWithFindExecutable() {
        // The two helpers must stay in sync — `hasCommand` is implemented as
        // `findExecutable(_:) != nil`, but pin the contract with a test.
        #expect(ShellEnvironment.shared.hasCommand("sh") == true)
        #expect(ShellEnvironment.shared.hasCommand("crow-nonexistent-binary-xyzzy-12345") == false)
    }
}
