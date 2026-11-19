---
implementation_paths:
  - .agents/skills/build/scripts/candidates.py
  - .agents/skills/build/scripts/run_ledger.py
  - .agents/skills/build/references/candidates.md
  - .agents/skills/build/references/run-ledger.md
  - .agents/skills/build/SKILL.md
  - tests/test-candidates.sh
  - tests/test-doc-conventions.sh
---

# Spec: Parallel candidates — several Builders on one slice, one winner by fixed rules

> Origin: #445 · Designed 2026-11-19 · Review status: **unattended improve-lane run, critic lens run inline** (no sub-agent tool in this worker)

## Summary

A slice that opts in with a `> Candidates: <N>` line is built N times, each
Builder in its own detached worktree. `candidates.py rank` measures and
verifies every candidate itself, ranks them by a fixed lexicographic key,
applies the winner's diff to the main tree, records every candidate with the
reason for its place in the run ledger, and removes every candidate worktree
— also when it is cancelled. The decision not to miss: eligibility is the
three-outcome `slice_result` (#441), so a candidate whose check failed or did
not run sorts behind every eligible one and is never applied.

## Behavior

1. `/build` reaches a slice whose heading in `tasks/todo.md` carries
   `> Candidates: <N>` (N ≥ 2). Without that line the slice builds as before.
2. `candidates.py open --slice <n> --count <N>` creates N detached worktrees
   at the current `HEAD` through `bootstrap-worktree.sh --detach-head` (the
   worktree setup `/build` and `/eval` already use), at
   `<toplevel>/../<repo>-slice-<n>-c<k>`, and prints one
   `candidates: c<k> <path>` line each. It is all-or-nothing: a failure
   removes the worktrees it already made.
3. `/build` dispatches one Builder per path with the slice's normal
   delegation prompt and the rule "edit only inside <path>".
4. `candidates.py rank` takes each dispatch's claim (`--agent c<k>=true|false|unknown`,
   absent = `unknown`) and the affected-test command after `--`. For each
   candidate in id order it stages the worktree, measures the diff against the
   worktree's starting commit, then runs the verification through
   `slice_outcome.py` inside that worktree.
5. It ranks, prints one line per candidate, records them in the run ledger,
   applies the winner's diff to the current tree with `git apply`, and removes
   every candidate worktree.
6. Slice Close then runs as for any slice, against the applied winner.
7. `candidates.py discard --slice <n>` removes the slice's candidate
   worktrees when the build stops between `open` and `rank`.

## Inputs

- `open --slice <n> --count <N>`: slice number, N ≥ 2.
- `rank --spec <spec> --slice <n> --branch <b> --base <sha> [--run-id <id>]
  [--ledger <dir>] [--agent c<k>=<v>]... -- <verification command>`: the
  slice's Surface comes from the spec through `slice.py`'s own resolver;
  branch and base are the build's, as Phase 6 passes them.
- `discard --slice <n>`.

## Outputs

`rank` prints, in rank order:

```text
candidates: c<k> rank=<r> selected|discarded eligible|ineligible checks=<p>/2 diff_lines=<d> outside_surface=<o> <LABEL> — <reason>
candidates: applied c<k>
```

- Reasons: the winner `selected: ahead of c<j> on <signal> (<a> vs <b>)`, or
  `selected: only eligible candidate`; an eligible loser
  `behind c<j> on <signal> (<a> vs <b>)`, where c<j> is the candidate ranked
  just above it; an ineligible candidate `ineligible: <LABEL>`.
- The run record (`tasks/runs/<run-id>.json`) gains
  `candidates: {"<slice>": [ {candidate, rank, selected, eligible,
  agent_result, verification_result, slice_result, label, checks_passed,
  diff_lines, outside_surface, reason} ]}`. The schema stays `run-ledger/1`:
  the field is additive, `record` keeps it, `stats` does not read it.
- Exit: 0 a winner was applied; 1 no eligible candidate (nothing applied), the
  winner's diff does not apply (the patch is kept under `tasks/tmp/`), or no
  candidate worktree exists; 2 usage.

### Ranking key

Lexicographic and total, smallest first:

1. eligible before ineligible (eligible ⇔ `slice_result=True SUCCEEDED`);
2. more checks passed (`agent_result` and `verification_result` that are `True`);
3. fewer diff lines (added plus deleted, a binary file counts 1);
4. fewer changed paths outside the slice's Surface;
5. lower candidate number — the tiebreak that makes the order total.

Nothing outside these recorded measurements — model confidence, timing,
dispatch order — enters the key.

## Edge Cases

- A Builder commits inside its worktree: the diff is measured against the
  commit the worktree started at (stored in the worktree's git dir), so
  committed and uncommitted work both count.
- Verification creates files (caches, logs): the diff is measured and the
  patch captured before verification runs.
- No candidate is eligible: every candidate is recorded `discarded`, nothing
  is applied, exit 1 — the slice goes to Step 3 like any failed slice.
- An empty diff that passes its checks is eligible and ranks first by size;
  Slice Close's surface check then reports every Surface path `untouched`.
- `rank` is cancelled (SIGTERM, SIGHUP, Ctrl-C): a `finally` removes every
  candidate worktree before the process exits non-zero.
- `open` when the slice already has candidate worktrees: refused, naming
  `discard`.
- `open` is all-or-nothing: each target is owned before its bootstrap starts,
  so a failing bootstrap (a `post-checkout` hook exiting non-zero, say) or a
  SIGTERM/SIGHUP/Ctrl-C mid-bootstrap stops the bootstrap's process group,
  waits for it, then removes every candidate this call made. A target path
  that already exists is refused and never deleted — this run did not make it.
- git refuses to remove a candidate (`git worktree lock`): the directory and
  its registration are kept, the refusal is printed with git's reason, and
  `discard` (or `rank`, after its own result) exits 1. A candidate is reported
  `removed` only once git no longer lists it.
- The verification wrapper dies or disagrees with itself — killed after its
  command printed a success-shaped line, an agent value other than the claim
  passed in, an exit status that does not match its own summary: the
  candidate's verification counts as failed, never eligible.
- The main tree moved since `open` (another slice landed): the winner's diff
  is applied with `git apply`; a conflict exits 1, keeps the patch under
  `tasks/tmp/` and still records the ranking.
- A refused `rank` call — a spec or slice that does not resolve, a run id that
  is not a safe file name, a base that is not a SHA — exits before measuring
  and keeps every candidate worktree, so a typo never costs the Builders' work.

## Interfaces

### candidates.py

- **Path:** `.agents/skills/build/scripts/candidates.py`
- **Hides:** where candidate worktrees live, each one's base commit, how a
  diff is measured, the ranking key and the cleanup on cancellation.
- **Interface:** `candidates.py open|rank|discard --slice <n> …`
- **Alternative considered:** a pure `rank` over measurements the
  orchestrator gathers — it lost because the orchestrator would then measure
  and verify by hand, and an agent-quoted result is the input #441 removed.
- **Depth:** one `rank` call verifies, measures, ranks, records, applies and
  cleans up N worktrees.

### run_ledger.add_candidates

- **Path:** `.agents/skills/build/scripts/run_ledger.py`
- **Hides:** the record's load-or-create rule, shared with `record`.
- **Interface:** `add_candidates(ledger, branch, base, run_id, slice_id, entries)`
- **Depth:** writes one slice's candidates into the run record atomically.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | A SIGKILL leaves worktrees behind | L | L | no handler can run on SIGKILL; `discard` and `git worktree prune` clean up, and `open` refuses while leftovers exist, so they are seen | 1 |
| R2 | N candidates cost N times one attempt | H | M | opt-in per slice only; the ledger records every attempt so a later comparison against one stronger attempt is possible | 2 |

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: four ACs, because they are one script's semantics — the ranking, its eligibility rule, its cleanup and the record it writes are one `rank` call.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Candidate ranker | `candidates.py` opens, ranks and discards candidate worktrees; `run_ledger.add_candidates` records the ranking | `.agents/skills/build/scripts/candidates.py`, `.agents/skills/build/scripts/run_ledger.py`, `tests/test-candidates.sh` | — | 1, 2, 3, 4 | `bash tests/run.sh tests/test-candidates.sh tests/test-run-ledger.sh` | 3 files · 2 systems · 4 ACs |
| 2 | Build runs candidates | `/build` names the opt-in and the flow; the references document the commands and the ledger field | `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/candidates.md`, `.agents/skills/build/references/run-ledger.md`, `tests/test-doc-conventions.sh` | 1 | 5 | `bash tests/run.sh tests/test-doc-conventions.sh` | 4 files · 2 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/parallel-candidates.md`.
Plan: `## Plan: parallel-candidates` in `tasks/todo.md`, 2 slices, ready set <1>.
Files: .agents/skills/build/scripts/candidates.py, .agents/skills/build/scripts/run_ledger.py, .agents/skills/build/references/candidates.md, .agents/skills/build/references/run-ledger.md, .agents/skills/build/SKILL.md, tests/test-candidates.sh, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: eligibility is slice_outcome's SUCCEEDED (D2); the ranking key ends in the candidate number (D3); the run record stays run-ledger/1 (D5); build/SKILL.md stays at most 600 lines.
```

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| D1 | How a slice opts in | a `> Candidates: <N>` line under its `### Slice` heading in `tasks/todo.md` | assumed | per slice, durable across compaction, and no parser change; the issue asks for opt-in per slice |
| D2 | Eligibility | `slice_result=True SUCCEEDED` from `slice_outcome.py`, run by `rank` inside the worktree | assumed | #441 owns the outcome contract; a failed or unknown check can never win |
| D3 | Ranking key | eligible, checks passed, diff lines, outside-Surface paths, candidate number | assumed | the issue's order; the candidate number makes the order total so the same set always ranks the same |
| D4 | Where worktrees live | `<toplevel>/../<repo>-slice-<n>-c<k>`, detached, via `bootstrap-worktree.sh --detach-head` | assumed | the script's own sibling-path convention; detached means no branch to delete; under `.git/` an editor may refuse writes |
| D5 | Where the ranking is recorded | a `candidates` field in the run's `run-ledger/1` record, written by `rank` | assumed | the issue's "each attempt in the ledger"; additive, so no schema bump and `record` keeps it |
| D6 | How the winner lands | `rank` applies its staged diff with `git apply`; Slice Close verifies it centrally | assumed | the worktrees are removed in the same call, so the diff must leave before they do |
| D7 | Spec route | `/plan`, not `/system-design-planning` | assumed | one new script, one additive field in an existing record, no external contract |

## Acceptance Criteria

- AC1: the same candidate set always gives the same ranking — `rank` over the
  same measurements in any input order prints the same lines, and two `rank`
  runs over identically built worktrees print identical candidate lines.
- AC2: a candidate that failed any check — `verification_result` or
  `agent_result` not `True` — is never selected or applied, even when its
  diff is the smallest; with no eligible candidate `rank` exits 1 and the
  main tree is unchanged.
- AC3: every candidate worktree is removed after `rank` — on success, on no
  winner, and when `rank` is terminated mid-verification — and `discard`
  removes them when the build stops before `rank`; an `open` whose bootstrap
  fails or is terminated leaves none behind; a candidate git refuses to remove
  (a locked worktree) is kept and reported, and the call exits 1.
- AC4: the run ledger record holds one entry per candidate with its rank,
  selected flag, three outcomes, measurements and the reason for its place.
- AC5: `/build` names the opt-in line, the `open` → dispatch → `rank` flow and
  `discard`; `.agents/skills/build/references/candidates.md` and
  `references/run-ledger.md` document the commands and the `candidates` field.

## Implementation Paths

- `.agents/skills/build/scripts/candidates.py` — open, rank and discard candidate worktrees.
- `.agents/skills/build/scripts/run_ledger.py` — `add_candidates` writes the ranking into the run record.
- `.agents/skills/build/references/candidates.md` — the opt-in and the command flow for `/build`.
- `.agents/skills/build/references/run-ledger.md` — the `candidates` field and who writes it.
- `.agents/skills/build/SKILL.md` — Phase 1 points to the candidate flow for an opted-in slice.
- `tests/test-candidates.sh` — AC1–AC4.
- `tests/test-doc-conventions.sh` — pins AC5's wiring.
