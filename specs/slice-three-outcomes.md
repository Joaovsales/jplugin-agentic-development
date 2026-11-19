---
implementation_paths:
  - .agents/skills/build/scripts/slice_outcome.py
  - .agents/skills/build/SKILL.md
  - .agents/skills/wrap-up-session/references/closure-actions.md
  - .agents/skills/quality-gate/scripts/receipt.py
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/verify-evidence/SKILL.md
  - tests/test-slice-outcome.sh
  - tests/test-quality-receipt.sh
  - tests/test-doc-conventions.sh
---

# Spec: Slice Close records three outcomes

> Origin: #441

## Summary

A slice used to close on one result, so "the sub-agent says it is done" and
"the orchestrator saw the checks pass" could not be told apart. Slice Close now
records three results — `agent_result`, `verification_result` and
`slice_result`, each `True`, `False` or `Unknown` — and only `slice_result=True`
closes a slice. The verification result comes from a command the orchestrator
runs itself, never from anything a sub-agent reports. The quality receipt and
`/verify-evidence` name every check that did not run as `not checked`, with a
reason.

## Behavior

At Slice Close, `/build` runs its affected-test command through
`.agents/skills/build/scripts/slice_outcome.py`, passing the sub-agent's claim:

```bash
python3 .agents/skills/build/scripts/slice_outcome.py --agent <true|false|unknown> \
  -- .agents/skills/build/scripts/cached-suite.sh -- <affected-test command>
```

The script runs the command after `--` itself, lets its output through, and
prints the outcome as its last lines. `agent_result` is the sub-agent's claim:
`true` when it reported every acceptance criterion of the slice green, `false`
when it listed any under `## Not finished` or reported one failing, `unknown`
when it returned no usable report (a hang, a crash, an escape hatch with no
list). `verification_result` is the command's exit status as the script itself
observed it: `0` is `True`, a `cached-suite:` refusal (exit 3 with its
`cached-suite: a suite is already running` line on stderr) is `Unknown` because nothing ran, any other
non-zero status is `False`, and no command at all is `Unknown`. No option
accepts a verification result, so a sub-agent's quoted test output has no way
in.

`slice_result` is derived from the two, in this order:

| verification_result | agent_result | slice_result | label | exit |
|---|---|---|---|---|
| False | any | False | `VERIFICATION_FAILED` | 1 |
| Unknown | any | Unknown | `NOT_VERIFIED` | 3 |
| True | False | False | `AGENT_FAILED` | 1 |
| True | Unknown | Unknown | `AGENT_UNKNOWN` | 3 |
| True | True | True | `SUCCEEDED` | 0 |

`/build` marks the slice header `[x]` only on exit 0. Any other result leaves
the header `[ ]`: `VERIFICATION_FAILED` and `AGENT_FAILED` go back through
Step 3's repair loop, and an `Unknown` result is re-run once the cause (a held
suite lock, a missing report) is gone. The handover blockquote carries the
script's outcome line as `> Outcome:`, and the Phase 6 build report lists one
outcome line per slice.

`receipt.py write` refuses a reviewer entry recorded `lost` without a
non-empty `reason`, and `write` and `check` print one
`receipt: not checked phase <n> <lens> — <reason>` line per lost entry, so a
receipt with a lost review never reads like a fully checked one. A delta
receipt reviews only its own paths, so the lines cover every receipt in its
parent chain; an ancestor's line ends `(inherited from <fp8>)`. The verdict
rule does not change: `lost` is disclosed, not weighed.

`/verify-evidence` reports every check that did not run as
`not checked: <check> — <reason>`: never as a pass, never omitted.

## Inputs

- `--agent true|false|unknown` — the sub-agent's claim, read by the orchestrator
  from the dispatch's return.
- `-- <command…>` — the orchestrator's own verification command, optional.
- A quality-gate outcome JSON whose `reviewers` entries may carry
  `"dispatch": "lost"` with a `"reason"`.

## Outputs

`slice_outcome.py` prints, after the command's own output:

```
slice-outcome: agent_result=True verification_result=False slice_result=False VERIFICATION_FAILED
slice-outcome: verification: `<command>` exited 1
```

or, when verification did not run, `slice-outcome: not checked: verification — <reason>`
in place of the second line. Exit status as in the table; exit 2 on usage
errors. The summary always starts on a fresh line after everything the
command printed (a trailing newline is added when its stdout lacks one), and
the command's stderr is passed through as raw bytes, so undecodable output
never stops an outcome being recorded. The **last** line starting
`slice-outcome: agent_result=` is authoritative — a command that prints a
lookalike line cannot displace it — and is the `> Outcome:` handover line
verbatim (minus its `slice-outcome: ` prefix); its `key=value` fields are the
names later consumers (a per-run record, ranked candidates) read.

## Edge Cases

- The command is not found or cannot start: `verification_result=False`, the
  detail names the error, exit 1 — a verification that was asked for and broke
  is a failure, not a skip.
- `cached-suite.sh` reuses an earlier green run of the same command on the same
  tree: exit 0, so `True` — that run happened on exactly this tree.
- The command itself exits 3 without the lock-refusal line — including after
  `cached-suite.sh`'s other notes, such as `running uncached` — `False`; only
  the refusal line makes exit 3 mean "nothing ran".
- An `--agent` value other than the three is refused with exit 2.
- A stored receipt written before this change with a `lost` entry and no
  reason: `check` prints `— no reason recorded`, it does not refuse.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where does the derivation live? | A new `.agents/skills/build/scripts/slice_outcome.py`, not a `slice.py` subcommand | assumed | `slice.py` owns plan structure and is already over 800 lines; run results are `/build`'s Slice Close concern |
| 2 | How is a quoted test output kept from closing a slice? | The script runs the verification command itself and has no option that accepts a verification result | assumed | a missing input channel is a structural guarantee; a rule in prose is not |
| 3 | Does `verification_result` include the gate-integrity check? | Not yet: it covers the affected-test command; the gate-integrity check (#439) does not exist on master and joins as a second input when it lands | assumed | requiring an absent check would make every slice `Unknown`; the outcome names only checks that ran |
| 4 | Which results close a slice? | Only `slice_result=True`; both `False` and `Unknown` keep the header `[ ]` | assumed | "not checked" is never clean |
| 5 | Exit status for `Unknown`? | 3, the same "nothing ran" status `cached-suite.sh` uses; `False` is 1 | assumed | a caller tells a retry from a repair by status alone |
| 6 | Must a `lost` reviewer carry a reason? | Yes, `write` refuses one without it; `check` tolerates old receipts | assumed | a skip carries a reason; old receipts must still verify |
| 7 | Does a lost review change the verdict? | No — unchanged from the existing rule | assumed | out of scope; #429 owns receipt verdict soundness |

## Acceptance Criteria

- AC1: `slice_outcome.py --agent true -- <command exiting 1>` prints
  `slice_result=False VERIFICATION_FAILED` and exits 1, and `/build` § Slice
  Close marks a header `[x]` only when the script exits 0, so the slice stays
  open.
- AC2: `slice_outcome.py` accepts no verification result as input: with no
  command it prints `verification_result=Unknown`, a
  `not checked: verification — <reason>` line, and exits 3; a `cached-suite:`
  refusal is `Unknown`, not `False`; `/build` § Slice Close states that a
  sub-agent's quoted test output never closes a slice.
- AC3: `receipt.py write` refuses a `lost` reviewer entry with no reason, and
  `write` and `check` print `receipt: not checked phase 5 test-engineer — <reason>`
  for a lost entry; `/verify-evidence` and `/quality-gate` state that a check
  that did not run is reported as `not checked: <check> — <reason>`, never as
  clean.
- AC4: the `/build` handover carries a `> Outcome:` line with `agent_result`,
  `verification_result` and `slice_result`, the Phase 6 report lists one
  outcome per slice, and the PR body's `## Handovers` section carries the
  `> Outcome:` line.

## Implementation Paths

- `.agents/skills/build/scripts/slice_outcome.py` — runs the verification command and derives the three outcomes.
- `.agents/skills/build/SKILL.md` — Slice Close calls the script, closes only on `SUCCEEDED`, writes `> Outcome:`; Phase 6 lists outcomes.
- `.agents/skills/wrap-up-session/references/closure-actions.md` — the PR body's Handovers section carries `> Outcome:`.
- `.agents/skills/quality-gate/scripts/receipt.py` — requires a reason on `lost`, prints `not checked` lines.
- `.agents/skills/quality-gate/SKILL.md` — the lost entry's `reason` field in the outcome contract.
- `.agents/skills/verify-evidence/SKILL.md` — the `not checked` wording rule.
- `tests/test-slice-outcome.sh` — the derivation table, the refusal, the missing command.
- `tests/test-quality-receipt.sh` — the lost reason and the `not checked` lines.
- `tests/test-doc-conventions.sh` — pins the Slice Close, Phase 6, handover and wording rules.

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: three systems (the build skill, the wrap-up handover reference and its tests), because the `> Outcome:` line the build writes and the PR section that carries it are one contract; slice 2: three systems (quality-gate, verify-evidence and their tests), because the `not checked` wording is one rule across both.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Slice outcome at Slice Close | `slice_outcome.py` derives the three outcomes from the orchestrator's own run; Slice Close closes only on `SUCCEEDED` and writes `> Outcome:` | `.agents/skills/build/scripts/slice_outcome.py`, `.agents/skills/build/SKILL.md`, `.agents/skills/wrap-up-session/references/closure-actions.md`, `tests/test-slice-outcome.sh`, `tests/test-doc-conventions.sh` | — | 1, 2, 4 | `bash tests/run.sh tests/test-slice-outcome.sh tests/test-doc-conventions.sh` | 5 files · 3 systems · 3 ACs |
| 2 | Not checked is never clean | the receipt requires a reason on a lost review and prints `not checked`; `/verify-evidence` and `/quality-gate` state the wording rule | `.agents/skills/quality-gate/scripts/receipt.py`, `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/verify-evidence/SKILL.md`, `tests/test-quality-receipt.sh`, `tests/test-doc-conventions.sh` | 1 | 3 | `bash tests/run.sh tests/test-quality-receipt.sh tests/test-doc-conventions.sh` | 5 files · 3 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/slice-three-outcomes.md`.
Plan: `## Plan: slice-three-outcomes` in `tasks/todo.md`, 2 slices, ready set <1>.
Files: .agents/skills/build/scripts/slice_outcome.py, .agents/skills/build/SKILL.md, .agents/skills/wrap-up-session/references/closure-actions.md, .agents/skills/quality-gate/scripts/receipt.py, .agents/skills/quality-gate/SKILL.md, .agents/skills/verify-evidence/SKILL.md, tests/test-slice-outcome.sh, tests/test-quality-receipt.sh, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: verification_result comes only from a command the script runs (D2); only slice_result=True closes a slice (D4); the gate-integrity check is #439's, not this plan's (D3); build/SKILL.md stays at most 600 lines.
```
