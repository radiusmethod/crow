---
name: Bug Report
about: Report a bug or unexpected behavior
title: ''
labels: bug
assignees: ''
---

## Environment

- **macOS version:**
- **Hardware:** Apple Silicon / Intel
- **Xcode version:**
- **Zig version:**
- **Crow version/commit:**

## Description

A clear description of the bug.

## Steps to Reproduce

1.
2.
3.

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Logs

Run Crow from the terminal to capture stderr output:

```bash
.build/debug/CrowApp 2>&1 | tee crow-debug.log
```

Paste relevant log lines here (filter with `grep "\[TerminalManager\]\|\[SessionService\]\|\[IssueTracker\]"`).
