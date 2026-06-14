import Foundation
import Testing
@testable import CrowCore

/// CROW-505: AutoRespondSettings default flip and decoder behavior.
@Suite("AutoRespondSettings defaults")
struct AutoRespondSettingsDefaultsTests {
    @Test func defaultInitializerDefaultsRespondToChangesRequestedOn() {
        // The whole point of CROW-505: a fresh install gets auto-refine on by
        // default. Old default was off; users assumed it worked but the toggle
        // was silently false.
        let settings = AutoRespondSettings()
        #expect(settings.respondToChangesRequested == true)
        // Failed-checks stays off — separate decision; intrusive prompts on
        // every CI flake aren't what most users want.
        #expect(settings.respondToFailedChecks == false)
    }

    @Test func decoderFallbackForMissingKeyMatchesNewDefault() throws {
        // Older configs that never wrote the field at all (key absent) should
        // pick up the new default — this is the upgrade path for users who
        // never touched the setting.
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AutoRespondSettings.self, from: json)
        #expect(decoded.respondToChangesRequested == true)
        #expect(decoded.respondToFailedChecks == false)
    }

    @Test func decoderPreservesExplicitFalseChoice() throws {
        // Existing users who explicitly toggled the setting OFF in UI have the
        // key written as `false` in their JSON. `decodeIfPresent` returns the
        // written value, so their choice survives the default flip. This is
        // the "existing choices stay sticky" guarantee.
        let json = #"{"respondToChangesRequested": false, "respondToFailedChecks": false}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AutoRespondSettings.self, from: json)
        #expect(decoded.respondToChangesRequested == false)
    }

    @Test func decoderHonorsExplicitTrueChoice() throws {
        let json = #"{"respondToChangesRequested": true, "respondToFailedChecks": true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AutoRespondSettings.self, from: json)
        #expect(decoded.respondToChangesRequested == true)
        #expect(decoded.respondToFailedChecks == true)
    }
}
