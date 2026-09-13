# 0025 — Auto-download the corveil CLI from corveil-releases

- **Status:** Accepted
- **Date:** 2026-09-10 (amended 2026-09-12, CROW-1247)
- **Deciders:** @dhilgaertner

## Context

The `corveil` CLI was a manually managed artifact: an operator cloned
`corveil/corveil`, built `out/corveil-<os>-<arch>`, and pointed Crow at it via
`defaults.binaries["corveil"]`. Crow only (re)created the `.claude/bin/corveil`
symlink to whatever path was configured. Linked binaries drifted silently —
months and dozens of releases behind — and a daemon restart did not self-heal.

Prebuilt binaries already ship from the public [`corveil/corveil-releases`](https://github.com/corveil/corveil-releases)
repo (`checksums.txt` plus darwin/linux amd64/arm64). No private-repo auth and
no source-build step are required. The mirror can trail source tags by about a
day; that is acceptable for "roughly current," not a Crow-side problem.

Crow already had a periodic GitHub check (`crow version` / CROW-938), a
post-download verify (`crow corveil verify`), skill reinstall, and an
Application Support directory.

CROW-1210 shipped the downloader **off** so source-build workflows were not
surprised. CROW-1229 flipped the default **on**, but only for a *missing* key:
an explicit `false` in `config.json` stayed off, and `shouldAutoManage` skipped
any `binaries["corveil"]` outside the managed dir. Existing boxes — almost all
of them pointing at `…/corveil/out/corveil-<os>-<arch>` — kept drifting. There
was no boot-time migration.

## Decision

1. **Config, default on.** `defaults.corveilAutoUpdate` (bool, default **on**; a
   missing key decodes as on) and `defaults.corveilVersion` (`"latest"` or a
   `vX.Y.Z` pin). Exposed via `crow defaults get/set` and Settings → General.
   An explicit `false` after the leftover one-shot (below) stays off.
2. **Crow owns the path when auto-update is on.** Auto-manage runs whenever
   `corveilAutoUpdate` is on. A previous source-build path is adopted: Crow
   downloads, verifies, writes under
   `~/Library/Application Support/crow/bin/corveil/<tag>/`, points
   `binaries["corveil"]` at that file, and hot-swaps `.claude/bin/corveil`. The
   old `out/` binary is not deleted. Source-build wins **only while auto-update
   is off** (`crow defaults set --corveil-auto-update false` or the Settings
   toggle).
3. **One-shot leftover default-off (CROW-1247).** Config with
   `corveilAutoUpdate: false`, a non-managed `binaries["corveil"]`, and no
   `corveilAutoUpdateOptOut` sentinel is treated as "never opted in" (the #1228
   default-off leftover), not "opted out." Crow flips auto-update on, adopts,
   and writes the sentinel. After that, an explicit false is a real opt-out and
   is not flipped again. The sentinel is also written when the operator sets
   auto-update off (CLI or a true→false Settings save). A leftover false saved
   unchanged does not stamp it.
4. **Download, verify, link.** Resolve host `os/arch`, fetch the matching
   asset from `corveil/corveil-releases` over HTTPS (unauthenticated), verify
   SHA-256 against `checksums.txt`, run `corveil --version`, store under a
   versioned managed dir, atomically repoint `.claude/bin/corveil`, reinstall
   skills, and keep one previous version for rollback. Darwin downloads get
   `com.apple.quarantine` stripped. Failures log a warning and keep last-good
   (the previous path or last managed tag); startup never fails.
5. **Cadence.** Check at daemon start and on the existing
   `versionUpdate.intervalHours` loop. Enabling via `crow defaults set` kicks a
   check immediately. The symlink is hot-swapped; no `crowd` restart is required
   for a successful auto-update.

## Consequences

Fresh Crow installs get a `corveil` CLI without pointing `binaries["corveil"]`
at a build. Existing source-build installs are adopted onto the managed
downloader on the next check, using the same Auto-download toggle as the
control — not a second flag. Operators who want to keep an `out/` path pass
`--corveil-auto-update false`. The `-releases` lag vs source tags remains a
publish-cadence issue, not Crow's. Quarantine stripping is a pragmatic
workaround until `-releases` artifacts are notarized.

## Alternatives considered

- **Default off (CROW-1210).** Shipped first so existing source-build workflows
  were unchanged until an operator opted in. Reconsidered once the download
  path was proven; CROW-1229 made on the default. CROW-1247 then adopted the
  leftover source-build boxes that CROW-1229 could not flip.
- **Keep "operator path always wins."** That is what left this machine on
  `v0.4.39-13-ge07be53f`. The Auto-download setting is the control; a source
  build is an opt-out, not a silent skip while the toggle is on.
- **Build from `corveil/corveil` source.** Needs a Go toolchain and private-repo
  auth; binaries already exist.
- **Require a daemon restart after swap.** Unnecessary: the PATH prepend
  resolves the symlink, and skills are reinstalled in place.

## References

- Ticket: https://github.com/corveil/crow/issues/1210
- Follow-up (default on): https://github.com/corveil/crow/issues/1229
- Follow-up (adopt existing installs): https://github.com/corveil/crow/issues/1247
- Related ADRs: [0012](./0012-tests-never-touch-live-data.md) (tests inject a
  temp managed root), [0016](./0016-cli-control-plane-parity.md)
- Code: `Packages/CrowEngine/Sources/CrowEngine/CorveilAutoUpdate.swift`,
  `Packages/CrowDaemon/Sources/CrowDaemon/CorveilAutoUpdateService.swift`
