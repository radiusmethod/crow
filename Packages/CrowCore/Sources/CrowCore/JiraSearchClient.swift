import Foundation

/// Fetches the operator's **assigned Jira work items** for the ticket board via
/// the Jira Cloud REST API, so the board read-back agrees with Jira (#533).
///
/// Why REST and not `acli` / the agent-side MCP — same reasoning as
/// ``JiraTransitionClient`` and ``JiraStatusFetcher``: `acli` requires a separate
/// install + auth, and the session-side `jira` MCP isn't reachable from the Crow
/// app process. The app drives the read itself over REST, authenticated with the
/// same Atlassian email + API token used elsewhere (HTTP Basic via
/// ``JiraCredentialResolver``). Mirrors ``JiraStatusFetcher`` — same site host,
/// same credential, injectable transport for tests.
///
/// Uses Jira Cloud's enhanced JQL search endpoint
/// `GET /rest/api/3/search/jql` (the legacy `/rest/api/3/search` was removed on
/// Cloud). A single page of up to `maxResults` items is fetched, matching the
/// previous `acli --limit 100` behavior; token pagination (`nextPageToken`) is a
/// follow-up if boards ever exceed a page.
public enum JiraSearchClient {
    public enum FetchError: Error, Equatable {
        case badSite
        case http(Int)
        case transport(String)
        case decode
    }

    /// Build the enhanced-search REST URL for a site host + JQL + fields. Accepts
    /// a bare host (`acme.atlassian.net`) or a full origin; the scheme is always
    /// forced to **https** so the Basic credential is never sent in cleartext
    /// (mirrors ``JiraStatusFetcher/statusesURL(site:projectKey:)``).
    static func searchURL(site: String, jql: String, fields: [String], maxResults: Int) -> URL? {
        let trimmedSite = site.trimmingCharacters(in: .whitespaces)
        let trimmedJQL = jql.trimmingCharacters(in: .whitespaces)
        guard !trimmedSite.isEmpty, !trimmedJQL.isEmpty else { return nil }
        let bareHost = trimmedSite.range(of: "://").map { String(trimmedSite[$0.upperBound...]) } ?? trimmedSite
        guard !bareHost.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = bareHost
        components.path = "/rest/api/3/search/jql"
        components.queryItems = [
            URLQueryItem(name: "jql", value: trimmedJQL),
            URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
        ]
        return components.url
    }

    /// Parse the `search/jql` payload (`{ "issues": [ { key, fields:{…} } ] }`)
    /// into the raw issue dictionaries. Returns the (possibly empty) `issues`
    /// array, or `nil` when the payload shape is unrecognized.
    static func parseIssues(_ data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let issues = json["issues"] as? [[String: Any]] else {
            // A well-formed response with no matches still carries an `issues` key;
            // a missing key means an unexpected shape.
            return nil
        }
        return issues
    }

    /// Fetch the assigned work items matching `jql` on `site`, authenticated with
    /// `authorization` (a full header value, e.g. `Basic …` from
    /// ``JiraCredentialResolver``). Returns the raw issue dictionaries (each
    /// `{ key, fields }`) for the caller to map. Injectable transport for testing.
    public static func fetchAssigned(
        site: String,
        jql: String,
        authorization: String,
        fields: [String] = ["key", "summary", "status", "labels"],
        maxResults: Int = 100,
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async -> Result<[[String: Any]], FetchError> {
        guard let url = searchURL(site: site, jql: jql, fields: fields, maxResults: maxResults) else {
            return .failure(.badSite)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await transport(request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(.http(http.statusCode))
            }
            guard let issues = parseIssues(data) else { return .failure(.decode) }
            return .success(issues)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}
