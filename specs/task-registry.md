---
implementation_paths:
  - .agents/skills/task-registry/**
  - .claude/skills/task-registry/**
  - tests/test-task-registry.sh
  - tests/fixtures/task-registry/**
  - docs/task-tracking.md
---

# Spec: Provider-Agnostic Task Registry

> Status: implemented on `feat/task-registry-provider-adapters`.
> Inspiration: Matt Pocock's Wayfinder (compact map, child tickets, dependency-aware
> frontier, progressive disclosure, tracker configured through project instructions,
> local Markdown fallback). Vocabulary and scope are deliberately **not** copied:
> Wayfinder models decision tickets, this harness must also track implementation,
> bugs, research, and operational verification.

## Problem

`local_project` converged on a working pattern: a compact, issue-linked
`tasks/todo.md`; detail in GitHub Issues; specs under `specs/`; operational
verification tracked as issues; stale plans reconciled separately. The pattern is
currently hand-run and GitHub-shaped. Every other repository using this harness
re-derives it, and no skill can rely on it existing.

Two failure modes this generalizes away:

1. **`tasks/todo.md` as the detailed source of truth.** It grows without bound,
   every agent loads all of it every session, and completed plan blocks are never
   reconciled — this repository's own `tasks/todo.md` is 200+ lines of closed plans.
2. **Provider coupling.** A workflow skill that shells out to `gh` cannot run on
   another tracker or offline, and each skill that does so re-implements identity,
   label, and status handling slightly differently.

## Behavior

Three layers, each usable without the one above it.

### Layer 1 — provider-neutral domain model

A normalized `Task` record (frozen dataclass) with a **stable task ID** that is not
a provider issue number. Canonical kinds: `epic`, `feature`, `bug`, `decision`,
`research`, `operational`, `task`. Canonical statuses: `open`, `in_progress`,
`blocked`, `done`, `cancelled`. Canonical priorities: `high`, `medium`, `low`, unset.

Identity lives in two places and nowhere else:

- local: an HTML comment on the index row — `<!-- task-id: recipe.morph-live-grid -->`
- external: a delimited metadata block in the task body

Tasks without IDs keep working: they parse, they appear in `reconcile` output as
`id: (none)`, and only the one-shot `scripts/migrate-task-registry.py --apply` writes
IDs — idempotently.

### Layer 2 — provider adapters

A narrow `TrackerProvider` interface (discover, list, get, create, update, close,
comment, link_parent, add_dependency, resolve_reference) plus an explicit
`Capabilities` record (native_hierarchy, native_dependencies, comments, labels,
offline, atomic_updates). Two adapters ship: `github` (via the `gh` CLI) and
`local` (Markdown files). A `jira` adapter shipped originally and was retired in
Cut 1 of `specs/workflow-routing.md`: it was never run against a real Jira, so it
was speculative surface rather than a supported provider. The interface it was
written against is unchanged, which is the point — a third adapter is an addition,
not a rewrite.

Where a provider lacks a capability, the registry **degrades visibly**: a dependency
a provider cannot express natively is stored in the metadata block and reported as
`inferred`, never as `native`.

### Layer 3 — progressive-disclosure synchronization

A CLI, `task-registry`, exposed through the `/task-registry` skill:

| Command | Effect | External writes |
|---------|--------|-----------------|
| `reconcile` | Compare local index, specs, backlog against the provider | none (default dry-run) |
| `publish --apply` | Create/update external tasks for local rows that lack them | yes, gated |
| `pull` | Refresh local rows from external state | none (local only) |
| `frontier` | Dependency-aware ready/blocked list | none |
| `show <task-id>` | Full detail for exactly one task | none |
| `upsert` | Create-or-update exactly one task, addressed by a stable ID (derivable from a path with `--derive-id`) | yes, gated |
| `selectors` | Report the routine selector vocabulary and check it against the tracker | none |
| `select --routine R` | The next issue routine `R` may claim, after asserting the vocabulary, the claim label, and the linked-PR capability all exist | none |
| `claim <ref> --routine R` | Write the claim label onto one issue — the routine spine's only write | yes, gated |

Summary first, always. Detail only via `show`. Full external bodies are **never**
copied into `tasks/todo.md`.

## Inputs

- `docs/task-tracking.md` — the project configuration contract (an ```ini fenced
  block parsed with `configparser`). Discovered directly, or through a
  `Task tracking instructions: <path>` pointer in `AGENTS.md`, `CLAUDE.md`, or
  `.claude/project.md`. A pointer whose target is missing is refused, naming
  the declaring file and the path (#82) — only "no pointer, no default file"
  is silent.
- `tasks/todo.md` — the compact local index.
- `tasks/backlog.md`, `specs/`, `specs/pending/`, `specs/completed/` — reconciled inputs.
- `gh` CLI for the GitHub provider.

## Outputs

- Stdout: a bounded summary (counts + one line per divergence), or a single task's
  detail under `show`.
- `tasks/todo.md`: rewritten only in the regions the registry owns, and only under
  `--apply`.
- Local provider: `<local_detail_dir>/<task-id>.md` canonical task files.
- External provider: issues created/updated only under `--apply`.
- `tasks/task-registry-migration.md`: the migration audit trail.
- Exit codes: `0` success, `1` failure or partial failure, `2` usage error.

## Edge Cases

- **No configuration, no `gh`, no remote** → local provider, exit 0.
- **Configured `github`, `gh` missing or unauthenticated** → reads degrade (local
  index still reconciles, provider reported unreachable); `publish --apply` fails
  loudly, non-zero, naming the reason.
- **Two tasks with the same title** → not a duplicate. Duplicate detection requires
  matching stable ID or matching external reference.
- **External task edited by a human** → `pull` updates only the registry-owned
  metadata block and the local row; body, comments, labels, and hierarchy survive.
- **Row without an ID** → parsed, reported, never silently rewritten.
- **Legacy multi-line row** → an indented continuation belongs to the preceding
  task. For ``TDD: `name` -> detail``, the quoted name becomes the provider title
  and the complete implementation clause becomes its body; migration preserves
  the physical continuation until the logical row is deliberately rewritten.
- **Malformed or unsafe-to-publish row** (unbalanced comment, empty title,
  unknown status char, ambiguous `->` split, or a logical row over 60,000
  characters) → reported on stderr with the file:line, counted in the exit
  summary, never truncated or dropped; publication refuses the entire local
  batch before reading from or writing to the provider.
- **A GitHub label the mapping does not know** → preserved verbatim, and the task
  still gets a kind (`task` by default).
- **`in_progress` / `blocked`** → never inferred from GitHub's open/closed state.
  Only an explicitly configured source produces them.
- **Partial failure during `publish --apply`** (3 of 5 issues created) → the 3 links
  are written locally, the 2 failures are named, exit code 1.
- **Credentials in an error path** → redacted before any output or log line.

## Acceptance Criteria

- AC-1 — `Task` model validates canonical kinds/statuses/priorities and rejects
      unknown values with a named error.
- AC-2 — Stable IDs live in an HTML comment locally and a metadata block
      externally; no provider issue number is used as identity.
- AC-3 — Provider selection: explicit config wins; else GitHub when a GitHub
      remote and authenticated `gh` both exist; else local. No tracker is implicit.
- AC-4 — GitHub adapter maps `bug`→`bug`, `enhancement`→`feature`,
      `design-decision`→`decision`, `question`→ only when configured, `now`→`high`,
      `next`→`medium`, no queue label → unset priority.
- AC-5 — Every original label, including every `area/*`, survives a round trip.
- AC-6 — Ordinary sync never creates a label. `allow_label_creation = true`
      is the only switch that permits it, and creation still passes the write gate
      like any other external write.
- AC-7 — GitHub open/closed maps to `open`/`done`; `in_progress`/`blocked` only
      from configured project fields, native state, assignee, or configured labels.
- AC-8 — Capabilities are declared per provider, and a dependency stored in
      metadata is reported `inferred`, never `native`.
- AC-9 — External writes require `--apply`; default is dry-run for every command.
- AC-10 — The `Authorization` header and any `Bearer`/`Basic` payload,
      `api_token`/`password`/`secret` assignment, or `user:pass@` URL userinfo are
      redacted in all output, including tracebacks and verbose mode. Redaction is
      by pattern and does not depend on a credential being registered — since
      Cut 1 no shipped provider keeps one in the configuration.
- AC-11 — Local provider works fully offline: create, update, close, comment,
      parent, dependency.
- AC-12 — `reconcile` is idempotent: a second run reports no changes and writes
      nothing new.
- AC-13 — Duplicate detection never uses title equality alone.
- AC-14 — `tasks/todo.md` rows carry only checkbox, title, ID, link, one-line
      summary, optional dependency marker; no acceptance criteria, no issue body.
- AC-15 — Legacy checkbox-only rows keep parsing; indented continuation detail
      remains part of the same logical row, and the migration is dry-run first,
      preserves that detail, and leaves an audit trail. Since Cut 1 of
      `specs/workflow-routing.md` the migration is the one-shot `scripts/migrate-task-registry.py`
      rather than a subcommand; the behaviour above is unchanged and is still
      pinned by `tests/test-task-registry.sh` § 10.
- AC-16 — Migration groups tightly coupled work and does not emit one external
      issue per historical `[x]` checkbox.
- AC-17 — Unresolved work is never deleted; stale/superseded entries are
      classified and reported, not removed.
- AC-18 — `frontier` orders by dependency and names the blocker for each blocked
      task.
- AC-19 — Malformed or unsafe-to-publish input is reported with file:line and a
      non-zero exit before any provider write, never swallowed or truncated.
- AC-20 — Workflow skills (`/plan`, `/build`, `/verify`, `/quality-gate`,
      `/wrap-up-session`) reach tracking only through this capability — no direct
      `gh` or tracker-API calls for task state.

## Implementation Paths

- `.agents/skills/task-registry/SKILL.md` — the skill (canonical), parity-copied.
- `.agents/skills/task-registry/scripts/task-registry.py` — CLI entrypoint.
- `.agents/skills/task-registry/scripts/registry/` — model, config, index,
  reconcile, upsert, providers.
- `scripts/migrate-task-registry.py` — one-shot migration for a pre-registry
  repository, outside the skill because `/sync` overwrites skills wholesale.
- `.agents/skills/task-registry/references/` — configuration and
  progressive-disclosure guides.
- `.agents/skills/task-registry/templates/task-tracking.md` — the config template.
- `tests/test-task-registry.sh`, `tests/fixtures/task-registry/` — contract tests.
- `CLAUDE.md`, `README.md`, `.claude/hooks/session-start.sh` — registration.
