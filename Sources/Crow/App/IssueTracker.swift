import Foundation
import CrowCore
import CrowPersistence

/// Polls GitHub/GitLab for issues assigned to the current user.
@MainActor
final class IssueTracker {
    private let appState: AppState
    private var timer: Timer?
    private let pollInterval: TimeInterval = 60 // 1 minute

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

        // Fetch PR status (pipeline, review, mergeability) for sessions with PR links
        await fetchPRStatuses()

        // Fetch done issues (closed in last 24h) and merge them in
        if checkedGitHub {
            let doneIssues = await fetchDoneIssuesLast24h()
            // Avoid duplicates — a recently-closed issue may still appear in the open search
            let openIDs = Set(allIssues.map(\.id))
            let uniqueDone = doneIssues.filter { !openIDs.contains($0.id) }
            allIssues.append(contentsOf: uniqueDone)
            appState.doneIssuesLast24h = doneIssues.count
        }

        appState.assignedIssues = allIssues

        // Sync session status for tickets that are "In Review" on the project board
        syncInReviewSessions(issues: allIssues)

        // Auto-complete sessions whose linked issue/PR is no longer open
        await autoCompleteFinishedSessions(openIssues: allIssues.filter { $0.state == "open" })
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
                "--state", "all",
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
            var url = output.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip .git suffix first
            if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
            // Parse: https://github.com/org/repo or git@github.com:org/repo
            if let match = url.range(of: #"[:/]([^/:]+/[^/:]+)$"#, options: .regularExpression) {
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

    // MARK: - PR Status Enrichment

    private func fetchPRStatuses() async {
        // Check all non-manager sessions (active + completed) so merged PRs show correct status
        let sessionsWithPRs = appState.sessions.filter { $0.id != AppState.managerSessionID }
        for session in sessionsWithPRs {
            let links = appState.links(for: session.id)
            guard let prLink = links.first(where: { $0.linkType == .pr }) else { continue }

            guard let output = try? await shell(
                "gh", "pr", "view", prLink.url,
                "--json", "state,mergeable,reviewDecision,statusCheckRollup"
            ) else { continue }

            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Parse checks
            var checksPass: PRStatus.CheckStatus = .unknown
            var failedChecks: [String] = []
            if let checks = json["statusCheckRollup"] as? [[String: Any]] {
                if checks.isEmpty {
                    checksPass = .unknown
                } else {
                    let hasPending = checks.contains { ($0["status"] as? String) != "COMPLETED" }
                    let hasFailed = checks.contains { ($0["conclusion"] as? String) == "FAILURE" }
                    if hasPending {
                        checksPass = .pending
                    } else if hasFailed {
                        checksPass = .failing
                        failedChecks = checks.filter { ($0["conclusion"] as? String) == "FAILURE" }
                            .compactMap { $0["name"] as? String }
                    } else {
                        checksPass = .passing
                    }
                }
            }

            // Parse review status
            let reviewStatus: PRStatus.ReviewStatus
            switch json["reviewDecision"] as? String {
            case "APPROVED": reviewStatus = .approved
            case "CHANGES_REQUESTED": reviewStatus = .changesRequested
            case "REVIEW_REQUIRED": reviewStatus = .reviewRequired
            case "": reviewStatus = .reviewRequired  // empty string means no reviews yet
            default: reviewStatus = .unknown
            }

            // Parse merge status — check PR state first for merged
            let prState = json["state"] as? String
            let mergeStatus: PRStatus.MergeStatus
            if prState == "MERGED" {
                mergeStatus = .merged
            } else {
                switch json["mergeable"] as? String {
                case "MERGEABLE": mergeStatus = .mergeable
                case "CONFLICTING": mergeStatus = .conflicting
                default: mergeStatus = .unknown
                }
            }

            appState.prStatus[session.id] = PRStatus(
                checksPass: checksPass,
                reviewStatus: reviewStatus,
                mergeable: mergeStatus,
                failedCheckNames: failedChecks
            )
        }
    }

    // MARK: - Done Issues (Last 24h)

    private func fetchDoneIssuesLast24h() async -> [AssignedIssue] {
        let formatter = ISO8601DateFormatter()
        let since = formatter.string(from: Date().addingTimeInterval(-86400))

        guard let output = try? await shell(
            "gh", "search", "issues",
            "--assignee", "@me",
            "--state", "closed",
            "--json", "number,title,state,labels,url,repository,updatedAt",
            "--limit", "50",
            "--", "closed:>\(since)"
        ) else { return [] }

        guard let data = output.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AssignedIssue? in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let url = item["url"] as? String else { return nil }

            let state = item["state"] as? String ?? "closed"
            let labels = (item["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let repoDict = item["repository"] as? [String: Any]
            let repoName = repoDict?["nameWithOwner"] as? String ?? ""

            var updatedAt: Date?
            if let dateStr = item["updatedAt"] as? String {
                updatedAt = formatter.date(from: dateStr)
            }

            return AssignedIssue(
                id: "github:\(repoName)#\(number)",
                number: number, title: title, state: state.lowercased(),
                url: url, repo: repoName, labels: labels, provider: .github,
                updatedAt: updatedAt, projectStatus: .done
            )
        }
    }

    // MARK: - Auto-Complete Finished Sessions

    /// Sync active sessions whose linked ticket has "In Review" project status to .inReview session status.
    private func syncInReviewSessions(issues: [AssignedIssue]) {
        let inReviewURLs = Set(issues.filter { $0.projectStatus == .inReview }.map(\.url))

        for session in appState.activeSessions {
            guard let ticketURL = session.ticketURL else { continue }
            if inReviewURLs.contains(ticketURL) {
                print("[IssueTracker] Session '\(session.name)' — ticket is In Review on project board, updating session status")
                appState.onSetSessionInReview?(session.id)
            }
        }
    }

    /// Check active sessions whose linked ticket is no longer in the open issues list.
    /// If the session has a PR link and that PR was merged, mark the session as completed.
    private func autoCompleteFinishedSessions(openIssues: [AssignedIssue]) async {
        let openIssueURLs = Set(openIssues.map(\.url))

        let candidateSessions = appState.sessions.filter {
            $0.id != AppState.managerSessionID &&
            ($0.status == .active || $0.status == .paused || $0.status == .inReview)
        }
        for session in candidateSessions {
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

    // MARK: - Mark In Review

    func markInReview(sessionID: UUID) async {
        guard let session = appState.sessions.first(where: { $0.id == sessionID }),
              let ticketURL = session.ticketURL,
              session.provider == .github else { return }

        // Parse owner/repo/number from URL like "https://github.com/org/repo/issues/123"
        let components = ticketURL.split(separator: "/")
        guard components.count >= 5,
              let number = Int(components.last ?? "") else {
            print("[IssueTracker] Could not parse ticket URL: \(ticketURL)")
            return
        }
        let owner = String(components[components.count - 4])
        let repoName = String(components[components.count - 3])

        appState.isMarkingInReview[sessionID] = true
        defer { appState.isMarkingInReview[sessionID] = false }

        // Step 1: Query for project item ID, project ID, field ID, and "In Review" option ID
        let query = """
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              projectItems(first: 10) {
                nodes {
                  id
                  project { id }
                  fieldValueByName(name: "Status") {
                    ... on ProjectV2ItemFieldSingleSelectValue {
                      name
                      field {
                        ... on ProjectV2SingleSelectField {
                          id
                          options { id name }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let queryResult = await shellWithStatus(
            "gh", "api", "graphql",
            "-f", "query=\(query)",
            "-F", "owner=\(owner)",
            "-F", "repo=\(repoName)",
            "-F", "number=\(number)"
        )

        if queryResult.exitCode != 0 {
            if queryResult.stderr.contains("INSUFFICIENT_SCOPES") || queryResult.stderr.contains("read:project") || queryResult.stderr.contains("project") {
                print("[IssueTracker] GitHub token missing 'project' scope — run 'gh auth refresh -s project'")
            } else {
                print("[IssueTracker] GraphQL query failed: \(queryResult.stderr.prefix(200))")
            }
            return
        }

        // Parse the query response
        guard let data = queryResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let repository = dataObj["repository"] as? [String: Any],
              let issueObj = repository["issue"] as? [String: Any],
              let projectItems = issueObj["projectItems"] as? [String: Any],
              let nodes = projectItems["nodes"] as? [[String: Any]],
              !nodes.isEmpty else {
            print("[IssueTracker] Issue \(owner)/\(repoName)#\(number) is not in any GitHub Project")
            return
        }

        // Find a project item that has a Status field with an "In Review" option
        var itemID: String?
        var projectID: String?
        var fieldID: String?
        var optionID: String?

        for node in nodes {
            guard let nodeID = node["id"] as? String,
                  let project = node["project"] as? [String: Any],
                  let projID = project["id"] as? String,
                  let fieldValue = node["fieldValueByName"] as? [String: Any],
                  let field = fieldValue["field"] as? [String: Any],
                  let fID = field["id"] as? String,
                  let options = field["options"] as? [[String: Any]] else { continue }

            // Find the "In Review" option (case-insensitive)
            for option in options {
                guard let optName = option["name"] as? String,
                      let optID = option["id"] as? String else { continue }
                let normalized = optName.lowercased().trimmingCharacters(in: .whitespaces)
                if normalized == "in review" || normalized == "review" {
                    itemID = nodeID
                    projectID = projID
                    fieldID = fID
                    optionID = optID
                    break
                }
            }
            if optionID != nil { break }
        }

        guard let itemID, let projectID, let fieldID, let optionID else {
            print("[IssueTracker] No 'In Review' status option found in project for \(owner)/\(repoName)#\(number)")
            return
        }

        // Step 2: Mutation to update the status
        let mutation = """
        mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $projectId, itemId: $itemId, fieldId: $fieldId,
            value: { singleSelectOptionId: $optionId }
          }) { projectV2Item { id } }
        }
        """

        let mutationResult = await shellWithStatus(
            "gh", "api", "graphql",
            "-f", "query=\(mutation)",
            "-F", "projectId=\(projectID)",
            "-F", "itemId=\(itemID)",
            "-F", "fieldId=\(fieldID)",
            "-F", "optionId=\(optionID)"
        )

        if mutationResult.exitCode != 0 {
            if mutationResult.stderr.contains("INSUFFICIENT_SCOPES") {
                print("[IssueTracker] GitHub token missing 'project' scope — run 'gh auth refresh -s project'")
            } else {
                print("[IssueTracker] Failed to update project status: \(mutationResult.stderr.prefix(200))")
            }
            return
        }

        // Update local state
        if let idx = appState.assignedIssues.firstIndex(where: {
            $0.repo == "\(owner)/\(repoName)" && $0.number == number
        }) {
            appState.assignedIssues[idx].projectStatus = .inReview
        }

        print("[IssueTracker] Marked \(owner)/\(repoName)#\(number) as In Review")

        // Update local session status to .inReview
        appState.onSetSessionInReview?(sessionID)
    }

    // MARK: - Shell

    private func shell(env: [String: String] = [:], _ args: String...) async throws -> String {
        let args = args
        let env = env
        return try await Task.detached {
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
        }.value
    }

    private struct ShellResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func shellWithStatus(_ args: String...) async -> ShellResult {
        let args = args
        return await Task.detached {
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
        }.value
    }
}
