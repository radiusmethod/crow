# Troubleshooting

## Build Issues

| Problem                                                  | Solution                                                                 |
| -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `zig` not found                                          | `brew install zig` or download from [ziglang.org](https://ziglang.org/download/) |
| Zig version mismatch                                     | Version **0.15.2** is required. Check with `zig version`                 |
| Metal toolchain not found                                | Run `xcodebuild -downloadComponent MetalToolchain`                       |
| Ghostty submodule missing                                | Run `git submodule update --init vendor/ghostty`                         |
| `swift build` fails with linker errors                   | Build `GhosttyKit` first: `./scripts/build-ghostty.sh` (or just run `make build`) |
| `make build` reports "Prerequisites OK" then fails later | Run `make clean-all && make build` to force a full rebuild of `Frameworks/` |

## Runtime Issues

| Problem                                                  | Solution                                                                 |
| -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `crow` CLI: "Connection refused"                         | The Crow app must be running — the CLI communicates via Unix socket at `~/.local/share/crow/crow.sock` |
| GitHub API errors / empty issue list                     | Check auth: `gh auth status`. Ensure scopes include `repo`, `read:org`, `project`. If missing, run `gh auth refresh -s project,read:org,repo`. |
| `INSUFFICIENT_SCOPES` in `[IssueTracker]` stderr         | Run `gh auth refresh -s project`. **`read:project` is NOT sufficient** — the write `project` scope is required to update ticket status via `updateProjectV2ItemFieldValue`. See `Sources/Crow/App/IssueTracker.swift:691-692,768-769`. |
| Ticket stays "Backlog" when starting a session           | Same as above — the `markInReview` code path requires the write `project` scope |
| Terminal not starting                                    | Check stderr for `[TerminalManager]` or `[Ghostty]` messages             |
| Issue tracker shows no tickets                           | Verify `gh auth status` shows `repo`, `read:org`, `project` scopes       |
| GitLab tickets missing                                   | Run `glab auth status --hostname <your-host>`; ensure `GITLAB_HOST` matches what's in `{devRoot}/.claude/config.json` |
| Sidebar status dot stuck gray                            | Terminal never initialized — click the session tab to trigger `createSurface()` |
| Sidebar status dot stuck yellow                          | Shell is spawning but the probe file never appeared. Check `[TerminalManager]` logs for shell-startup errors |
| Sidebar shows "working" forever after a `※ recap:` line  | The Claude Code session recap (`awaySummaryEnabled`, on by default in v2.1.108+) fires hook events after a turn's `Stop`. Crow now ignores those — if you're on an older build, disable the recap by setting `"awaySummaryEnabled": false` in `~/.claude/settings.json`, toggling "Session recap" off via `/config` inside Claude Code, or exporting `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=0`. |

## Debugging

The app logs diagnostic information to stderr with component tags:

- `[TerminalManager]` — Surface creation, shell readiness transitions
- `[SessionService]` — Orphan detection, session lifecycle changes
- `[IssueTracker]` — GitHub/GitLab API errors, scope issues, project status queries
- `[JSONStore]` — Decode failures (store data loss prevention)
- `[Ghostty]` — Surface creation success/failure
- `[AppSupportDirectory]` — One-time `rm-ai-ide` → `crow` migration events
- `[Scaffolder]` — Template file loading (development builds)
- `[hook-event]` — Claude Code hook event arrivals and `ClaudeState` transitions. Off by default. Set `CROW_HOOK_DEBUG=1` before launching to enable; useful when diagnosing why the sidebar status dot is in the wrong state.

Run with log filtering to focus on a subsystem:

```bash
.build/debug/CrowApp 2>&1 | grep '\[TerminalManager\]\|\[SessionService\]'
```

Filter for scope / auth errors while you're iterating on `gh` permissions:

```bash
.build/debug/CrowApp 2>&1 | grep '\[IssueTracker\]'
```

## Quarantine Warnings on an Unsigned Build

Developers building from source do not need a signing certificate — `make build` and `make release` produce unsigned but fully functional binaries. If macOS quarantines an unsigned `.app`, remove the quarantine attribute:

```bash
xattr -cr Crow.app
```
