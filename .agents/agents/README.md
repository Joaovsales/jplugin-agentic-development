# Workflow Agents (canonical, harness-neutral)

These are the canonical definitions of the workflow's sub-agent personas.
Same format as Claude Code agents: YAML frontmatter (`name`, `description`)
plus a system-prompt body.

## How each harness consumes them

| Harness | Location | Model routing |
|---------|----------|---------------|
| **Claude Code** | `.claude/agents/` (backwards-compat copy, may pin `model: sonnet` etc.) | Explicit `model` on each Agent tool call, per the `/build` Model Routing table |
| **Pi** | `.agents/agents/` (this dir) — auto-discovered by the [`pi-subagents`](https://github.com/nicobailon/pi-subagents) extension via its legacy `.agents/**/*.md` project discovery | `subagents.agentOverrides` in `~/.pi/agent/settings.json` — do **not** pin `model:` here |

## Rules

1. **Never put `model:` in these canonical files.** Model assignment is a
   per-harness, per-user concern (see `PI_SETUP.md`). The `.claude/agents/`
   copies may pin Claude built-in aliases for Claude Code users.
2. Edits to a persona (system prompt, description) go here first, then get
   copied to `.claude/agents/`. Skills need no copy: Claude Code loads
   `.agents/skills/` through the `jplugin` plugin.
3. `pi-subagents` explicitly skips `.agents/skills/**` during agent
   discovery, so skills and agents can coexist under `.agents/`.
4. Extension builtin agents fill roles this directory does **not** define
   (`scout`, `oracle`, `researcher`, `context-builder`). Overlapping builtins
   (`worker`, `reviewer`, `delegate`, `advisor`) should be disabled in Pi
   settings to keep the fleet unambiguous — see `PI_SETUP.md`.
5. **Keep `description:` a colon-free single line, and make `name:` match the
   filename.** Frontmatter values here are unquoted YAML plain scalars, which
   may not contain `": "` or end in `:` — a violation is a *parse error*, and a
   persona whose frontmatter fails to parse is dropped from the registry
   silently: the file still exists, the name still looks right, and dispatch
   fails with "agent type not found". `name:` is what the harness registers, so
   a value that drifts from the filename fails the same way while parsing
   cleanly. Both are enforced by `tests/test-agents.sh` § 4. If a description
   genuinely needs punctuation, quote the whole value — but prefer rewording,
   because a half-applied quote is its own parse error.
