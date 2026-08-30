# Project Context

**Repository**: `coding-agent-workflow`
**Purpose**: A reusable, project-agnostic coding agent configuration system — consolidated rules, subagents, skills, hooks, and workflows that enforce spec-driven, TDD-first development.

**Structure**:
- `.agents/skills/` — canonical, harness-neutral skills
- `.claude/agents/` — specialized subagents
- `.claude/skills/` — byte-identical compatibility copies of canonical skills
- `.claude/hooks/` — lifecycle automation
- `.github/upstreams.json` — registered upstream sources and pinned baselines
- `.github/workflows/` — repository automation, including upstream drift checks
- `scripts/` — standard-library and shell maintenance utilities
- `specs/` — feature specifications and acceptance criteria
- `tasks/solutions/` — typed, grep-first learning store
- `tests/` — shell contract and integration tests
- `CLAUDE.md` — root-level Claude Code config

**Conventions**:
- Edit canonical skills under `.agents/skills/` and keep their `.claude/skills/`
  compatibility copies byte-identical.
- Vendored skill directories carry their own upstream license notice; repository-
  level attribution and pinned provenance live in `THIRD_PARTY_NOTICES.md`.
- Recurring checks are silent on success and actionable on failure.
