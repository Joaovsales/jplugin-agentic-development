---
name: software-design-expert-review
description: Run a focused APOSD design review on recently changed files. Scans for the 10 red flags from 'A Philosophy of Software Design' plus Error Design (R11), emits four-axis findings (severity, confidence, autofix_class, owner), and produces a GO / HOLD / STOP verdict. Can be invoked manually or called by /build Phase 3.5.
compatibility: >
  Requires a git repository. Works with any language. No external dependencies.
  When invoked manually: scopes to uncommitted / recently touched files by default.
  Supports --file and --scope flags for narrowing.
---

# /software-design-expert-review — APOSD Design Quality Gate

Run a focused structural review based on *A Philosophy of Software Design* by John Ousterhout. This skill is **not** a general code review — it hunts specifically for depth, abstraction, coupling, and hidden-complexity red flags.

**When to run:**
- Manually: `/skill:software-design-expert-review` after you want a design-only sanity check
- Automatically: `/build` Phase 3.5 invokes this gate on every changed file before declaring the build complete
- After refactors: when you've restructured modules and want to verify you didn't create shallow abstractions

**How to run:**
```
/skill:software-design-expert-review              # Review all changed files in current branch
/skill:software-design-expert-review --file path  # Scope to one file
/skill:software-design-expert-review --scope auth # Scope to functional area (grep + diff)
```

---

## Phase 1 — Gather Evidence

1. Determine changed files:
   - If `--file` provided: use that file only.
   - If `--scope` provided: `git diff --name-only <base>..HEAD | grep -i <scope>`.
   - Default: `git diff --name-only <base>..HEAD`.
2. For each file, capture approximate size and nature (new / modified / deleted).
3. Note any new file with **no public interface tests** — flag as `SHOULD-FIX` immediately.

**Base branch detection** (same rules as `/wrap-up-session`):
- `main` → `master` → `develop` → `git merge-base HEAD origin/HEAD`
- Store as `<base-branch>` for all subsequent steps.

---

## Phase 2 — Dispatch APOSD Reviewer Agent

For each changed file (or grouped batch if <5 files), dispatch the `software-design-expert-review` agent (Ceiling tier — pass no `model` at all, so it inherits the session model; see `CLAUDE.md` § *Model Routing*) in a single tool call. Pass the seven items in `CLAUDE.md` § *Review Dispatch Contract*, which for this gate means:
- The git diff for the file(s)
- Absolute paths of the files
- Every spec relevant to this session: each one's path and its acceptance criteria
  verbatim, or `no spec — <reason>`
- The `tasks/todo.md` entries closed this run
- The `[AMBIGUITY]` lines and any `TODO(shortcut):` markers in these files, or `deferrals: none` — an accepted trade-off is not a red flag, and R1–R11 have no way to tell the difference from the diff alone
- The boundary: review issues **introduced** by this diff; pre-existing structure inside a changed file is out of scope
- The instruction: "Review ONLY these changed files. Emit every finding in the canonical four-axis format `[SEVERITY | confidence | autofix_class | owner] file:line — description`, with an `evidence:` line quoting the motivating source line for any finding at anchor `75` or `100`."

Withhold conclusions — no prior findings, no builder rationale. Batches are the unit
of independence here (Phase 3), so an inherited opinion inflates corroboration.

Do **not** ask the agent for the old single-axis `[MUST-FIX]`-only format. The
persona emits four axes; an instruction to strip them here silently discards the
`confidence` this gate needs, and every finding then degrades to anchor `50`.

### Agent Failure Handling
- If the agent errors or returns unparseable output: log the failure, label review status `degraded`, and proceed to Phase 3 with a warning.
- If the agent returns findings with no `confidence`, treat each as `50` /
  `autofix_class: manual` per `CLAUDE.md` § *Finding Model* — reported, never
  discarded. Do not re-dispatch to chase the format.

---

## Phase 3 — Severity Reconciliation

Parse agent output. Every finding must have:
- **`severity`**: `MUST-FIX`, `SHOULD-FIX`, or `NITPICK`
- **`confidence`**: `50`, `75`, or `100`
- **`autofix_class`**: `gated_auto`, `manual`, or `advisory`
- **`owner`**: `agent`, `human`, or `release`
- **Location**: `file:line`
- **Red Flag ID**: `R1`–`R11`
- **Impact**: one sentence
- **`evidence`**: the verbatim motivating line, required at `confidence` `75` or
  `100`. Missing evidence **demotes** the finding to `50`; it is never dropped.

Deduplicate identical findings (same file:line + same root cause):

- Keep the **highest** `severity`.
- Take the **more conservative** `autofix_class` (`advisory` > `manual` >
  `gated_auto`). Synthesis never widens.
- Two findings from **separately dispatched** batches naming the same `file:line`
  are independent corroboration: promote `confidence` by exactly one anchor. Two
  lenses inside a single batch are not — see `CLAUDE.md` § *Independence
  Accounting*. Batching files therefore trades corroboration for tool calls;
  state which happened in the output.

---

## Phase 4 — Verdict & Gate Logic

The verdict counts **confirmed** findings — `confidence >= 75`, which by the
evidence gate means a quoted `file:line` proves them:

```
🟢 GO   — Zero confirmed MUST-FIX and SHOULD-FIX, or only NITPICKs.
🟡 HOLD — No confirmed MUST-FIX, but >0 and ≤3 confirmed SHOULD-FIX. Log as design debt and proceed.
🔴 STOP — Any confirmed MUST-FIX, or >3 confirmed SHOULD-FIX.
```

**A `MUST-FIX` at `confidence` `50` does not STOP the build.** Read the sites the
red flag depends on and resolve the anchor first:

- Evidence found → it is `75`+, counts as confirmed, and STOP applies.
- Refuted → drop it, and say so in the findings table.
- Cannot be resolved in this pass → log it as design debt and verdict `HOLD`.

An unproven structural claim halting a build is the failure mode this split
exists to prevent: R1 Repetition inferred from shape rather than read across all
sites, or R9 Shallow Module judged without reading the callers, is exactly the
finding most likely to be wrong and most expensive to obey. Never raise an anchor
to force a STOP, and never lower one to avoid it.

**STOP behavior (when invoked by /build):**
- Halt the build immediately. Do NOT proceed to Phase 4 (Spec Validation).
- Present the user with a terse table of MUST-FIX findings and ask:
  > _"Build halted: [N] MUST-FIX APOSD findings detected. Fix them now and retry, or acknowledge and proceed? (fix/acknowledge)"_
- On `acknowledge`: log all findings in `tasks/design-debt.md` (create if absent) with date + commit short-sha, then downgrade verdict to `HOLD` and proceed.
- On `fix`: convert findings into `[ ]` tasks appended to `tasks/todo.md`, return to /build Phase 1 for those tasks only. After fixes, the build must re-run **only this Phase 3.5** (not full Phase 1–3).

**STOP behavior (when invoked manually):**
- Print the findings table and STOP. User decides whether to fix or proceed independently.

**HOLD behavior:**
- Print all SHOULD-FIX items under a `Design Debt:` section.
- Proceed to the next phase. No user prompt for ≤3 SHOULD-FIX.

---

## Output Format

When invoked manually, produce:

```markdown
# APOSD Design Review — <scope>

## Evidence
| File | Δ | Nature |
|------|---|--------|

## Findings
| # | Severity | Conf | Autofix | Owner | Flag | Location | Evidence | Impact | Suggestion |
|---|----------|------|---------|-------|------|----------|----------|--------|------------|

## Verdict
🟢 GO / 🟡 HOLD / 🔴 STOP

Review independence: [N batches dispatched separately / single batch — no promotion available]
Unconfirmed (anchor 50, excluded from the verdict): [N — list, or none]

## Design Debt (if HOLD or acknowledged STOP)
| File:Line | Flag | Conf | Issue |
|-----------|------|------|-------|
```

When invoked by `/build`, emit only:
```
APOSD GATE: [PASS / HOLD / STOP]
Confirmed (75+): [N MUST-FIX, N SHOULD-FIX, N NITPICK]
Unconfirmed (50): [N — reported, not gated]
```

The unconfirmed count is not optional. Findings the verdict excluded are the ones
most likely to be lost, and a gate that reports only what it counted reads as
though nothing else was found.

---

## References

- `.agents/skills/software-design-expert-learn/references/principles.md` — Full APOSD principles catalog
- `.claude/agents/software-design-expert-review.md` — The agent prompt and red flag definitions

## Confidence Note for Builders

> "The best module is one where the interface is so simple that the implementation could be completely rewritten without callers noticing."

This skill enforces that standard before a build is declared structurally sound.
