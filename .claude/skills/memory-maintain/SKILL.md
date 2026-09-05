---
name: memory-maintain
description: Sweep the typed learning store (tasks/solutions/) — resolve needs_review documents, merge duplicates, prune stale or contradicted entries. Invoked at every session start and wrap-up; self-gates on session count.
argument-hint: "[--force]"
harness: universal
---

# /memory-maintain — Learning Store Maintenance

Keep the typed learning store healthy: resolve `needs_review` documents, merge
duplicates, prune stale content, correct contradicted claims. The store schema
and category map live in `tasks/solutions/README.md`.

Invoked at every session start (CLAUDE.md Session Start Checklist) and by
/wrap-up-session Step 1.5. Self-gates on session count so it only does real work
every 5 sessions. Run manually with /memory-maintain --force at any time.

## When to run

This skill runs two passes at different cadences (a Reflector-style split): a
cheap light pass every session, and the heavy consolidation only every 5.

### Light pass — every session (cheap, continuous decay)

Runs on **every** invocation (session start + wrap-up). Bounded work only:
- Count documents and `needs_review` flags (`grep -rlE '^needs_review: true' tasks/solutions/*/`). Anchored to column 0 because the flag is a frontmatter field: scoping to category dirs excludes the store README, but not a document that quotes the flag in its own prose.
- Check `tasks/concepts.md` for a `> Sweep: pending` marker line (cheap grep).
  If present, run **Phase 0** now — the bootstrap sweep fires on the first
  invocation that sees the marker, never waiting for the heavy-pass gate.
- If any document written **this session** duplicates an existing one
  (same `module` + overlapping `tags` **and** >70% semantic overlap — the
  migration's generic `module: general` + `migrated` tag alone never qualify),
  merge into the more specific document and note the merge in its body.

**If `tasks/solutions/` is absent or empty: silent no-op (exit 0, no output) —
but the glossary marker check above runs regardless. A fresh install has an
empty store and a `pending` glossary at the same time; the empty store must
not swallow the one sweep that install exists to trigger.**

### Heavy pass — every 5 sessions (gated)

Count session entries in `tasks/history.md` (lines matching `^### \[\d{4}-\d{2}-\d{2}`):
- Run the full sweep below (Phases 1–4) if the count is a multiple of 5
  (5, 10, 15, …) OR --force flag passed
- If neither condition met: skip the heavy pass (the light pass above still ran)

## Phase 0 — Glossary Bootstrap Sweep (one-time)

Runs only while `tasks/concepts.md` carries a `> Sweep: pending` marker line.
If the marker reads `Sweep: done` or is absent entirely, this phase is a no-op —
never launch a repo-wide sweep on a file that does not ask for one.

1. Sweep the project's own material for vocabulary: README, `specs/`, docs, and
   domain identifiers (model/schema/module names). Admit a term by the same test
   pruning uses: project-specific meaning only — an entity, named process, or
   status term whose meaning is local to this project. Standard industry terms
   never qualify.
2. Write the admitted terms in the glossary's entry format
   (`- **term** — definition.`, alphabetical within section), refining in place
   any term that already exists — never a duplicate bullet.
3. Only after the entries land, flip the marker line to `> Sweep: done YYYY-MM-DD`
   and drop the seed's "(While pending, …)" explanatory note — it describes a
   state the file is no longer in. An interrupted sweep therefore re-runs whole
   on the next invocation, and refine-in-place keeps the re-run idempotent.

A near-empty project yields few or no terms; write what qualifies and flip the
marker anyway — no "nothing found" noise.

## Phase 1 — Resolve `needs_review` Documents

For every document carrying `needs_review: true` (migration output and flagged
/learn writes):
- Fill the missing track-required fields from evidence: read the files named in
  `module`, the PRs cited in the body, and git history. Bug track needs
  `symptoms` / `root_cause` / `resolution`; knowledge track needs `applies_when`.
- Repair migration placeholders the same way: replace `module: general` with the
  real module when evidence names one, replace generic `[migrated, ...]` tags
  with retrieval-worthy ones, and complete a `derive_title`-truncated title
  (fix the `title:` field only — the filename slug stays stable so inbound
  cross-links survive).
- A claim you can verify against the tree gets cited as `file:line`; one you
  cannot is softened and attributed (grounding rule, see /learn).
- When the fields are complete, remove the `needs_review: true` line.
- If the document cannot be grounded at all (source vanished, no evidence),
  move it to `tasks/archive/solutions/` — never delete.

## Phase 2 — Deduplicate

For each pair of documents in the same category with overlapping `module`/`tags`,
check semantic overlap (same problem, same root cause, one a subset of the other).
Merge only if >70% overlap — keep the more specific document, fold in unique
detail, note `[merged from <slug>]` in the body, and delete the emptied sibling's
file only after its content is fully absorbed. Fix any inbound cross-links.
When in doubt, keep separate.

## Phase 3 — Prune Stale and Contradicted Documents

For each document:
- **Stale**: older than 90 days (frontmatter `date`) AND its key terms are
  referenced by no current spec, task, or source file AND it names deleted
  files, removed features, or superseded approaches. All three must hold — never
  prune on age alone. Move stale documents to `tasks/archive/solutions/`.
- **Contradicted**: the tree no longer behaves as the document claims (spot-check
  `file:line` citations). Update the document to the current truth and note the
  correction — never leave a contradicting sibling, never silently drop it.

## Phase 4 — Store Hygiene

- Every document validates against the schema (`tasks/solutions/README.md`):
  required frontmatter, known `problem_type`, category directory matching the
  map, no dates in filenames. Fix violations in place.
- Documents still carrying the migration's `module: general` placeholder — even
  ones no longer (or never) flagged `needs_review` — get the Phase 1 placeholder
  repair when evidence names a real module; otherwise leave them and move on.
- `tasks/history.md` stays a narrative log: any learning prose that leaked into
  it is extracted to a typed document and cross-linked, matching how the
  migration handled `- Pattern:` bullets.
- `tasks/concepts.md` stays a glossary, not a catch-all: prune any entry whose
  term has a standard industry meaning — a common word stays only if its
  definition states the local twist. Keep entries alphabetical in the
  `- **term** — definition.` format.

## Output

```
══════════════════════
  STORE MAINTAINED
══════════════════════
Documents: [N total across M categories]
needs_review: [N resolved, N remaining, N archived as ungroundable]
Duplicates: [N merged]
Stale/contradicted: [N archived, N corrected]
Schema violations fixed: [N]
Glossary: [swept: N terms | N pruned, N kept | no change]
══════════════════════
```
