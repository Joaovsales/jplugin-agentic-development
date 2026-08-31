# Backlog

Ordered work items. Judgment-call proposals from automated hygiene runs land here rather
than being auto-applied.

- [ ] `/tidy` (2026-08-31): `CLAUDE.md`'s skill table (§ Skills) lists `` `/graphify` `` as if it
      were a repo skill, but no such skill exists under `.agents/skills/` or `.claude/skills/` —
      `graphify` is an external `pip`-installed CLI tool documented separately in README.md
      § "Optional — graphify code graph". Decide whether to remove the row, or reformat it to
      make clear it is an external tool rather than a `/`-invocable skill.
