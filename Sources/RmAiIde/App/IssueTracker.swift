import Foundation
import RmCore
import RmPersistence

/// Polls GitHub/GitLab for issues assigned to the current user.
@MainActor
final class IssueTracker {
    private let appState: AppState
    private var timer: Timer?
    private let pollInterval: TimeInterval = 300 // 5 minutes

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Initial fetch
        Task { await refresh() }

        // Poll every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        appState.isLoadingIssues = true
        defer { appState.isLoadingIssues = false }

        var allIssues: [AssignedIssue] = []

        // Load config to know which workspaces/repos to check
        guard let devRoot = ConfigStore.loadDevRoot(),
              let config = ConfigStore.loadConfig(devRoot: devRoot) else { return }

        // Collect unique providers
        var checkedGitHub = false
        var checkedGitLabHosts: Set<String> = []

        for ws in config.workspaces {
            if ws.provider == "github" && !checkedGitHub {
                checkedGitHub = true
                let issues = await fetchGitHubIssues()
                allIssues.append(contentsOf: issues)
            } else if ws.provider == "gitlab", let host = ws.host, !checkedGitLabHosts.contains(host) {
                checkedGitLabHosts.insert(host)
                let issues = await fetchGitLabIssues(host: host)
                allIssues.append(contentsOf: issues)
            }
        }

        // Also check for PRs linked to these issues
        let prs = await fetchGitHubPRs()
        for pr in prs {
            // Match PRs to issues by closingIssuesReferences
            for linkedIssueNum in pr.linkedIssueNumbers {
                if let idx = allIssues.firstIndex(where: { $0.number == linkedIssueNum && $0.provider == .github }) {
                    allIssues[idx].prNumber = pr.number
                    allIssues[idx].prURL = pr.url
                }
            }
        }

        // Fetch project board status for GitHub issues
        await fetchGitHubProjectStatuses(for: &allIssues)

        // Check for PRs on active session branches
        await checkSessionPRs(config: config)

        appState.assignedIssues = allIssues

        // Auto-complete sessions whose linked issue/PR is no longer open
        await autoCompleteFinishedSessions(openIssues: allIssues)
    }

    // MARK: - GitHub

    private func fetchGitHubIssues() async -> [AssignedIssue] {
        // Use gh search issues to find ALL issues assigned to me across all repos
        guard let output = try? await shell(
            "gh", "search", "issues",
            "--assignee", "@me",
            "--state", "open",
            "--json", "number,title,state,labels,url,repository,updatedAt",
            "--limit", "100"
        ) else { return [] }

        guard let data = output.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AssignedIssue? in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let url = item["url"] as? String else { return nil }

            let state = item["state"] as? String ?? "open"
            let labels = (item["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let repoDict = item["repository"] as? [String: Any]
            let repoName = repoDict?["nameWithOwner"] as? String ?? ""

            return AssignedIssue(
                id: "github:\(repoName)#\(number)",
                number: number, title: title, state: state.lowercased(),
                url: url, repo: repoName, labels: labels, provider: .github
            )
        }
    }

    private struct PRInfo {
        let number: Int
        let url: String
        let branch: String
        let linkedIssueNumbers: [Int]
    }

    private func fetchGitHubPRs() async -> [PRInfo] {
        guard let output = try? await shell(
            "gh", "pr", "list", "--author", "@me", "--state", "open",
            "--json", "number,url,headRefName,closingIssuesReferences",
            "--limit", "20"
        ) else { return [] }

        guard let data = output.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return items.compactMap { item -> PRInfo? in
            guard let number = item["number"] as? Int,
                  let url = item["url"] as? String,
                  let branch = item["headRefName"] as? String else { return nil }

            let linkedIssues = (item["closingIssuesReferences"] as? [[String: Any]])?
                .compactMap { $0["number"] as? Int } ?? []

            return PRInfo(number: number, url: url, branch: branch, linkedIssueNumbers: linkedIssues)
        }
    }

    // MARK: - GitLab

    private func fetchGitLabIssues(host: String) async -> [AssignedIssue] {
        guard let output = try? await shell(
            env: ["GITLAB_HOST": host],
            "glab", "issue", "list", "-a", "@me", "--output-format", "json"
        ) else { return [] }

        guard let data = output.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AssignedIssue? in
            guard let number = item["iid"] as? Int,
                  let title = item["title"] as? String,
                  let url = item["web_url"] as? String else { return nil }

            let state = item["state"] as? String ?? "opened"
            let labels = item["labels"] as? [String] ?? []
            let refs = item["references"] as? [String: Any]
            let fullRef = refs?["full"] as? String ?? ""

            return AssignedIssue(
                id: "gitlab:\(host):\(fullRef)",
                number: number, title: title, state: state == "opened" ? "open" : state,
                url: url, repo: fullRef, labels: labels, provider: .gitlab
            )
        }
    }

    // MARK: - Session PR Detection

    private func checkSessionPRs(config: AppConfig) async {
        let store = JSONStore()

        for session in appState.sessions {
            guard session.id != AppState.managerSessionID else { continue }
            let wts = appState.worktrees(for: session.id)
            let links = appState.links(for: session.id)

            // Skip if already has a PR link
            guard !links.contains(where: { $0.linkType == .pr }) else { continue }

            // Check primary worktree's branch for an open PR
            guard let primaryWt = wts.first(where: { $0.isPrimary }) ?? wts.first else { continue }

            let branch = primaryWt.branch
            guard !branch.isEmpty else { continue }

            // Derive the org/repo slug from the worktree's repo path or repo name
            let repoSlug = resolveRepoSlug(worktree: primaryWt)
            guard !repoSlug.isEmpty else { continue }

            if let output = try? await shell(
                "gh", "pr", "list", "--repo", repoSlug, "--head", branch,
                "--json", "number,url,state", "--limit", "1"
            ), let data = output.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let pr = items.first,
               let prNum = pr["number"] as? Int,
               let prURL = pr["url"] as? String {

                let link = SessionLink(
                    sessionID: session.id,
                    label: "PR #\(prNum)",
                    url: prURL,
                    linkType: .pr
                )
                appState.links[session.id, default: []].append(link)

                // Persist the PR link
                store.mutate { data in
                    data.links.append(link)
                }
            }
        }
    }

    /// Resolve the org/repo slug (e.g. "radiusmethod/citadel") from a worktree's git remote.
    private func resolveRepoSlug(worktree: SessionWorktree) -> String {
        // First try from the repo path's git remote
        if let output = try? shellSync(
            "git", "-C", worktree.repoPath, "remote", "get-url", "origin"
        ) {
            let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
            // Parse: https://github.com/org/repo.git or git@github.com:org/repo.git
            if let match = url.range(of: #"[:/]([^/:]+/[^/.]+?)(?:\.git)?$"#, options: .regularExpression) {
                return String(url[match]).trimmingCharacters(in: CharacterSet(charactersIn: "/:"))
            }
        }
        // Fallback to repoName if it looks like org/repo
        if worktree.repoName.contains("/") { return worktree.repoName }
        return ""
    }

    private func shellSync(_ args: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "IssueTracker", code: Int(process.terminationStatus))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Auto-Complete Finished Sessions

    /// Check active sessions whose linked ticket is no longer in the open issues list.
    /// If the session has a PR link and that PR was merged, mark the session as completed.
    private func autoCompleteFinishedSessions(openIssues: [AssignedIssue]) async {
        let openIssueURLs = Set(openIssues.map(\.url))

        for session in appState.activeSessions {
            guard let ticketURL = session.ticketURL else { continue }

            // If the issue is still in the open list, it's not finished
            if openIssueURLs.contains(ticketURL) { continue }

            // The issue is no longer open — check if it was closed/merged via PR
            let sessionLinks = appState.links(for: session.id)
            let prLink = sessionLinks.first(where: { $0.linkType == .pr })

            if let prLink {
                // Check if the PR was merged
                let merged = await checkPRMerged(url: prLink.url)
                if merged {
                    print("[IssueTracker] Session '\(session.name)' — PR merged, marking completed")
                    appState.onCompleteSession?(session.id)
                    continue
                }
            }

            // No PR link — check the issue state directly
            let closed = await checkIssueClosed(url: ticketURL, provider: session.provider ?? .github)
            if closed {
                print("[IssueTracker] Session '\(session.name)' — issue closed, marking completed")
                appState.onCompleteSession?(session.id)
            }
        }
    }

    /// Check if a GitHub PR was merged.
    private func checkPRMerged(url: String) async -> Bool {
        guard let output = try? await shell(
            "gh", "pr", "view", url, "--json", "state"
        ) else { return false }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else { return false }

        return state == "MERGED"
    }

    /// Check if an issue is closed.
    private func checkIssueClosed(url: String, provider: Provider) async -> Bool {
        guard provider == .github else { return false }  // GitLab TBD

        guard let output = try? await shell(
            "gh", "issue", "view", url, "--json", "state"
        ) else { return false }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else { return false }

        return state == "CLOSED"
    }

    // MARK: - GitHub Project Status

    private func fetchGitHubProjectStatuses(for issues: inout [AssignedIssue]) async {
        let githubIssues = issues.enumerated().filter { $0.element.provider == .github }
        guard !githubIssues.isEmpty else { return }

        let query = """
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              projectItems(first: 10) {
                nodes {
                  fieldValueByName(name: "Status") {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                }
              }
            }
          }
        }
        """

        // Test with the first issue to detect scope errors early
        let (firstIndex, firstIssue) = githubIssues[0]
        let firstParts = firstIssue.repo.split(separator: "/")
        if firstParts.count == 2 {
            let testResult = await shellWithStatus(
                "gh", "api", "graphql",
                "-f", "query=\(query)",
                "-F", "owner=\(String(firstParts[0]))",
                "-F", "repo=\(String(firstParts[1]))",
                "-F", "number=\(firstIssue.number)"
            )
            if testResult.exitCode != 0 {
                if testResult.stderr.contains("INSUFFICIENT_SCOPES") || testResult.stderr.contains("read:project") {
                    print("[IssueTracker] GitHub token missing 'read:project' scope — run 'gh auth refresh -s read:project'")
                } else {
                    print("[IssueTracker] GraphQL project status query failed (exit \(testResult.exitCode)): \(testResult.stderr.prefix(200))")
                }
                return
            }
        }

        for (index, issue) in githubIssues {
            let parts = issue.repo.split(separator: "/")
            guard parts.count == 2 else { continue }
            let owner = String(parts[0])
            let repoName = String(parts[1])

            guard let output = try? await shell(
                "gh", "api", "graphql",
                "-f", "query=\(query)",
                "-F", "owner=\(owner)",
                "-F", "repo=\(repoName)",
                "-F", "number=\(issue.number)"
            ) else { continue }

            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let repository = dataObj["repository"] as? [String: Any],
                  let issueObj = repository["issue"] as? [String: Any],
                  let projectItems = issueObj["projectItems"] as? [String: Any],
                  let nodes = projectItems["nodes"] as? [[String: Any]] else { continue }

            // Take the first non-nil status from project items
            for node in nodes {
                if let fieldValue = node["fieldValueByName"] as? [String: Any],
                   let statusName = fieldValue["name"] as? String {
                    issues[index].projectStatus = mapProjectStatus(statusName)
                    break
                }
            }
        }
    }

    private func mapProjectStatus(_ name: String) -> TicketStatus {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "backlog":
            return .backlog
        case "ready", "todo", "to do":
            return .ready
        case "in progress", "doing", "active":
            return .inProgress
        case "in review", "review":
            return .inReview
        case "done", "closed", "complete", "completed":
            return .done
        default:
            return .unknown
        }
    }

    // MARK: - Shell

    private func shell(env: [String: String] = [:], _ args: String...) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        if !env.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (k, v) in env { environment[k] = v }
            process.environment = environment
        }
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "IssueTracker", code: Int(process.terminationStatus))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private struct ShellResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func shellWithStatus(_ args: String...) async -> ShellResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return ShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1) }
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
