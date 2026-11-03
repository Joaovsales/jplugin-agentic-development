# Typed Learning Store

> Replaces the retired monolithic store (the old memory, lessons, and bug-register
> files under `tasks/`). Written by `/learn` and `/debug`; swept by
> `/memory-maintain`; converted from the old store by the template repo's
> `scripts/migrate-learning-store.py`.

One document per learning:

```
tasks/solutions/<category>/<slug>.md
```

Filenames are stable ASCII kebab-case slugs derived from the title. **The date
lives in frontmatter, never in the filename** — slugs must not change, so
cross-links do not rot.

Retrieval is grep-first on frontmatter: a session greps `problem_type`, `module`,
and `tags` to load only the documents relevant to what it is doing. Never bulk-load
the whole store into context.

## Frontmatter schema

Every document opens with a YAML frontmatter block. Flat keys only; `tags` is an
inline list.

```yaml
---
title: Short imperative statement of the learning
date: YYYY-MM-DD
problem_type: <enum below>
module: area, path, or component this applies to
tags: [two, to, five, lowercase-kebab, tags]
---
```

### Required by both tracks

| Field | Rule |
|-------|------|
| `title` | Non-empty; the slug derives from it |
| `date` | `YYYY-MM-DD`; when the learning was captured or last materially updated |
| `problem_type` | One of the enum values below; selects the track |
| `module` | Non-empty; what part of the system this is about |
| `tags` | Inline list, at least one entry |

### `problem_type` enum and category map

The directory (`<category>/`) is determined by `problem_type`:

| `problem_type` | Track | Category directory |
|----------------|-------|--------------------|
| `bug` | bug | `bugs/` |
| `build-failure` | bug | `bugs/` |
| `test-failure` | bug | `bugs/` |
| `runtime-error` | bug | `bugs/` |
| `performance` | bug | `performance/` |
| `security` | bug | `security/` |
| `architecture-decision` | knowledge | `architecture/` |
| `pattern` | knowledge | `patterns/` |
| `convention` | knowledge | `conventions/` |
| `tooling` | knowledge | `tooling/` |
| `process` | knowledge | `process/` |

An unknown `problem_type` is a schema violation, not a new category. Extend this
table first.

### Bug track — additionally required

| Field | Rule |
|-------|------|
| `symptoms` | What was observed failing |
| `root_cause` | Why it failed |
| `resolution` | What fixed it |

### Knowledge track — additionally required

| Field | Rule |
|-------|------|
| `applies_when` | The situation in which this learning should be recalled |

### Optional fields

| Field | Rule |
|-------|------|
| `needs_review: true` | Stamped by the migration script (or `/learn`) on any document with an inferred or missing required *content* field (`module`, `tags`, or the track fields). `/memory-maintain` sweeps these. A flagged document may have empty track-required fields — that is the flag's purpose. An inferred `date` alone does not flag the document; `date_source` records that inference instead. |
| `date_source` | Where `date` came from when it was not explicit in the source: `git-log` or `today`. Absent when the source carried its own date. |
| `migrated_from` | Source file path, stamped by the migration script. |

## Body

Free markdown. Grounding rule: a claim about how code behaves must be verified
against the tree and cited as `file:line`, or softened and attributed
("the 2026-07-08 session reported…"). Cite PR numbers, not bare commit SHAs —
rebase and squash merges rewrite SHAs.

Cross-link related documents by relative path. Migrated documents whose source
carried unmapped columns keep them in the body as `**<Column>**: <value>` lines —
nothing is dropped.

## Writing rules (`/learn`)

Before creating a document, score overlap against existing documents across the
five dimensions of the candidate's track (`/learn` Step 4 defines each):

| Track | Dimensions |
|-------|------------|
| bug | problem, root cause, solution, files touched, prevention rule |
| knowledge | situation (`applies_when`), claim, files or module, rule, consequence |

A document on the other track scores Moderate at most: cross-link it, never
merge across tracks.

| Score | Dimensions matched | Action |
|-------|--------------------|--------|
| High | 4–5 | Update the existing document. Do not create a second one. |
| Moderate | 2–3 | Create the new document and cross-link both. |
| Low | 0–1 | Create the new document. |

If the existing document is wrong, update it and note the correction — never add
a contradicting sibling. Slug collisions between distinct learnings get a numeric
suffix (`-2`), never an overwrite.
