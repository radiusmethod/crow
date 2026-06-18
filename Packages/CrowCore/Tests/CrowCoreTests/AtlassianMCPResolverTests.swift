import Foundation
import Testing
@testable import CrowCore

@Test func atlassianMCPResolverBuildsBasicAuthFromPlaintextToken() throws {
    let config = AtlassianMCPConfig(email: "me@example.com", tokenRef: "tok123")
    // resolveSecret must NOT be consulted for a plaintext token.
    let resolved = AtlassianMCPResolver.resolve(config) { _ in
        Issue.record("op read should not be called for a plaintext token")
        return nil
    }
    let expected = "Basic " + Data("me@example.com:tok123".utf8).base64EncodedString()
    #expect(resolved?.authorization == expected)
    #expect(resolved?.endpoint == AtlassianMCPConfig.defaultEndpoint)
}

@Test func atlassianMCPResolverResolvesOpReference() throws {
    let config = AtlassianMCPConfig(
        endpoint: "https://mcp.atlassian.com/v1/mcp",
        email: "me@example.com",
        tokenRef: "op://Private/Atlassian/api_token")
    var requestedRef: String?
    let resolved = AtlassianMCPResolver.resolve(config) { ref in
        requestedRef = ref
        return "secretToken"
    }
    #expect(requestedRef == "op://Private/Atlassian/api_token")
    let expected = "Basic " + Data("me@example.com:secretToken".utf8).base64EncodedString()
    #expect(resolved?.authorization == expected)
}

@Test func atlassianMCPResolverReturnsNilForEmptyConfig() throws {
    let empty = AtlassianMCPConfig(email: "", tokenRef: "")
    #expect(empty.isEmpty)
    #expect(AtlassianMCPResolver.resolve(empty) { _ in "unused" } == nil)
}

@Test func atlassianMCPResolverReturnsNilWhenSecretResolutionFails() throws {
    let config = AtlassianMCPConfig(email: "me@example.com", tokenRef: "op://Vault/Item/missing")
    // A failed op read must NOT inject a broken credential.
    #expect(AtlassianMCPResolver.resolve(config) { _ in nil } == nil)
}

@Test func atlassianMCPResolverReturnsNilWhenHalfConfigured() throws {
    // Email without a token (or vice versa) can't form Basic auth.
    let emailOnly = AtlassianMCPConfig(email: "me@example.com", tokenRef: "")
    #expect(AtlassianMCPResolver.resolve(emailOnly) { _ in "unused" } == nil)
    let tokenOnly = AtlassianMCPConfig(email: "", tokenRef: "tok")
    #expect(AtlassianMCPResolver.resolve(tokenOnly) { _ in "unused" } == nil)
}

@Test func atlassianMCPConfigDefaultsBlankEndpointToAtlassian() throws {
    let config = AtlassianMCPConfig(endpoint: "  ", email: "me@example.com", tokenRef: "tok")
    #expect(config.resolvedEndpoint == AtlassianMCPConfig.defaultEndpoint)
    #expect(AtlassianMCPResolver.resolve(config) { _ in nil }?.endpoint == AtlassianMCPConfig.defaultEndpoint)
}

@Test func appConfigRoundTripsAtlassianMCP() throws {
    let config = AppConfig(atlassianMCP: AtlassianMCPConfig(
        email: "me@example.com", tokenRef: "op://Private/Atlassian/api_token"))
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.atlassianMCP?.email == "me@example.com")
    #expect(decoded.atlassianMCP?.tokenRef == "op://Private/Atlassian/api_token")
    #expect(decoded.atlassianMCP?.endpoint == AtlassianMCPConfig.defaultEndpoint)
}

@Test func appConfigDecodesMissingAtlassianMCPAsNil() throws {
    let json = "{}".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    #expect(decoded.atlassianMCP == nil)
}
