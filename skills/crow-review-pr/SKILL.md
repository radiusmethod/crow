# Crow Review PR Skill

## Purpose

Performs thorough code reviews on GitHub pull requests. Reads the PR diff, understands the codebase context, provides a detailed review, and posts comments back to GitHub — all with user approval before submission.

## Important: Sandbox Bypass

All `gh` commands require `dangerouslyDisableSandbox: true` because they need network/TLS access.

## Activation

This skill activates when:
- User invokes `/crow-review-pr` command
- User asks to "review a PR" or "review this pull request"
- This is a review session (the session was created via the Reviews board)

## Workflow

### Step 1: Identify the PR

Get the PR URL from the session's links:

```bash
crow list-links --session {session_uuid}
```

Look for a link with type `pr`. Extract the URL.

If no PR link is found, ask the user for the PR URL.

### Step 2: Fetch PR Details

```bash
gh pr view {pr_url} --json title,body,baseRefName,headRefName,files,additions,deletions,commits,author,labels,reviewRequests
```

This gives you:
- **title** and **body**: The PR description and context
- **baseRefName** / **headRefName**: The target and source branches
- **files**: List of changed files with additions/deletions
- **commits**: Commit messages for understanding the work
- **author**: Who created the PR

### Step 3: Read the Diff

```bash
gh pr diff {pr_url}
```

This returns the full unified diff of all changes. For large PRs, you may want to also read specific files:

```bash
gh pr diff {pr_url} -- {specific_file_path}
```

### Step 4: Understand Context

1. Read `CLAUDE.md` and `README.md` in the repo root for project conventions
2. For each changed file, read the full file (not just the diff) to understand surrounding context
3. Check if tests were added or updated for the changes
4. Look at the commit history on the branch:
   ```bash
   git log --oneline origin/{baseRefName}..HEAD
   ```

### Step 5: Analyze the Changes

Review the PR for:

1. **Correctness**: Does the code do what the PR description claims? Are there logic errors, off-by-one mistakes, or missing edge cases?

2. **Security**: Any injection vulnerabilities (SQL, XSS, command injection)? Improper input validation? Hardcoded secrets? Insecure defaults?

3. **Performance**: Unnecessary allocations? N+1 queries? Missing indexes? Blocking operations in hot paths?

4. **Code Quality**: Does it follow the project's conventions? Is it readable? Are abstractions appropriate? Any code duplication?

5. **Testing**: Are there adequate tests? Do they cover edge cases? Are they testing the right things (behavior, not implementation)?

6. **Architecture**: Does the change fit the existing architecture? Any accidental coupling? Is the abstraction level right?

### Step 6: Present the Review

Format your review as:

```
## PR Review: {title}

### Summary
{1-2 sentence overview of what the PR does and your overall assessment}

### Verdict: {APPROVE | REQUEST_CHANGES | COMMENT}

### Issues Found
{Numbered list of issues, each with:}
- Severity: critical / major / minor / nit
- File: {path}:{line}
- Description: what's wrong and why
- Suggestion: how to fix it

### Positive Notes
{Things done well — acknowledge good patterns, thorough tests, clean abstractions}
```

**IMPORTANT**: Always present the review to the user for approval BEFORE submitting. Say:

> Here is my review. Would you like me to:
> 1. Submit as-is
> 2. Modify the review
> 3. Cancel without submitting

### Step 7: Submit the Review

Only after the user approves:

#### For a simple review comment (no inline comments):

```bash
gh pr review {pr_url} --comment --body "review text here"
```

Or to approve:
```bash
gh pr review {pr_url} --approve --body "review text here"
```

Or to request changes:
```bash
gh pr review {pr_url} --request-changes --body "review text here"
```

#### For inline comments on specific lines:

Use the GitHub API to create a review with inline comments:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST \
  -f body="Overall review summary" \
  -f event="COMMENT" \
  -f 'comments[][path]=src/example.swift' \
  -f 'comments[][line]=42' \
  -f 'comments[][body]=Specific comment about this line'
```

Note: The `line` field refers to the line number in the **new version** of the file (right side of the diff). Use `side=RIGHT` (default) for comments on added/modified lines.

For comments on deleted lines, use `side=LEFT` with the old line number.

## Important Constraints

- **Never auto-submit**: Always wait for user approval before posting any review
- **Never auto-approve**: Even if the code looks good, present the review first
- **Be constructive**: Frame feedback as suggestions, not demands. Explain the "why"
- **Acknowledge good work**: Don't only point out problems
- **Respect conventions**: If the project has a style guide or CLAUDE.md conventions, follow them in your review
- **Be specific**: Reference exact files, line numbers, and code snippets
- **All `gh` and `crow` commands require `dangerouslyDisableSandbox: true`**

## Error Handling

| Error | Response |
|-------|----------|
| PR URL not found | Ask user for the PR URL |
| `gh` auth error | Suggest: `gh auth refresh` |
| Large diff (>5000 lines) | Focus on the most critical files; note that you reviewed a subset |
| Rate limit | Wait and retry, inform user |

## Examples

### Basic Review
```
/crow-review-pr
```
→ Reads PR from session links, fetches diff, analyzes, presents review for approval

### Review with Specific Focus
```
/crow-review-pr — focus on security implications
```
→ Same flow but with security-focused analysis

### Review a Specific PR
```
/crow-review-pr https://github.com/org/repo/pull/123
```
→ Reviews the specified PR regardless of session links
