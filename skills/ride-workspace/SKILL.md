# ride Workspace Setup Skill

## Purpose

Orchestrates work sessions in **rm-ai-ide** by setting up git worktrees and creating a ride session with auto-launched Claude Code and ticket metadata. Supports multiple organizations/workspaces with different Git providers.

This skill targets rm-ai-ide's `ride` CLI. The original `/workspace` skill targeting CMUX remains unchanged and both can run in parallel.

## Important: Sandbox Bypass

All `ride` CLI commands require `dangerouslyDisableSandbox: true` because they communicate via Unix socket at `$TMPDIR/ride.sock`.

## Activation

This skill activates when:
- User invokes `/ride-workspace` command
- User asks to "set up ride workspace" or "start working on" a feature in rm-ai-ide

## Configuration

Configuration is at `{devRoot}/.claude/config.json` (managed by the rm-ai-ide app). The format is:

```json
{
  "devRoot": "/Users/name/Dev",
  "workspaces": {
    "RadiusMethod": {
      "provider": "github",
      "cli": "gh"
    },
    "PlatformOne": {
      "provider": "gitlab",
      "cli": "glab",
      "host": "repo1.dso.mil",
      "alwaysInclude": ["bigbang", "overrides"]
    }
  },
  "defaults": {
    "provider": "github",
    "cli": "gh",
    "worktreePattern": "{repo}-{feature}",
    "branchPrefix": "feature/",
    "excludeDirs": ["node_modules", ".git", "vendor", "dist", "build", "target"],
    "keywordSources": ["CLAUDE.md", "README.md", "package.json", "Cargo.toml", "pyproject.toml", "go.mod"]
  }
}
```

## Multi-Workspace Discovery

### Step 1: Enumerate Workspaces

```bash
ls -d {devRoot}/*/
```

For each workspace: check if it has explicit config, otherwise apply defaults.

### Step 2: Scan Each Workspace for Repos

```bash
for dir in {workspace}/*/; do
  if [ -d "$dir/.git" ]; then
    echo "$dir"
  fi
done
```

### Step 3: Build Global Repo Index

Match repos to input by: direct name match (+10), workspace mention (+5), keyword match (+2 per).

## Git Provider Commands

### GitHub (gh)
```bash
gh issue view {url} --json title,body,labels
gh pr view {url} --json title,body,labels
```

### GitLab (glab)
```bash
GITLAB_HOST=repo1.dso.mil glab issue view {number} --repo {org/repo} --comments
GITLAB_HOST=repo1.dso.mil glab mr view {number} --repo {org/repo} --comments
```

### Provider Detection from URL

| URL Contains | Provider | CLI | GITLAB_HOST |
|---|---|---|---|
| `github.com` | github | gh | - |
| `repo1.dso.mil` | gitlab | glab | repo1.dso.mil |
| `gitlab.com` | gitlab | glab | gitlab.com |
| `code.il2.dso.mil` | gitlab | glab | code.il2.dso.mil |

## Worktree Management

### Naming Convention

**CRITICAL: Worktrees go DIRECTLY under the workspace folder, at the same level as the main repo clone. NOT in a subfolder.**

**For ticket URLs:**
```
{devRoot}/{workspace}/{repo}-{ticket_number}-{brief_slug}
```
Branch: `feature/{repo}-{ticket_number}-{brief_slug}`

The brief slug is 2-4 key words from the ticket title.

**Concrete example with full paths:**
Given: devRoot=`/Users/jane/Dev`, workspace=`RadiusMethod`, repo=`citadel` (cloned at `/Users/jane/Dev/RadiusMethod/citadel`), ticket #197 "Fix tab URL hash routing"

```
Worktree path: /Users/jane/Dev/RadiusMethod/citadel-197-fix-tab-url-hash
Branch:        feature/citadel-197-fix-tab-url-hash
Git command:   git -C /Users/jane/Dev/RadiusMethod/citadel worktree add /Users/jane/Dev/RadiusMethod/citadel-197-fix-tab-url-hash -b feature/citadel-197-fix-tab-url-hash --no-track origin/main
```

More examples:
```
loki #252 "Update grafana-enterprise.md"    → {devRoot}/PlatformOne/loki-252-update-grafana-docs
citadel #45 "Add JWT validation endpoint"   → {devRoot}/RadiusMethod/citadel-45-jwt-validation
```

**WRONG — do NOT create subdirectories:**
```
WRONG: {devRoot}/{workspace}/{repo}-worktrees/{feature}
WRONG: {devRoot}/{workspace}/worktrees/{repo}-{feature}
```

**For natural language (no ticket):**
```
{devRoot}/{workspace}/{repo}-{feature-slug}
```
Branch: `feature/{feature-slug}`

### Git Commands (Provider-Agnostic)

```bash
git -C {repo_path} fetch origin
git -C {repo_path} ls-remote --heads origin feature/{name}

# Existing remote branch:
git -C {repo_path} worktree add {path} \
  -b feature/{name} \
  --track origin/feature/{name}

# New branch:
git -C {repo_path} worktree add {path} \
  -b feature/{name} \
  --no-track \
  origin/main
```

**Important:** Always use `-b` to create a local branch. Without it, the worktree ends up in detached HEAD state. Use `--no-track` for new branches to prevent accidental push to main.

## ride Session Creation

All `ride` commands require `dangerouslyDisableSandbox: true`.

### Complete Step-by-Step Flow

```bash
# 1. Create session (parse session_id from JSON output)
ride new-session --name "{feature_name}"
# Output: {"session_id":"<uuid>","name":"feature_name"}

# 2. Set ticket metadata (only if URL was provided)
ride set-ticket --session {session_id} \
  --url "{ticket_url}" \
  --title "{ticket_title}" \
  --number {ticket_number}

# 3. Register each worktree (after creating with git)
#    IMPORTANT: --repo-path is the MAIN repo path (e.g., .../citadel)
#    --path is the WORKTREE path (e.g., .../citadel-197-slug)
ride add-worktree --session {session_id} \
  --repo "{repo_name}" \
  --repo-path "{main_repo_path}" \
  --path "{worktree_path}" \
  --branch "feature/{name}" \
  --primary   # for the first/main repo

# 4. Add ticket link (only if URL was provided)
ride add-link --session {session_id} \
  --label "Issue" \
  --url "{ticket_url}" \
  --type ticket

# 4b. Auto-assign and set project status (GitHub issues only, best-effort)
#     All gh commands require dangerouslyDisableSandbox: true.
#     Don't fail the workspace setup if these error.
#
#     Step A: Assign yourself to the issue
gh issue edit {ticket_url} --add-assignee @me
#
#     Step B: Set the issue's project status to "In progress"
#     This requires multiple GraphQL calls chained together:
#     1. Get the projectItem ID and project ID for the issue
#     2. Get the Status field ID from the project
#     3. Get the option ID for "In progress" from the Status field options
#     4. Mutate the field value
#
#     Use gh api graphql with --jq to extract values. Chain them:
#       - query repository.issue.projectItems.nodes[0] for {itemId, project.id}
#       - query node(id: projectId).field(name: "Status") for fieldId and options
#       - find the option where name == "In progress" (case-sensitive, match exactly)
#       - call updateProjectV2ItemFieldValue mutation
#     If the issue is not on any project, skip silently.

# 5. Write prompt to temp file
#    IMPORTANT: Write to {devRoot}/.claude/prompts/ — NOT $TMPDIR (which differs per session)
#    The prompt MUST start with /plan to enter plan mode
mkdir -p {devRoot}/.claude/prompts
cat > {devRoot}/.claude/prompts/ride-prompt-{feature_name}.md << 'PROMPT'
{prompt content — see template below}
PROMPT

# 6. Create a shell terminal in the primary worktree (NO command — just a shell)
ride new-terminal --session {session_id} \
  --cwd "{primary_worktree_path}" \
  --name "Claude Code"
# Output: {"terminal_id":"<uuid>","session_id":"..."}
# IMPORTANT: Capture the terminal_id from the output!

# 7. Switch to the new session so the terminal gets created in the UI
ride select-session --session {session_id}

# 8. Wait for the shell to initialize (the terminal needs to be visible and ready)
sleep 3

# 9. Send the claude launch command to the terminal
#    CRITICAL: End the text with literal \n — the app converts \n to Enter.
#    Use single quotes so the shell doesn't expand $(cat ...).
#    Use --permission-mode plan to start Claude in plan mode.
#    Use full path to claude binary (avoid CMUX wrapper).
ride send --session {session_id} --terminal {terminal_id} 'cd {primary_worktree_path} && {claude_binary_path} --permission-mode plan "$(cat {devRoot}/.claude/prompts/ride-prompt-{feature_name}.md)"\n'
```

## First Prompt Template

IMPORTANT: Always use full absolute paths, never abbreviated (`...`) or home-relative (`~`) paths.

The prompt is written to `{devRoot}/.claude/prompts/ride-prompt-{feature_name}.md`. It starts with `/plan` to enter plan mode.

**Repo descriptions for the prompt table:**

Hardcoded descriptions:
- `bigbang` → "Umbrella Helm chart that loads in specific product packages"
- `overrides` → "Helm install overrides used for testing; create overrides here when testing changes"
- `codename-spotlight` → "Infrastructure monorepo containing Citadel, SocketZero, and related services"

For all other repos, extract dynamically from first non-heading line of CLAUDE.md or README.md.

~~~markdown
# Workspace Context

| Repository | Path | Branch | Description |
|------------|------|--------|-------------|
| citadel | /Users/name/Dev/RadiusMethod/citadel-45-jwt | feature/citadel-45-jwt-validation | Auth gateway service |
| bigbang | /Users/name/Dev/PlatformOne/bigbang | main | Umbrella Helm chart that loads in specific product packages |
| overrides | /Users/name/Dev/PlatformOne/overrides | - | Helm install overrides used for testing; create overrides here when testing changes |

## Ticket

IMPORTANT: All gh/glab commands MUST use dangerouslyDisableSandbox: true. They will fail with TLS certificate errors otherwise. Do NOT attempt sandboxed first.

```bash
gh issue view https://github.com/org/repo/issues/123 --comments
```

## Instructions
1. Study the ticket thoroughly — use dangerouslyDisableSandbox: true for ALL gh/glab commands
2. Create an implementation plan
~~~

For PlatformOne, add: `3. If any changes to bigbang are required, create a new worktree with a feature branch before making modifications`

### CLI Commands for Fetching Issues

**GitHub:**
```bash
gh issue view {url} --comments
gh pr view {url} --comments
```

**GitLab (non-default host like repo1.dso.mil):**
```bash
GITLAB_HOST=repo1.dso.mil glab issue view {number} --repo {org/repo} --comments
GITLAB_HOST=repo1.dso.mil glab mr view {number} --repo {org/repo} --comments
```

## Error Handling and Self-Correction

If a `ride` command fails:
1. Read the error message from the JSON response
2. If the error indicates a usage problem (wrong arg format, missing param), append a one-line correction to `{devRoot}/CLAUDE.md` under "## Known Issues / Corrections"
3. Retry with corrected command
4. If transient error (socket unavailable), retry up to 3 times with 1s delay

| Error | Response |
|-------|----------|
| Socket not found | rm-ai-ide app may not be running. Inform user. |
| Session not found | Use full UUID from new-session output, not short names |
| Unknown workspace | Use defaults, warn user |
| CLI not installed | Report which CLI is needed (gh, glab) |
| No repos matched | List all repos across all workspaces |

## ride CLI Reference

```
ride new-session --name "name"
ride rename-session --session <uuid> "name"
ride select-session --session <uuid>
ride list-sessions
ride get-session --session <uuid>
ride set-status --session <uuid> active|completed|archived
ride delete-session --session <uuid>
ride set-ticket --session <uuid> --url "..." [--title "..."] [--number N]
ride add-worktree --session <uuid> --repo "name" --repo-path "/main/repo/path" --path "/worktree/path" --branch "..." [--primary]
ride list-worktrees --session <uuid>
ride new-terminal --session <uuid> --cwd "/..." [--name "..."] [--command "..."]
ride list-terminals --session <uuid>
ride send --session <uuid> --terminal <uuid> "text"
ride add-link --session <uuid> --label "..." --url "..." --type ticket|pr|repo|custom
ride list-links --session <uuid>
```

All commands return JSON and require `dangerouslyDisableSandbox: true`.

## Examples

### GitHub Issue URL
```
/ride-workspace https://github.com/RadiusMethod/citadel/issues/45
```
→ Fetches issue #45, matches citadel in RadiusMethod
→ Creates worktree at ~/Dev/RadiusMethod/citadel-45-jwt-validation
→ Creates ride session with ticket metadata + worktree + Claude Code terminal

### Natural Language
```
/ride-workspace "update citadel authentication"
```
→ Scans repos, matches citadel by keyword
→ Creates worktree with feature slug
→ Creates ride session with Claude Code terminal

### Cross-Workspace
```
/ride-workspace "integrate bigbang with citadel gateway"
```
→ Matches bigbang (PlatformOne) + citadel (RadiusMethod)
→ Creates worktrees for both, one ride session
→ Claude launches in highest-scoring repo
