import Foundation
import CrowCore

/// Detects provider from URL and fetches ticket details.
public actor ProviderManager {
    /// Additional GitLab hosts beyond gitlab.com (user-configurable).
    private let additionalGitLabHosts: [String]

    public init(additionalGitLabHosts: [String] = []) {
        self.additionalGitLabHosts = additionalGitLabHosts
    }

    /// Detect provider from a URL string.
    ///
    /// Falls back to `.github` for unrecognized hosts — the `gh` CLI call will fail clearly
    /// if the URL is actually a self-hosted GitLab instance, which is an acceptable failure mode.
    public func detectProvider(from url: String) -> (provider: Provider, cli: String, host: String?) {
        if url.contains("github.com") {
            return (.github, "gh", nil)
        } else if url.contains("gitlab.com") {
            return (.gitlab, "glab", "gitlab.com")
        }
        // Check user-configured GitLab hosts
        for host in additionalGitLabHosts {
            if url.contains(host) {
                return (.gitlab, "glab", host)
            }
        }
        return (.github, "gh", nil)
    }

    /// Parse issue/PR number and repo from a ticket URL.
    ///
    /// Supported formats:
    /// - GitHub issue: `https://github.com/{org}/{repo}/issues/{number}`
    /// - GitHub PR:    `https://github.com/{org}/{repo}/pull/{number}`
    /// - GitLab issue: `https://{host}/{org}/{repo}/-/issues/{number}`
    /// - GitLab MR:    `https://{host}/{org}/{repo}/-/merge_requests/{number}`
    ///
    /// - Returns: A tuple of `(org, repo, number, isMR)` where `isMR` is true for pull requests
    ///   and merge requests, or `nil` if the URL doesn't match a supported format.
    public func parseTicketURL(_ url: String) -> (org: String, repo: String, number: Int, isMR: Bool)? {
        Self.parseTicketURLComponents(url)
    }

    /// Static variant of ``parseTicketURL(_:)`` usable without an actor instance.
    public static func parseTicketURLComponents(_ url: String) -> (org: String, repo: String, number: Int, isMR: Bool)? {
        // split(separator:) omits empty subsequences, so "https://host/..." becomes:
        // ["https:", "host", "org", "repo", ...]
        let parts = url.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return nil }

        if url.contains("github.com") {
            // ["https:", "github.com", org, repo, "issues"|"pull", number]
            guard parts.count >= 6,
                  let number = Int(parts[parts.count - 1]) else { return nil }
            let org = parts[2]
            let repo = parts[3]
            let isMR = parts[parts.count - 2] == "pull"
            return (org, repo, number, isMR)
        } else {
            // GitLab: ["https:", host, org, repo, "-", "issues"|"merge_requests", number]
            guard parts.count >= 7,
                  let number = Int(parts[parts.count - 1]) else { return nil }
            let org = parts[2]
            let repo = parts[3]
            let isMR = parts[parts.count - 2] == "merge_requests"
            return (org, repo, number, isMR)
        }
    }

    /// Fetch ticket details using gh/glab CLI.
    public func fetchTicket(url: String) async throws -> TicketInfo {
        let detected = detectProvider(from: url)
        guard let parsed = parseTicketURL(url) else {
            throw ProviderError.invalidURL(url)
        }

        let output: String
        switch detected.provider {
        case .github:
            if parsed.isMR {
                output = try await shell("gh", "pr", "view", url, "--json", "title,body,labels")
            } else {
                output = try await shell("gh", "issue", "view", url, "--json", "title,body,labels")
            }
        case .gitlab:
            var env: [String: String] = [:]
            if let host = detected.host {
                env["GITLAB_HOST"] = host
            }
            let repoSlug = "\(parsed.org)/\(parsed.repo)"
            if parsed.isMR {
                output = try await shell(env: env, cwd: NSHomeDirectory(), "glab", "mr", "view", "\(parsed.number)", "--repo", repoSlug)
            } else {
                output = try await shell(env: env, cwd: NSHomeDirectory(), "glab", "issue", "view", "\(parsed.number)", "--repo", repoSlug)
            }
        }

        // Parse title from JSON output (GitHub returns JSON, GitLab returns text)
        let title = extractTitle(from: output) ?? "Ticket #\(parsed.number)"

        return TicketInfo(
            number: parsed.number,
            title: title,
            repo: parsed.repo,
            org: parsed.org,
            url: url,
            provider: detected.provider,
            isMR: parsed.isMR
        )
    }

    private func extractTitle(from output: String) -> String? {
        // Try JSON first (GitHub gh output)
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = json["title"] as? String {
            return title
        }
        // Fallback: first line of output (GitLab glab output)
        return output.components(separatedBy: .newlines).first
    }

    private func shell(env: [String: String] = [:], cwd: String? = nil, _ args: String...) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.environment = env.isEmpty
            ? ShellEnvironment.shared.env
            : ShellEnvironment.shared.merging(env)
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw ProviderError.commandFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Details about a ticket (issue or PR/MR) fetched from a provider.
public struct TicketInfo: Sendable {
    public let number: Int
    public let title: String
    public let repo: String
    public let org: String
    public let url: String
    public let provider: Provider
    public let isMR: Bool
}

public enum ProviderError: Error {
    case invalidURL(String)
    case commandFailed(String)
}
