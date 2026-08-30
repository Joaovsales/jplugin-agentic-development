---
name: task-registry
description: Synchronize the compact tasks/todo.md index with an external tracker (GitHub Issues, Jira) or a local Markdown store. Use when linking tasks to issues, reconciling stale plans against tickets, asking what work is unblocked, or migrating a repository whose todo.md has grown into a detailed backlog.
argument-hint: "[reconcile|publish|pull|frontier|show <task-id>|migrate|doctor]"
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
   `show <task-id>` and nowhere else.
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
python3 .agents/skills/task-registry/scripts/task-registry.py migrate
```

| Command | Reads | Local writes | External writes |
|---------|-------|--------------|-----------------|
| `doctor` | provider | no | no |
| `reconcile` | index + specs + provider | `--apply` only | never |
| `publish` | index + provider | link-back on success | `--apply` (+ approval) |
| `pull` | provider | `--apply` only | never |
| `frontier` | index + provider | no | no |
| `show` | one task | no | no |
| `migrate` | index + backlog + specs | `--apply` only | never |

Exit codes: `0` success · `1` failure or partial failure · `2` usage error.

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

**Jira is never selected implicitly** — reachable credentials are not consent to
write to a company tracker.

The configuration document is `docs/task-tracking.md`, or wherever a
`Task tracking instructions: <path>` line in `AGENTS.md`, `CLAUDE.md`, or
`.claude/project.md` points. Copy `templates/task-tracking.md` to start one.
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

No workflow skill talks to GitHub or Jira about task state. They go through here.

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

`migrate` classifies every row as `active`, `stale`, `completed`, or `superseded`;
mints stable IDs for the first two only; groups tightly coupled work so a closed
plan block with nine ticked rows does not become nine issues; and writes an audit
trail to `tasks/task-registry-migration.md`. Dry-run first, always. Procedure and
worked example: `references/migration.md`.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `provider: local` on a GitHub repo | `gh` not authenticated | `gh auth login`, then `doctor` |
| `reads degraded to local-only` | provider unreachable | expected offline; the local half still reconciled |
| `refusing to publish` | unreachable provider + `--apply` | restore connectivity; nothing was written |
| `refusing to ... external writes need approval` | project requires review | re-run with `--approve` after reading the dry run |
| `label 'x' does not exist ... written without it` | mapped label absent upstream | create it in the tracker yourself, or set `allow_label_creation` |
| `no closing transition available` | Jira workflow has no Done transition | close in Jira, or add the transition |
| `missing-id` on every row | pre-registry index | `migrate`, then `migrate --apply` |

## Notes

- Python 3.8+, standard library only. No GitHub or Jira SDK.
- GitHub goes through the `gh` CLI, reusing the auth the harness already assumes.
- Credentials are redacted at the boundary — see `references/configuration.md`
  § Credentials.
