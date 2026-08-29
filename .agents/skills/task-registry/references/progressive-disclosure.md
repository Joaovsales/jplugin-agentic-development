# Progressive Disclosure Rules

Why this file exists: the failure mode of task tooling is not missing
information, it is a wall of it. A `reconcile` that prints every issue body is
worse than no reconcile at all, because it costs the context window the work
itself needs.

---

## The rules

1. **Summary before detail, always.** Every command prints its provider, its
   mode, and a count per category before a single per-task line.
2. **At most 20 lines per category.** Beyond that: `… N more (pass --verbose)`.
   `--verbose` is a choice the reader makes, never a default.
3. **One line per task.** ID, a truncated title, and what diverged. Nothing else.
4. **Never a body.** Issue bodies, comments, and acceptance criteria do not
   appear in `reconcile`, `publish`, `pull`, or `frontier` output at any verbosity.
5. **`show <task-id>` is the only expansion.** It prints one task in full,
   fetching from the provider on demand.
6. **Limitations and failures are never truncated.** They are the lines a reader
   most needs and the shortest sections; they print in full.

---

## What lives where

| Content | Lives in | Never in |
|---------|----------|----------|
| status box, title, ID, link, one-line summary, dependency marker | `tasks/todo.md` row | — |
| acceptance criteria | external ticket, or the linked spec | the index |
| discussion, decisions, review notes | ticket comments | the index |
| long-form design | `specs/<feature>.md` | the index, the ticket body |
| evidence links | task metadata (`evidence:`) | the index |

The test suite pins the direction of this table: assertions assert that criteria
appear under `show` and are *absent* from both the index and the reconcile output.

---

## When a summary is still too long

The output is bounded, but a genuinely divergent repository can still produce a
long summary. In order:

1. `frontier` instead of `reconcile` — it answers "what can I do now", which is
   usually the actual question.
2. Fix one category at a time. `missing-id` is almost always first: run `migrate`,
   and most of the other categories collapse because identity starts working.
3. `stale-spec` and `superseded-spec` accumulate and never resolve themselves —
   they are a human decision, and the registry will keep reporting them until
   somebody makes it.

---

## For skills calling the registry

- Call `reconcile` (dry-run) and surface **the summary block only** to the user.
- Never inline a `show` result into a plan, a commit message, or `tasks/todo.md`.
- When reporting to a sub-agent, pass the summary plus the task IDs — not the
  full output. This is `.claude/project.md` § *Large-Artifact Handoff* applied to
  task state: truncate with a pointer, because the pointer (`show <task-id>`)
  actually resolves.
