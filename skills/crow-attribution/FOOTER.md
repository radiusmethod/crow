# Crow Attribution Footers

Every skill body Crow writes to disk goes through a substitution pass that
replaces `{{CROW_AGENT_DISPLAY_NAME}}` with the session's resolved agent name
(`Claude Code`, `Cursor`, `OpenAI Codex`, …). The agent reads literal text — no
shell parameter expansion is involved, so footers survive every quoting form
(single-quoted heredocs, JSON files, Swift string literals).

**Do not** reintroduce `${CROW_AGENT_DISPLAY_NAME:-…}` or any other shell
expression in attribution footers. Use the literal name Crow already wrote
into your skill, or `{{CROW_AGENT_DISPLAY_NAME}}` if you are authoring a new
template.

The link target is always `https://github.com/radiusmethod/crow` — never a fork or a value from the local git remote.

| Artifact | Footer |
|----------|--------|
| Created (issues, PR descriptions, etc.) | `[🐦‍⬛ Created with Crow via <agent>](https://github.com/radiusmethod/crow)` |
| Reviewed | `[🐦‍⬛ Reviewed by Crow via <agent>](https://github.com/radiusmethod/crow)` |

Replace `<agent>` with the literal name (or `{{CROW_AGENT_DISPLAY_NAME}}` in source templates). Do not change the URL or wrap the line in extra formatting.
