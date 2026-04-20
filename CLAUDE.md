<!-- This file is both repo documentation and Manager tab context.
     Crow scaffolds it into {devRoot}/.claude/CLAUDE.md on launch (see Scaffolder.swift). -->

# Crow — Manager Context

This is the development root managed by Crow. The Manager tab runs Claude Code here to orchestrate work sessions via the `crow` CLI.

## crow CLI Reference

The `crow` CLI communicates with the Crow app via Unix socket at `~/.local/share/crow/crow.sock`. The app must be running for commands to work. **All `crow`, `gh`, `glab`, and `git worktree` commands require `dangerouslyDisableSandbox: true`** and return JSON.

### Session Commands
```
crow new-session --name "feature-name"          → {"session_id":"<uuid>","name":"..."}
crow rename-session --session <uuid> "new-name" → {"session_id":"...","name":"..."}
crow select-session --session <uuid>            → {"session_id":"..."}
crow list-sessions                              → {"sessions":[...]}
crow get-session --session <uuid>               → {id, name, status, ticket_url, ...}
crow set-status --session <uuid> active|paused|inReview|completed|archived
crow delete-session --session <uuid>            → {"deleted":true}
```

### Metadata Commands
```
crow set-ticket --session <uuid> --url "..." [--title "..."] [--number N]
crow add-link --session <uuid> --label "Issue" --url "..." --type ticket|pr|repo|custom
crow list-links --session <uuid>
```

### Worktree Commands
```
crow add-worktree --session <uuid> --repo "name" --repo-path "/main/repo" --path "/worktree/path" --branch "feature/..." [--primary]
crow list-worktrees --session <uuid>
```

### Terminal Commands
```
crow new-terminal --session <uuid> --cwd "/path" [--name "Claude Code"] [--command "claude ..."] [--managed]
crow list-terminals --session <uuid>
crow close-terminal --session <uuid> --terminal <uuid>
crow send --session <uuid> --terminal <uuid> "text to send"
```

The `crow send` command writes text to the terminal. Newlines in the text are converted to Enter keypresses. To submit a command, include a newline at the end of the text.

## Important Notes

- `--session` always expects a full UUID (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`), not a session name
- Always capture the `session_id` from `new-session` output before using it in subsequent commands
- The Manager session UUID is always `00000000-0000-0000-0000-000000000000` — do not delete it
- Use `/crow-workspace` skill for full workspace setup (worktrees + session + Claude Code)
- **Worktree paths go DIRECTLY under the workspace folder**: `{devRoot}/{workspace}/{repo}-{number}-{slug}` — NOT in a subfolder
- The prompt for new Claude Code sessions must start with `/plan` to enter plan mode
- Use `$TMPDIR` (not `/tmp`) for temporary files

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
/Users/jane/Dev/RadiusMethod/acme-api-197-fix-tab-url-hash
```

**WRONG — never create subdirectories:**
```
WRONG: /Users/jane/Dev/RadiusMethod/acme-api-worktrees/197-fix-tab
WRONG: /Users/jane/Dev/RadiusMethod/worktrees/acme-api-197-fix-tab
```

### Always use `--no-track` for new branches
Prevents accidental push to main:
```bash
git worktree add /path -b feature/name --no-track origin/main
```

## Concurrency Safety

The crow CLI is safe for concurrent use. Multiple `crow` commands can run simultaneously without race conditions:

- **Socket Server**: Each CLI connection is dispatched to GCD's global concurrent queue. Multiple connections are accepted and processed in parallel.
- **State Mutations**: All RPC handlers use `await MainActor.run { ... }`, serializing all AppState mutations on the main thread. This prevents data races even when multiple CLI commands arrive simultaneously.
- **Persistence**: JSONStore uses NSLock to serialize disk writes. Concurrent `mutate()` calls are safe.
- **Git Operations**: Each `setup.sh` creates its own worktree at a unique path, its own session (unique UUID), and its own terminal. There are no shared resources between parallel workspace setups.

Use `/crow-batch-workspace` to set up multiple workspaces in parallel.

## Known Issues / Corrections

<!-- Auto-maintained by Claude Code during workspace setup -->
