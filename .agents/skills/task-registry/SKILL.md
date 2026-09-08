---
name: task-registry
description: Synchronize the compact tasks/todo.md index with an external tracker (GitHub Issues) or a local Markdown store. Use when linking tasks to issues, reconciling stale plans against tickets, or asking what work is unblocked.
argument-hint: "[reconcile|publish|pull|frontier|show <task-reference>|doctor|selectors|select|claim|workflow <task-reference>]"
disable-model-invocation: false
harness: universal
---

# /task-registry — Provider-Agnostic Task Tracking

`tasks/todo.md` is an **index**, not the source of truth. One row per task: status
box, title, stable ID, provider link, one-line summary, optional dependency
marker. The detail — acceptance criteria, discussion, evidence, history — lives in
the external ticket or the linked spec, and is fetched one task at a time.

That bound is the point. An index that stays small can be loaded at the top of
every session; a `tasks/todo.md` that has absorbed nine closed plan blocks cannot.

## Iron Laws

1. **Dry-run is the default.** Every command previews. `--apply` is the only way
   anything is written, and external writes additionally honour
   `require_write_approval` — which is a floor a repository file may raise and
   never lower.
2. **A title is never an identity.** Matching is by stable ID or by a recorded
   provider reference. Same-title tasks are reported as *advisory*, never merged.
3. **The label vocabulary belongs to the project.** Ordinary sync never creates,
   renames, or removes a label. Every original label survives, `area/*` included.
4. **Never copy a ticket body into the index.** Detail is revealed by
   `show <task-reference>` and nowhere else; provider URLs and shorthand resolve
   through the configured provider without requiring a local row.
5. **Nothing unresolved is deleted.** Stale, superseded, and orphaned entries are
   classified and reported for a human to act on.
6. **Degrade reads, refuse writes.** An unreachable provider still reconciles the
   local half and says so. An external write against it fails loudly, non-zero.

## Commands

All commands take `--repo <path>` (default: cwd) and print a bounded summary.

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py doctor
python3 .agents/skills/task-registry/scripts/task-registry.py reconcile
python3 .agents/skills/task-registry/scripts/task-registry.py reconcile --apply
python3 .agents/skills/task-registry/scripts/task-registry.py publish --apply --approve
python3 .agents/skills/task-registry/scripts/task-registry.py pull --apply
python3 .agents/skills/task-registry/scripts/task-registry.py frontier
python3 .agents/skills/task-registry/scripts/task-registry.py show recipe.morph-live-grid
python3 .agents/skills/task-registry/scripts/task-registry.py upsert <task-id> --apply \
  --title '...' --kind research --spec specs/x.md \
  --summary '...' --evidence 'inspected: ...' --criterion '...'
python3 .agents/skills/task-registry/scripts/task-registry.py upsert --apply \
  --derive-id spec-reconciliation --spec specs/x.md --title '...' --kind research
```

| Command | Reads | Local writes | External writes |
|---------|-------|--------------|-----------------|
| `doctor` | provider | no | no |
| `reconcile` | index + specs + provider | `--apply` only | never |
| `publish` | index + provider | link-back on success | `--apply` (+ approval) |
| `pull` | provider | `--apply` only | never |
| `frontier` | index + provider | no | no |
| `show` | one task | no | no |
| `upsert` | one task | `--apply` only | `--apply` (+ approval) |
| `selectors` | config + provider labels | no | no |
| `select` | provider | no | no |
| `claim` | one task | no | `--apply` (+ approval) |
| `workflow` | one task | no | no |

Exit codes: `0` success · `1` failure or partial failure · `2` usage error.

`workflow` splits the second code differently, because its caller is a scheduler
rather than a person: `2` is reserved for a fault a human must edit a file to
clear — a usage error, a contradictory `[routines]` block, or a selector label
the tracker does not have. Everything else that yields no routine to start —
an unknown reference, a closed issue, a tracker that did not answer — exits `1`.
A nightly wrapper pages on `2` and does not on `1`.

### `workflow` — which routine owns one issue

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py workflow '#42'
```

Answers the question `select` answers in bulk, for one issue a human names:
which routine's selector matches it, which skill chain that routine runs, and
whether anything makes it unrunnable right now. `select_routine` collapses five
distinct situations into a bare `None`; this command gives each its own sentence,
so "nobody owns it" and "somebody already claimed it" stop looking alike.

### `upsert` — record one task, addressed by its ID

`publish` mints provider tasks for rows a human already wrote into the index.
`upsert` is for work a skill *discovers at runtime* — documentation debt, an
unresolved behavioral question — where there is no row yet and no human in the
loop to type one.

It is **idempotent**: given an ID, exactly one task ends up existing with that
content. A second run updates rather than appends, and a run against a task
someone had closed **reopens** it, because the same question recurring is the
same question, not a new one.

That guarantee rests entirely on two runs minting the same ID, so when a task is
*about* a repository path, pass `--derive-id NAMESPACE` with `--spec` instead of
typing one. `is_valid_id` accepts both `ns.feature-c` and `ns.specs-feature-c-md`,
so a caller who normalizes differently creates a second task rather than updating
the first — silently, and only on the second run. Deriving the ID makes that
mismatch unrepresentable. Supplying both an explicit and a derived ID, or
neither, is a usage error rather than a silent default.

Content is passed as structured fields (`--summary`, `--evidence`, `--criterion`,
`--spec`, `--label`) rather than a Markdown body. Each round-trips through the
local provider's metadata block or a managed section, so re-running replaces the
record instead of accreting a second copy beside the first.

Where the canonical body lands follows the project's **existing** write policy
and never widens it: an external provider whose policy already permits unattended
writes gets the task and the index links it; otherwise the local Markdown record
stays canonical and the pending publication is reported. An unpublishable task is
never dropped and never blocks the caller.

## The index row

```markdown
- [ ] Morph live grid recipe <!-- task-id: recipe.morph-live-grid --> — ship the live grid morph ([#42](https://github.com/o/r/issues/42)) (blocked-by: recipe.color-lut)
```

Status boxes: `[ ]` open · `[~]` in progress · `[!]` blocked · `[x]` done ·
`[-]` cancelled. A plain `[ ] do the thing` row from before this capability
existed still parses — it is reported as missing an ID, never rewritten silently.

## Configuration

Provider selection, in order:

1. explicit `provider =` in the project's task-tracking configuration;
2. GitHub, when a GitHub remote **and** an authenticated `gh` both exist;
3. local Markdown.

**No tracker is ever selected implicitly beyond those three rungs** — reachable
credentials are not consent to write to a company tracker. A tracker is added by
declaring `provider =`, never by being detectable.

The configuration document is `docs/task-tracking.md`, or wherever a
`Task tracking instructions: <path>` line in `AGENTS.md`, `CLAUDE.md`, or
`.claude/project.md` points. Copy `templates/task-tracking.md` to start one. A
pointer whose target is missing is refused, naming the path — never defaulted.
Full field reference, provider examples, and troubleshooting:
`references/configuration.md`.

## Task kinds

| Kind | Use for | Typical GitHub label |
|------|---------|----------------------|
| `epic` | a parent grouping several deliverables | — |
| `feature` | new user-facing capability | `enhancement` |
| `bug` | something behaves incorrectly | `bug` |
| `decision` | an open choice blocking work | `design-decision` |
| `research` | a spike whose output is knowledge | `question` (only when configured) |
| `operational` | deployment, smoke, e2e, runbook verification | — |
| `task` | anything else, including the unclassified default | — |

`operational` exists because verification work is real work: it has a status, a
blocker, and evidence, and it disappears when the only vocabulary available is
"feature" and "bug".

## Workflow integration

No workflow skill talks to a tracker about task state. They go through here.

| Skill | Point of contact |
|-------|------------------|
| `/plan` | after the plan is approved, offer to link or create tasks (`publish`) |
| `/build` | claim a task and update status at task boundaries |
| `/verify` | attach evidence links to the task |
| `/quality-gate` | report findings against the task |
| `/wrap-up-session` | `reconcile` before the commit; report drift |

External task creation and status changes require explicit authorization unless
the project configuration turns approval off.

## Progressive disclosure

`reconcile` prints counts, then at most 20 lines per category, then a pointer to
`show`. Rules, and what to do when a summary is still too long:
`references/progressive-disclosure.md`.

## Migrating an existing repository

A repository that predates the registry is converted **once**, by a one-shot
script outside this skill:

```bash
python3 <template-clone>/scripts/migrate-task-registry.py --repo .            # dry run — read the report first
python3 <template-clone>/scripts/migrate-task-registry.py --repo . --apply    # mint ids, write the audit trail
```

It classifies every row as `active`, `stale`, `completed`, or `superseded`; mints
stable IDs for the unresolved ones; groups tightly coupled work so a closed plan
block with nine ticked rows does not become nine issues; and writes an audit trail
to `tasks/task-registry-migration.md`. Dry-run first, always.

It lives in the template repository's `scripts/` rather than here because a
conversion every project runs once should not be carried in the skill forever,
and because `.agents/skills/` is a syncable root that `/sync` overwrites
wholesale. That is also why the path above is written against a template clone:
`/sync` copies skills, not `scripts/`, so the file is not in your project. It
reads no configuration — pass `--index`, `--backlog`, `--spec-dir`, or
`--closed-plan-marker` if this project moved them.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `provider: local` on a GitHub repo | `gh` not authenticated | `gh auth login`, then `doctor` |
| `reads degraded to local-only` | provider unreachable | expected offline; the local half still reconciled |
| `refusing to publish` | unreachable provider + `--apply` | restore connectivity; nothing was written |
| `refusing to ... external writes need approval` | project requires review | re-run with `--approve` after reading the dry run |
| `label 'x' does not exist ... written without it` | mapped label absent upstream | create it in the tracker yourself, or set `allow_label_creation` |
| `missing-id` on every row | pre-registry index | `python3 <template-clone>/scripts/migrate-task-registry.py --repo .`, then the same with `--apply` |

## Notes

- Python 3.8+, standard library only. No tracker SDK.
- GitHub goes through the `gh` CLI, reusing the auth the harness already assumes.
- Credentials are redacted at the boundary — see `references/configuration.md`
  § Credentials.
