# rm-ai-ide (ride) — Manager Context

This is the development root managed by rm-ai-ide. The Manager tab runs Claude Code here to orchestrate work sessions via the `ride` CLI.

## ride CLI Reference

The `ride` CLI communicates with the rm-ai-ide app via Unix socket at `$TMPDIR/ride.sock`. The app must be running for commands to work. **All `ride` commands require `dangerouslyDisableSandbox: true`** and return JSON.

### Session Commands
```
ride new-session --name "feature-name"          → {"session_id":"<uuid>","name":"..."}
ride rename-session --session <uuid> "new-name" → {"session_id":"...","name":"..."}
ride select-session --session <uuid>            → {"session_id":"..."}
ride list-sessions                              → {"sessions":[...]}
ride get-session --session <uuid>               → {id, name, status, ticket_url, ...}
ride set-status --session <uuid> active|completed|archived
ride delete-session --session <uuid>            → {"deleted":true}
```

### Metadata Commands
```
ride set-ticket --session <uuid> --url "..." [--title "..."] [--number N]
ride add-link --session <uuid> --label "Issue" --url "..." --type ticket|pr|repo|custom
ride list-links --session <uuid>
```

### Worktree Commands
```
ride add-worktree --session <uuid> --repo "name" --repo-path "/main/repo" --path "/worktree/path" --branch "feature/..." [--primary]
ride list-worktrees --session <uuid>
```

### Terminal Commands
```
ride new-terminal --session <uuid> --cwd "/path" [--name "Claude Code"] [--command "claude ..."]
ride list-terminals --session <uuid>
ride send --session <uuid> --terminal <uuid> "text to send"
```

The `ride send` command writes text to the terminal. Newlines in the text are converted to Enter keypresses. To submit a command, include a newline at the end of the text.

## Important Notes

- `--session` always expects a full UUID (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`), not a session name
- Always capture the `session_id` from `new-session` output before using it in subsequent commands
- The Manager session UUID is always `00000000-0000-0000-0000-000000000000` — do not delete it
- Use `/ride-workspace` skill for full workspace setup (worktrees + session + Claude Code)
- **Worktree paths go DIRECTLY under the workspace folder**: `{devRoot}/{workspace}/{repo}-{number}-{slug}` — NOT in a subfolder
- The prompt for new Claude Code sessions must start with `/plan` to enter plan mode

## Sandbox & Network — CRITICAL

### All `ride` and `gh`/`glab` commands MUST use `dangerouslyDisableSandbox: true`

The sandbox blocks:
- Unix socket communication (`ride` commands)
- Network/TLS access (`gh`, `glab`, `curl`)
- Writing to `/tmp` (use `$TMPDIR` instead, which is sandbox-writable)

**ALWAYS use `dangerouslyDisableSandbox: true` for these commands. Do NOT attempt them sandboxed first — they will always fail.**

### GitHub CLI (gh) — TLS Certificate Errors

The `gh` CLI fails with TLS certificate errors in sandbox mode:
```
Post "https://api.github.com/graphql": tls: failed to verify certificate: x509: OSStatus -26276
```

**Fix:** Always use `dangerouslyDisableSandbox: true` for ALL `gh` commands. There is no workaround.

If `gh` still fails or returns empty output:
1. Try with `GIT_SSL_NO_VERIFY=1 gh issue view ...`
2. Use `--repo owner/repo` explicitly instead of relying on git remote detection
3. Use full URL: `gh issue view https://github.com/owner/repo/issues/123` not just the number

### GitLab CLI (glab)

Same TLS issue. Always use `dangerouslyDisableSandbox: true` and set `GITLAB_HOST`:
```bash
GITLAB_HOST=repo1.dso.mil glab issue view {number} --repo {org/repo}
```

## File System Rules

### Temporary Files
- **DO NOT** write to `/tmp` — it's blocked by sandbox
- **USE** `$TMPDIR` for temporary files (e.g., prompt files)
- Example: `cat > $TMPDIR/ride-prompt-feature.md << 'EOF' ... EOF`

### Write-Before-Read Rule
- You must Read a file before you can Write/Edit it (Claude Code requirement)
- If creating a new file, just use Write directly

## Git Worktree Best Practices

### Branch Conflicts
If `git worktree add` fails with "branch already exists":
```bash
git branch -D feature/branch-name          # Delete the conflicting local branch
git worktree add /path -b feature/name --no-track origin/main   # Retry
```

### Worktree Naming
**Correct:** `{devRoot}/{workspace}/{repo}-{number}-{slug}` (same level as main repo)
```
/Users/jane/Dev/RadiusMethod/citadel-197-fix-tab-url-hash
```

**WRONG — never create subdirectories:**
```
WRONG: /Users/jane/Dev/RadiusMethod/citadel-worktrees/197-fix-tab
WRONG: /Users/jane/Dev/RadiusMethod/worktrees/citadel-197-fix-tab
```

### Always use `--no-track` for new branches
Prevents accidental push to main:
```bash
git worktree add /path -b feature/name --no-track origin/main
```

## Claude Binary Path

The CMUX app installs a `claude` wrapper at `/Applications/cmux.app/Contents/Resources/bin/claude` that breaks when called from outside CMUX. Always use the real binary:

```bash
# Find the real claude binary:
which -a claude | grep -v cmux | head -1
# Common location: ~/.local/bin/claude
```

When using `ride new-terminal --command`, the app automatically resolves `claude` to the full path. But for `ride send`, use the full path explicitly.

## Known Issues / Corrections

- Worktree path must be at `{devRoot}/{workspace}/{repo}-{feature}`, NOT in a subdirectory
- Use full claude binary path (find with `which -a claude | grep -v cmux | head -1`), not just `claude`
- All `gh`/`glab` commands fail without `dangerouslyDisableSandbox: true` — never try sandboxed first
- Write temp files to `$TMPDIR`, not `/tmp`
- When `gh issue view` returns empty, add `--repo owner/repo` explicitly
