import Foundation

/// Resolves an ``AtlassianMCPConfig`` into the launch-ready value for the
/// Atlassian Remote MCP Server's `Authorization` header (CROW-522).
///
/// The token (`tokenRef`) may be a plaintext string or an `op://…` 1Password
/// reference; references are resolved at launch via the `op` CLI so the secret
/// never lands at rest in `config.json`. The resolved output is an HTTP Basic
/// credential — `Basic base64("\(email):\(token)")` — matching Atlassian's
/// personal-API-token auth for the Rovo MCP Server.
///
/// Resolved secret values are never logged.
public enum AtlassianMCPResolver {
    /// Launch-ready values for injecting the Atlassian MCP server.
    public struct Resolved: Equatable, Sendable {
        /// The MCP endpoint URL (e.g. `https://mcp.atlassian.com/v1/mcp`).
        public var endpoint: String
        /// The full `Authorization` header value (e.g. `Basic ZW1haWw6dG9rZW4=`).
        public var authorization: String

        public init(endpoint: String, authorization: String) {
            self.endpoint = endpoint
            self.authorization = authorization
        }
    }

    /// Resolve a config's token (resolving an `op://…` reference) and build the
    /// Basic-auth `Authorization` header. Returns `nil` for an empty config, or
    /// when the email/token is missing or the secret reference fails to resolve
    /// (caller should then *not* inject the server, rather than inject a broken
    /// credential).
    ///
    /// - Parameter resolveSecret: Injected for testability; defaults to `op read`.
    public static func resolve(
        _ config: AtlassianMCPConfig,
        resolveSecret: (String) -> String? = GatewayResolver.opRead
    ) -> Resolved? {
        guard !config.isEmpty else { return nil }

        let email = config.email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else {
            NSLog("[AtlassianMCPResolver] No account email set; skipping MCP injection")
            return nil
        }

        let tokenRef = config.tokenRef.trimmingCharacters(in: .whitespaces)
        guard !tokenRef.isEmpty else {
            NSLog("[AtlassianMCPResolver] No API token set; skipping MCP injection")
            return nil
        }

        let token: String
        if tokenRef.hasPrefix("op://") {
            guard let secret = resolveSecret(tokenRef) else {
                NSLog("[AtlassianMCPResolver] Failed to resolve API token reference (op read failed or op not signed in); skipping MCP injection")
                return nil
            }
            token = secret
        } else {
            token = tokenRef
        }

        let credential = "\(email):\(token)"
        guard let encoded = credential.data(using: .utf8)?.base64EncodedString() else {
            return nil
        }
        return Resolved(endpoint: config.resolvedEndpoint, authorization: "Basic \(encoded)")
    }
}
