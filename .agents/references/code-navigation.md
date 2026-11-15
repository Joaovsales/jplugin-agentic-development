# Code navigation

Use the best available capability: LSP when its language-server tools are
present; otherwise a working, fresh graph; otherwise Grep, Glob and Read.
Ordinary search is always available. A file-freshness hint does not certify
that the CLI is healthy.

| Question | Route |
|---|---|
| Exact strings, configuration and non-code files | Grep or Glob, then Read |
| A symbol's definition, references or callers | LSP; otherwise `timeout 20 graphify explain "symbol"` or `timeout 20 graphify path "A" "B"` |
| Blast radius, module boundaries or “what touches this?” | `timeout 20 graphify query "question" --budget 1500` |

Never read `graphify-out/GRAPH_REPORT.md` whole. Keep graph navigation calls
under `timeout 20`. A non-zero exit, timeout, unparsable output or empty result
sends that question directly to Grep. Do not retry the same failed call.

A graph is fresh only when its JSON parses and it is no older than HEAD or
any modified tracked code file. A stale or broken graph gets at most one
`timeout 120 graphify update .` per navigation session. That bounded refresh
is the exception to the navigation deadline; if it fails, stay on Grep for
the session. Scheduled build handover updates are maintenance, not query retries.

Confirm “no callers”, “unused” and “nothing touches this” with Grep on the
symbol name before acting. A missing edge is not evidence of absence.

An agent never installs or upgrades graphify or a language server. Report the
session banner's command for a person instead. Missing tools or an unreadable
reference always leave Grep, Glob and Read available.

Resolve this reference from the project first. In a Claude plugin workspace
without the project copy, use
`${CLAUDE_PLUGIN_ROOT}/.agents/references/code-navigation.md`, or the package
path supplied by the hint. If neither is readable, continue with Grep.

| Harness | Hint coverage |
|---|---|
| Claude Code | Plugin PreToolUse hook for Grep and Glob |
| Codex | Text-only unless a positive PreToolUse + tool-matcher probe enables the adapter |
| Pi and Cursor | Text-only |

The adoption evaluation measures Claude Code only; it does not establish a
verdict for Codex, Pi or Cursor.

## Source notes

The pin in `.agents/graphify.pin` names the PyPI `graphifyy` release from
`github.com/Graphify-Labs/graphify`. Its `query --budget`, `explain`, `path`,
`update .` and `--version` forms were checked on 2026-11-15. Stock Claude
wiring includes `hook-guard read/search`; the person-run installer strips those
hooks and legacy whole-report hooks. Never restore them through a skill.
