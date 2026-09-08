# Lens: `architect` — design

The `architect` routine looks for structure that will be wrong tomorrow: APOSD
red flags over the whole tree rather than over a diff. Its engine is the design
review, widened to the tree, and the bar to file is a quoted line.

## Engine

1. **Tree review.** Invoke `/software-design-expert-review --scope tree` — every
   source file, excluding tests and vendored paths, batched by directory. When
   dispatch is unavailable the review runs inline and reports
   `single batch — no promotion available`; the sweep carries that statement into
   the record's *Independence* section.
2. **Every `MUST-FIX` and `SHOULD-FIX`** finding is a candidate. `NITPICK` is
   read and dropped — it is never filed.
3. Directories the review did not reach (batch budget spent, unreadable source)
   are coverage gaps with the prerequisite that would reach them.

## Bar

A candidate is filed only with all of:

- An `evidence` line quoting the motivating code verbatim with `file:line`.
- Confidence `75` or above. A `75` must name the caller, config key, or runtime
  value it turns on; read it before filing and promote to `100` or drop.
- A proposed fix as concrete steps and at least one checkable criterion.

Files as `--kind task --label tech-debt`, or `--kind decision` when the proposed
fix is a choice between designs that a human must make — the record states the
options, not a pick. `MUST-FIX` → `--label now`, `SHOULD-FIX` → `--label next`.
Product code is never edited by this lens.
