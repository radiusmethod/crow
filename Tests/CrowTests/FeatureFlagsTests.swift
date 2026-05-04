import Foundation
import Testing
@testable import Crow

/// Test the env-var parsing in `FeatureFlags.boolFlag`. We can't easily
/// flip the live environment from tests, so this exercises the same shape
/// directly via a free function. The intent is to lock in which spellings
/// of "true" we accept so the rollout's flag flips are predictable.
///
/// `.serialized` because `tmuxBackendDefaultIsOff` and
/// `tmuxBackendOnWhenConfigOverrideOn` both mutate the global static
/// `FeatureFlags.tmuxBackendConfigOverride`. Without serialization the two
/// tests race on that shared state and the suite fails intermittently
/// (one test's `= false` reset lands between the other's set + read).
@Suite("FeatureFlags env parsing", .serialized)
struct FeatureFlagsTests {

    /// Mirror of the parsing rule in `FeatureFlags.boolFlag`. If the
    /// production rule changes, this helper must change too — that's the
    /// point: the test pins the policy.
    private func parse(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }

    @Test func acceptsCanonicalTrueValues() {
        #expect(parse("1"))
        #expect(parse("true"))
        #expect(parse("True"))
        #expect(parse("TRUE"))
        #expect(parse("yes"))
        #expect(parse("on"))
    }

    @Test func rejectsFalsishValues() {
        #expect(!parse(nil))
        #expect(!parse(""))
        #expect(!parse("0"))
        #expect(!parse("false"))
        #expect(!parse("no"))
        #expect(!parse("off"))
        #expect(!parse(" 1 "))   // intentional: whitespace not trimmed
    }

    @Test func tmuxBackendDefaultIsOff() {
        // The flag's default-off behavior is load-bearing for the gated
        // rollout. We can't unset env reliably from a test, so we just
        // assert that under normal CI conditions it's false.
        if ProcessInfo.processInfo.environment["CROW_TMUX_BACKEND"] == nil {
            // Reset the override so a previous test can't leak state.
            FeatureFlags.tmuxBackendConfigOverride = false
            #expect(!FeatureFlags.tmuxBackend)
        }
    }

    @Test func tmuxBackendOnWhenConfigOverrideOn() {
        // The config override is the user-facing entry point for the flag
        // (Settings → Experimental → Use tmux for managed terminals).
        // Should switch tmuxBackend ON without needing the env var.
        if ProcessInfo.processInfo.environment["CROW_TMUX_BACKEND"] == nil {
            FeatureFlags.tmuxBackendConfigOverride = true
            #expect(FeatureFlags.tmuxBackend)
            FeatureFlags.tmuxBackendConfigOverride = false
            #expect(!FeatureFlags.tmuxBackend)
        }
    }
}
