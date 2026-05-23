# Crow Create Ticket

Create a new ticket (GitHub issue via `gh`, or GitLab issue via `glab`) for a repo in
the current Crow workspace, assigned to the invoking user and labeled `crow:auto` so
Crow's auto-pickup queue implements it.

## Important: Sandbox Bypass

All `gh`, `glab`, and `git` commands require `dangerouslyDisableSandbox: true` because
they communicate over the network (TLS) or read outside the sandbox-allowed
directories. They will fail with TLS certificate errors otherwise.

## Arguments

- `$ARGUMENTS` — the ticket title (required) and an optional body.
  - The first quoted string is the **title**.
  - Any remaining text (including multiple lines) is the **body**.
  - If no title can be determined, ask the user for one before proceeding.

Examples:
```
/crow-create-ticket "Fix tab URL hash routing"
/crow-create-ticket "Add JWT validation" The /auth endpoint should reject expired tokens.
```

## Activation

This skill activates when:
- User invokes `/crow-create-ticket` command
- User asks to "create a ticket", "file an issue", or "open an issue" in Crow

## Configuration

Configuration is at `{devRoot}/.claude/config.json` (managed by the Crow app), the
same file used by `/crow-workspace`. It maps each workspace to a provider/cli/host:

```json
{
  "devRoot": "/Users/name/Dev",
  "workspaces": {
    "RadiusMethod": { "provider": "github", "cli": "gh" },
    "MyGitLab": { "provider": "gitlab", "cli": "glab", "host": "gitlab.example.com" }
  },
  "defaults": { "provider": "github", "cli": "gh" }
}
```

### Provider Detection

| Workspace `provider` | CLI  | GITLAB_HOST          |
|----------------------|------|----------------------|
| `github`             | gh   | —                    |
| `gitlab`             | glab | workspace `host`     |

## Instructions

You are creating a new ticket from the title/body in `$ARGUMENTS`. Follow these steps.
All `gh`/`glab`/`git` commands below require `dangerouslyDisableSandbox: true`.

### Step 1: Parse the title and body

Extract the title (required) and optional body from `$ARGUMENTS` per the **Arguments**
rules above. If there is no usable title, ask the user for one and stop until provided.

**Keep the body footer-free.** Do NOT append any Crow attribution, "Generated with"
footer, or co-author trailer — those belong on PRs, not issues. The body is exactly
what the user provided (or empty).

### Step 2: Determine the target repo and provider

1. Read the config: `cat {devRoot}/.claude/config.json`
2. If the user named a specific repo, use it. Otherwise, scan the repos in each
   configured workspace and match against the title/body by keyword (the same
   scoring approach as `/crow-workspace`: direct name match, workspace mention,
   keyword matches). Pick the highest-scoring repo.
3. If no repo clearly matches, or several are tied, **ask the user** which repo to
   file the ticket against. Do not guess.
4. Resolve the workspace's `provider`, `cli`, and (for GitLab) `host` from config,
   falling back to `defaults`.
5. Derive the canonical repo identifier from the repo's git remote:
   ```bash
   git -C {repo_path} remote get-url origin
   ```
   - GitHub → parse `OWNER/REPO` from the URL.
   - GitLab → parse the `org/repo` (group/subgroup) path from the URL.

### Step 3: Resolve the current user's login

**GitHub:**
```bash
gh api user --jq .login
```

**GitLab (non-default host):**
```bash
GITLAB_HOST={host} glab api user --jq '.username'
```

### Step 4: Create the issue (assigned + labeled `crow:auto`)

**GitHub:**
```bash
gh issue create --repo OWNER/REPO \
  --title "TITLE" \
  --body "BODY" \
  --assignee "{login}" \
  --label "crow:auto"
```
- If the body is empty, still pass `--body ""` so `gh` does not open an interactive
  editor.

**GitLab (non-default host):**
```bash
GITLAB_HOST={host} glab issue create --repo {org/repo} \
  --title "TITLE" \
  --description "BODY" \
  --assignee "{username}" \
  --label "crow:auto" \
  --yes
```

### Step 5: Missing-label fallback

If `issue create` fails because the `crow:auto` label does not exist in the repo,
create it once, then retry Step 4:

**GitHub:**
```bash
gh label create "crow:auto" --repo OWNER/REPO \
  --color FBCA04 --description "Crow auto-pickup"
```

**GitLab:**
```bash
GITLAB_HOST={host} glab label create --repo {org/repo} \
  --name "crow:auto" --color "#FBCA04" --description "Crow auto-pickup"
```

### Step 6: Report the result

`issue create` prints the URL of the new issue. Report it back to the user along with
the repo, assignee, and `crow:auto` label so they can confirm Crow will pick it up.

## Notes

- This skill only creates the ticket. Crow's auto-pickup queue (driven by the
  `crow:auto` label) is responsible for starting implementation — do not also set up a
  worktree or session here. Use `/crow-workspace` for that.
- Assignee is resolved dynamically (`gh api user` / `glab api user`); never hardcode a
  login.
- All `gh`, `glab`, and `git` commands require `dangerouslyDisableSandbox: true`.
