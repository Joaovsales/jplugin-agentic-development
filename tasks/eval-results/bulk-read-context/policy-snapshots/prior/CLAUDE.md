# Registry maintenance

This repository contains a provider-neutral task registry extracted from our workflow tooling. Source lives in registry/. Use Python's standard library; no new dependencies. Fix shared behavior centrally and preserve provider-owned state and unmanaged text. Work locally, with no network calls, commits, or pushes. The user has approved implementation of the requested correction.

### Bulk-Read Handoff

Routing decides which model a *dispatched* agent runs on. Nothing above decides
what the main thread or a builder does when it opens a 2,000-line file: it reads
the whole file into the most expensive context in the session. So the Scout tier
also owns **bulk reads**, and the rule is enforced mechanically rather than by
prose.

A pre-tool gate denies any single read that would put more than
`BULK_READ_MIN_LINES` lines (default **350**) of one file into the calling
model's context — a whole-file `Read`, a ranged `Read` whose `limit` is that
large, or a shell command whose final pipe stage prints the file — every `;`, `&&` or
newline-separated list is checked, and stdout redirected to a file is not a read — (`cat`,
`type`, `Get-Content` without `-TotalCount` or `-Tail`, `head -n N`,
`sed -n 'A,Bp'`). The deny names the file, its line count, the threshold, and
the two allowed alternatives:

1. **Dispatch `bulk-reader` with a question.** It answers in structured
   bullets, quoting `file:line` anchors on request. Its summaries are not edit
   anchors, it never proposes edits, and it never reasons about architecture
   or correctness. A builder receives a bulk-reader answer as context, never a
   file over the threshold.
2. **Read only the range an edit needs** — `offset`/`limit` under the
   threshold, or `sed -n 'A,Bp'` with the same bound.

The gate never rewrites a call; the model chooses the alternative. It fires
inside sub-agents too, so `bulk-reader`, `Explore`, and every other persona
chunk their reads. `BULK_READ_GATE=off` disables it for one session.

| Harness | Enforcement surface | Scout model |
|---------|---------------------|-------------|
| Claude Code | `PreToolUse` hook on `Read`, `Bash`, `PowerShell` — `.claude/hooks/bulk-read-gate.py`, registered project-level in `.claude/settings.json` (never user-level, or it fires twice) | `haiku`, pinned in `.claude/agents/bulk-reader.md` |
| Codex | the same script, installed by `scripts/install-codex.sh` and registered once under `PreToolUse` in `~/.codex/hooks.json` | Scout-tier `model` in the rendered TOML; the ID lives in `PI_SETUP.md` § Sub-Agent Routing, Codex column |
| Pi | `pi/extensions/bulk-read-gate.ts` on `tool_call` (`read`, `bash`), returning `{ block, reason }` | `subagents.agentOverrides` — `PI_SETUP.md` § Sub-Agent Routing |

Workspace scope: source exploration must stay inside this checkout. Do not inspect parent directories, sibling projects, global agent files, session logs, or files outside this checkout. If local coverage is absent, create it here.
