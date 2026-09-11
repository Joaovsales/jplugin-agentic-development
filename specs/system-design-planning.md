---
implementation_paths:
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/system-design-planning/references/review-card.md
  - .agents/skills/system-design-planning/templates/architecture-spec-template.md
  - .agents/skills/system-design-planning/templates/content-model.json
  - .claude/skills/system-design-planning/**
  - CLAUDE.md
  - README.md
  - .claude/hooks/session-start.sh
  - tests/test-doc-conventions.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-visual-render.sh
  - .agents/skills/build/SKILL.md
---

# Spec: `/system-design-planning` — upstream architecture review

> Origin: user request, 2026-09-11, after Dex Horthy's "Harness Engineering is
> Not Enough" — invest human review in system design, component contracts,
> data models and constraints before an agent builds.

## Behavior

`/system-design-planning` is a supervised entry point that replaces the
`/brainstorm` → `/plan` pair for architecture-shaped changes. It takes an issue
reference or a free-text idea, reads the real codebase, and writes one
architecture spec in a fixed section order: constraints, system design,
component contracts, data models, build order, decisions, acceptance criteria,
implementation paths. It renders that spec to a self-contained HTML document and
stops at a human review gate. After the reviewer replies "approved", it files
one task per build slice through `/task-registry` and appends a `## Plan:` block
of `[ ] TDD:` rows to `tasks/todo.md`, grouped by slice in build order under a
slice header row that is the registry's row for that slice. `/build` consumes
both; the slice header is the one row it reads differently — claimed and closed
with its children, never built on its own.

The skill never edits source, never files before approval, and never talks to a
tracker except through `task-registry.py`.

## Inputs

| Input | Form | Read through |
|-------|------|--------------|
| Issue reference | `#N` or a registry task ID | `task-registry.py show <ref>` |
| Idea or problem statement | free text argument | as given |
| Backlog item | matching `tasks/backlog.md` row | marked `[~]`, description used |
| Codebase | modules, boundaries, entities, tests the change touches | read-only recon; every fact carries `file:line` |
| Prior decisions | `tasks/solutions/` architecture-decision and pattern docs; `tasks/project-context.md` | grep by frontmatter |

## Outputs

| Output | Path | Consumer |
|--------|------|----------|
| Architecture spec, living-contract format | `specs/<feature>.md` | `/build` pre-flight, `/wrap-up-session` reconciliation, `/verify` |
| Rendered review document | `specs/<feature>.plan.html` | the human reviewer; the approval attaches to this file |
| One task per build slice | tracker via `task-registry.py upsert --derive-id design --spec specs/<feature>.md --fold-title` | `/build` claims and reads criteria with `show` |
| TDD plan block | appended to `tasks/todo.md`, one `### Slice n/total` heading per slice, `[ ] TDD:` rows beneath | `/build` Phase 1 |

## Edge Cases

- **Change is below the bar** (one module, no new boundary, no data-model
  change): the skill prints `Skipping system-design-planning: <reason> — use
  /plan` and produces no file.
- **Reviewer replies with findings**: the spec is edited, the self-review and
  render re-run to the same paths, and the paths are reprinted. No filing.
- **Reviewer approves in chat before the render is printed**: not approval; the
  skill renders and asks again.
- **A slice changes a persisted schema or external contract**: `critic` is
  dispatched under the Review Dispatch Contract before rendering; `MUST-FIX` at
  confidence 75 or above is applied to the spec, everything else is recorded in
  *Decisions*.
- **Tracker unreachable or approval required**: `upsert` records locally and
  reports publication pending; the plan block is still written; nothing is
  retried silently.
- **`upsert` has no dependency flag**: slice order is carried in each summary's
  `After:` line and in the plan block order, marked `TODO(shortcut)` in the
  skill with the upgrade path (`--depends-on`, which the index already parses as
  `blocked-by`).
- **Recon did not read a path or symbol**: it is written `NEW` or `UNVERIFIED`
  in the spec and the rendered document, never presented as fact.
- **Renderer limits**: `generate-presentation.py` escapes raw HTML and does not
  render markdown tables, so the content model carries tables and diagrams as
  fenced text blocks.

## Acceptance Criteria

- Both skill trees carry `system-design-planning/SKILL.md` with frontmatter
  `name: system-design-planning`, an `argument-hint`, and
  `disable-model-invocation: false`; the trees are byte-identical.
- The skill body names the four elements and the build order as section
  headings of the spec it writes, in the order constraints, system design,
  component contracts, data models, build order.
- The skill reads issue references only through `task-registry.py show` and
  files only through `task-registry.py upsert` with `--derive-id design`.
- The skill renders through `.agents/skills/visual-recap/scripts/visual-render.py`
  to `specs/<feature>.plan.html` and prints that path before asking for review.
- The skill states that nothing is filed and nothing is built before the
  reviewer's "approved", that approval attaches to the rendered document, and
  that the apply run carries `--approve` so the approval reaches the write gate.
- The skill appends `[ ] TDD:` rows grouped under `### Slice` headings to
  `tasks/todo.md`, writes the plan block before filing, puts `> Spec:` alone on
  its line, and names `/build` as the consumer; `/build` names the slice header
  row it must not build.
- The skill carries an off-ramp line `Skipping system-design-planning:` for
  changes below the bar.
- `templates/content-model.json` renders through `visual-render.py` without
  error and the output contains the seven section ids in order.
- `CLAUDE.md`, `README.md` and `.claude/hooks/session-start.sh` list
  `/system-design-planning`.
- `tests/test-doc-conventions.sh` pins the tokens above in both trees,
  `tests/test-skill-invocation-chain.sh` pins the handoffs to `task-registry`,
  `visual-render.py` and the Step 9 hand-off to `/build`, and
  `tests/test-visual-render.sh` renders the content-model template live.

## Implementation Paths

- `.agents/skills/system-design-planning/SKILL.md` — the process, iron law, gate, filing and handoff
- `.agents/skills/system-design-planning/references/review-card.md` — the 25-question dependency-ordered review card used in self-review and offered to the human reviewer
- `.agents/skills/system-design-planning/templates/architecture-spec-template.md` — the spec skeleton in the fixed section order, living-contract frontmatter
- `.agents/skills/system-design-planning/templates/content-model.json` — the `html-presentation` content model with the same sections for the rendered document
- `.claude/skills/system-design-planning/**` — byte-identical Claude Code copy
- `CLAUDE.md`, `README.md`, `.claude/hooks/session-start.sh` — skill registration
- `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` — static pins for the contract above
- `tests/test-visual-render.sh` — live render of `templates/content-model.json`, section ids in order
