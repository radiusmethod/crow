import CrowCore
import Foundation
import Testing
@testable import Crow

/// Snapshot tests for Crow skill attribution instructions (issues #443, #447).
///
/// Skill source files reference `{{CROW_AGENT_DISPLAY_NAME}}` as the canonical
/// placeholder; Crow substitutes it with the resolved agent name at file-write
/// time (Scaffolder, SessionService). The earlier `${CROW_AGENT_DISPLAY_NAME:-…}`
/// shell expression silently failed inside single-quoted heredocs and leaked
/// literal text into commits / issues / PR bodies — these tests guard against
/// regressing to that form. The unit tests in
/// `Packages/CrowCore/Tests/CrowCoreTests/CrowAttributionTests.swift` verify the
/// Swift helpers and default Claude Code footers.
@Suite("Review attribution snapshot")
struct AttributionSkillTests {

    private static let canonicalRepoURL = "https://github.com/radiusmethod/crow"
    private static let shellAgentExpression = "${CROW_AGENT_DISPLAY_NAME:-Claude Code}"
    private static let agentPlaceholder = "{{CROW_AGENT_DISPLAY_NAME}}"

    /// Walk up from this test source file until we find Package.swift.
    /// Returns the repo root URL.
    private static func repoRoot(file: StaticString = #file) -> URL {
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path
            ) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        Issue.record("Could not locate Package.swift walking up from \(file)")
        return URL(fileURLWithPath: "/")
    }

    private static func liveSkill() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("skills/crow-review-pr/SKILL.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func bundledTemplate() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("Resources/crow-review-pr-SKILL.md.template")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func liveTicketSkill() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("skills/crow-create-ticket/SKILL.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func bundledTicketTemplate() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("Resources/crow-create-ticket-SKILL.md.template")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func liveAttributionFooter() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("skills/crow-attribution/FOOTER.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func bundledAttributionTemplate() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("Resources/crow-attribution-FOOTER.md.template")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func liveSkillUsesAgentPlaceholderNotShellExpression() throws {
        let content = try Self.liveSkill()
        // #447: source templates must use the literal {{…}} sentinel that
        // Crow substitutes at write-time. The old shell expression silently
        // failed inside single-quoted heredocs and leaked into review bodies.
        #expect(content.contains(Self.agentPlaceholder))
        #expect(!content.contains(Self.shellAgentExpression))
        #expect(content.contains(Self.canonicalRepoURL))
    }

    @Test func bundledTemplateUsesAgentPlaceholderNotShellExpression() throws {
        let content = try Self.bundledTemplate()
        #expect(content.contains(Self.agentPlaceholder))
        #expect(!content.contains(Self.shellAgentExpression))
    }

    @Test func liveSkillAndBundledTemplateAreByteIdentical() throws {
        let live = try Self.liveSkill()
        let bundled = try Self.bundledTemplate()
        #expect(live == bundled,
                "skills/crow-review-pr/SKILL.md and Resources/crow-review-pr-SKILL.md.template must stay in sync — Scaffolder.bundledReviewSkill() picks one or the other depending on build type.")
    }

    @Test func attributionFilesContainNoForkReferences() throws {
        let live = try Self.liveSkill()
        let bundled = try Self.bundledTemplate()

        #expect(!live.contains("nicholasgasior"))
        #expect(!bundled.contains("nicholasgasior"))

        // Lowercase `corveil` — to skip the unrelated `CorveilTheme.swift`
        // design-system file which uses capital `C`.
        #expect(!live.contains("corveil"))
        #expect(!bundled.contains("corveil"))
    }

    @Test func liveSkillLinksOnlyToCanonicalRepo() throws {
        // Any github.com link in the review skill must point at radiusmethod/crow.
        // This catches drift where a contributor pastes a fork URL.
        let content = try Self.liveSkill()
        let pattern = #"https://github\.com/[A-Za-z0-9._/-]+"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        #expect(!matches.isEmpty, "expected at least one github.com link (the attribution line) in the skill")
        for match in matches {
            guard let r = Range(match.range, in: content) else { continue }
            let url = String(content[r])
            #expect(url == Self.canonicalRepoURL,
                    "review skill contains non-canonical github.com link: \(url)")
        }
    }

    @Test func liveTicketSkillUsesAgentPlaceholderNotShellExpression() throws {
        let content = try Self.liveTicketSkill()
        #expect(content.contains(Self.agentPlaceholder))
        #expect(!content.contains(Self.shellAgentExpression))
        #expect(content.contains(Self.canonicalRepoURL))
        #expect(!content.contains("Do not modify the link text"))
    }

    @Test func bundledTicketTemplateUsesAgentPlaceholderNotShellExpression() throws {
        let content = try Self.bundledTicketTemplate()
        #expect(content.contains(Self.agentPlaceholder))
        #expect(!content.contains(Self.shellAgentExpression))
    }

    @Test func liveTicketSkillAndBundledTemplateAreByteIdentical() throws {
        let live = try Self.liveTicketSkill()
        let bundled = try Self.bundledTicketTemplate()
        #expect(live == bundled,
                "skills/crow-create-ticket/SKILL.md and Resources/crow-create-ticket-SKILL.md.template must stay in sync — Scaffolder.bundledCreateTicketSkill() picks one or the other depending on build type.")
    }

    @Test func ticketSkillLinksOnlyToCanonicalRepo() throws {
        // Any github.com link in the create-ticket skill must point at radiusmethod/crow.
        let content = try Self.liveTicketSkill()
        let pattern = #"https://github\.com/[A-Za-z0-9._/-]+"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        #expect(!matches.isEmpty, "expected at least one github.com link (the attribution line) in the skill")
        for match in matches {
            guard let r = Range(match.range, in: content) else { continue }
            let url = String(content[r])
            #expect(url == Self.canonicalRepoURL,
                    "create-ticket skill contains non-canonical github.com link: \(url)")
        }
    }

    @Test func sharedFooterDocumentsSubstitutionAndCanonicalURL() throws {
        let footer = try Self.liveAttributionFooter()
        // #447 review: FOOTER prose must read sensibly post-substitution, so it
        // deliberately does NOT spell `{{CROW_AGENT_DISPLAY_NAME}}` literally
        // (`expandSkillBody` would otherwise rewrite the explanatory sentences
        // and produce self-contradictory deployed docs). Guard the canonical
        // URL and the no-sentinel constraint together.
        #expect(footer.contains(Self.canonicalRepoURL))
        #expect(!footer.contains(Self.agentPlaceholder),
                "FOOTER.md prose must not contain {{CROW_AGENT_DISPLAY_NAME}} — expandSkillBody runs over this file and would rewrite the explanation. Describe the model without naming the sentinel literally.")
        #expect(!footer.contains("$\(CrowAttribution.agentDisplayNameEnvironmentKey)"),
                "FOOTER.md prose must not contain a bare $CROW_AGENT_DISPLAY_NAME token — expandSkillBody would rewrite it too.")
    }

    @Test func liveAttributionFooterAndBundledTemplateAreByteIdentical() throws {
        let live = try Self.liveAttributionFooter()
        let bundled = try Self.bundledAttributionTemplate()
        #expect(live == bundled,
                "skills/crow-attribution/FOOTER.md and Resources/crow-attribution-FOOTER.md.template must stay in sync — Scaffolder.bundledAttributionFooter() loads the template in release builds.")
    }

    @Test func liveAttributionFooterMatchesSwiftConstant() throws {
        let live = try Self.liveAttributionFooter()
        let swift = CrowAttribution.sharedFooterInstructions
        var trimmed = live
        while trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") { trimmed.removeLast() }
        var swiftTrimmed = swift
        while swiftTrimmed.hasSuffix("\n") || swiftTrimmed.hasSuffix("\r") { swiftTrimmed.removeLast() }
        #expect(trimmed + "\n" == swiftTrimmed + "\n",
                "skills/crow-attribution/FOOTER.md must match CrowAttribution.sharedFooterInstructions — the constant is Scaffolder's final fallback.")
    }

    // MARK: - Substitution behavior (#447)

    /// Regression guard for the #447 review feedback: the prose explaining the
    /// substitution model must not contain a literal `{{CROW_AGENT_DISPLAY_NAME}}`
    /// token, because `expandSkillBody` will rewrite the explanation along with
    /// the real footer and produce self-contradictory deployed docs (e.g.
    /// "replaces `Cursor` with the session's resolved agent name"). The only
    /// valid home for the sentinel is the operative footer line itself, which
    /// is recognizable by also containing the canonical repo URL.
    private static func assertSentinelOnlyInFooterLines(_ body: String, file: StaticString = #file) {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains(Self.agentPlaceholder) {
                #expect(
                    line.contains(Self.canonicalRepoURL),
                    "Line contains `{{CROW_AGENT_DISPLAY_NAME}}` outside an attribution footer (no canonical URL on the line). `expandSkillBody` will rewrite this and likely produce self-contradictory prose post-scaffold. Reword to describe the model without spelling the sentinel.\nLine: \(line)"
                )
            }
        }
    }

    @Test func liveReviewSkillKeepsSentinelOnlyInFooterLines() throws {
        try Self.assertSentinelOnlyInFooterLines(Self.liveSkill())
    }

    @Test func liveTicketSkillKeepsSentinelOnlyInFooterLines() throws {
        try Self.assertSentinelOnlyInFooterLines(Self.liveTicketSkill())
    }

    /// Confirm the substitution pass walks every footer occurrence in a real
    /// skill body. Reads the live SKILL.md directly (rather than going through
    /// `Scaffolder.bundledReviewSkill()`) so the test doesn't depend on the
    /// bundled loader's runtime file-resolution heuristic, which falls back to
    /// a trivial stub in the test runner. The live file is the source of truth
    /// the scaffold writes from — exercising it here mirrors the dev-root
    /// behavior end-to-end.
    @Test func expandSkillBodyReplacesEveryReviewFooterOccurrence() throws {
        let body = try Self.liveSkill()
        #expect(body.contains(Self.agentPlaceholder),
                "precondition: live review skill must contain the placeholder before substitution")
        let expanded = CrowAttribution.expandSkillBody(body, agentKind: .cursor)
        #expect(!expanded.contains(Self.agentPlaceholder),
                "expandSkillBody must replace every {{CROW_AGENT_DISPLAY_NAME}} occurrence in the live review skill.")
        #expect(!expanded.contains(Self.shellAgentExpression),
                "expandSkillBody must also strip any legacy shell expression that snuck in.")
        #expect(expanded.contains("Reviewed by Crow via Cursor"),
                "the substituted footer must read the resolved agent name literally.")
    }

    @Test func expandSkillBodyReplacesEveryTicketFooterOccurrence() throws {
        let body = try Self.liveTicketSkill()
        #expect(body.contains(Self.agentPlaceholder))
        let expanded = CrowAttribution.expandSkillBody(body, agentKind: .codex)
        #expect(!expanded.contains(Self.agentPlaceholder))
        #expect(!expanded.contains(Self.shellAgentExpression))
        #expect(expanded.contains("Created with Crow via OpenAI Codex"))
    }
}
