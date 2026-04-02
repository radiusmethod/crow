import Foundation
import RmCore

/// Detects provider from URL and fetches ticket details.
public actor ProviderManager {
    public init() {}

    /// Detect provider from a URL string.
    public func detectProvider(from url: String) -> (provider: Provider, cli: String, host: String?) {
        if url.contains("github.com") {
            return (.github, "gh", nil)
        } else if url.contains("repo1.dso.mil") {
            return (.gitlab, "glab", "repo1.dso.mil")
        } else if url.contains("code.il2.dso.mil") {
            return (.gitlab, "glab", "code.il2.dso.mil")
        } else if url.contains("gitlab.com") {
            return (.gitlab, "glab", "gitlab.com")
        }
        return (.github, "gh", nil)
    }

    /// Parse issue/PR number and repo from a URL.
    public func parseTicketURL(_ url: String) -> (org: String, repo: String, number: Int, isMR: Bool)? {
        // GitHub: https://github.com/{org}/{repo}/issues/{number}
        // GitHub: https://github.com/{org}/{repo}/pull/{number}
        // GitLab: https://host/{org}/{repo}/-/issues/{number}
        // GitLab: https://host/{org}/{repo}/-/merge_requests/{number}
        let parts = url.split(separator: "/").map(String.init)
        guard parts.count >= 5 else { return nil }

        if url.contains("github.com") {
            // parts: ["https:", "", "github.com", org, repo, "issues"|"pull", number]
            guard parts.count >= 7,
                  let number = Int(parts[parts.count - 1]) else { return nil }
            let org = parts[3]
            let repo = parts[4]
            let isMR = parts[parts.count - 2] == "pull"
            return (org, repo, number, isMR)
        } else {
            // GitLab: ["https:", "", host, org, repo, "-", "issues"|"merge_requests", number]
            guard parts.count >= 8,
                  let number = Int(parts[parts.count - 1]) else { return nil }
            let org = parts[3]
            let repo = parts[4]
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
                output = try await shell(env: env, "glab", "mr", "view", "\(parsed.number)", "--repo", repoSlug)
            } else {
                output = try await shell(env: env, "glab", "issue", "view", "\(parsed.number)", "--repo", repoSlug)
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

    private func shell(env: [String: String] = [:], _ args: String...) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if !env.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            process.environment = environment
        }
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
