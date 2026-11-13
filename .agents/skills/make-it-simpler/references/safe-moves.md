# Safe moves

The five practices every spec `/make-it-simpler` writes carries as § Decisions
rows, so the build and the design review hold the simplification to them. They
came out of the wrap-up-phases rewrite (#204), where each one was a regression
caught late. § *Cross-area deduplication* is a sixth row, seeded only for a task
sized through it.

1. **Headings are names only.** A heading says what the section is, never a
   step number or a count — `## Full suite`, not `## Step 6 — Full suite (3 checks)`.
   A renumbered section must not break a single caller.
2. **Callers cite by § name.** Every pointer into a moved or trimmed file cites
   `` `<file>` § *<Heading>* ``, never a step number or a line number, and
   `bash tests/test-citations.sh` passes before and after.
3. **A moved assertion is repointed, never deleted without a replacement.** When
   a pinned sentence moves, its test follows it to the new home in the same
   commit; a test is deleted only when the rule it pins is deleted and the PR
   says so.
4. **One home per rule.** A rule stated in several files keeps one statement;
   the others cite it by § name.
5. **No script behavior change unless declared minor.** Scripts keep their
   inputs, outputs and exit codes. A change the simplification needs is listed
   under the PR body's `Behavior changes:`; an undeclared one found by review is
   **STOP**.

## Cross-area deduplication

A `duplicate-rule` move counts as one area for the unattended cap, whatever
skills its copies sit in, when every condition holds:

- It moves one rule: each copy becomes a one-line § citation of the rule's
  existing home, and nothing else in those files changes.
- Every citation resolves wherever its file is read — `` `/<skill>` § *<Heading>* ``
  or `` `.agents/references/<file>.md` § *<Heading>* ``. A home under another
  skill's `references/` is not eligible: that path does not resolve from a plugin
  install, and moving the rule into `.agents/references/` first is its own change.
- Every assertion pinning a copy is repointed in the same change (practice 3).

Copies under `.agents/agents/` or `.claude/agents/` are out of the move's scope and stay
byte-identical — a sub-agent persona starts in a fresh context and may never
open a citation — and their presence does not disqualify the move. Practice 4
yields to this rule for them.
