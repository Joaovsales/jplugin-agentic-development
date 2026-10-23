---
title: Four unresolved SHOULD-FIX make a HOLD, and a delta receipt inherits its parent's
date: 2026-10-22
problem_type: process
module: .agents/skills/quality-gate/scripts/receipt.py derive_verdict, chain_should_fix_carry; /quality-gate phases 4-6
tags: [quality-receipt, should-fix, hold, delta-scope, follow-up, apply-gate]
applies_when: a quality-gate pass ends GO from the design reviewer but leaves several `manual` or `advisory` SHOULD-FIX findings reported, and the session wants to act on some of them before wrap-up; or wrap-up stands at `approve-hold` and the findings are to be fixed rather than approved
---

## The claim

`receipt.py` derives the verdict; the gate never supplies one. Two rules in
`derive_verdict` (`.agents/skills/quality-gate/scripts/receipt.py:336-344`)
decide what a reviewer's GO becomes:

- more than three unresolved `SHOULD-FIX` → `HOLD`, whatever the design
  verdict said;
- with `--parent`, `chain_should_fix_carry` (line 317) adds every ancestor
  receipt's unresolved `SHOULD-FIX` up to the nearest approved HOLD, so a
  delta-scoped re-gate that fixes the parent's findings still counts them.

The 2026-10-19 build saw both: pass 2 returned GO with four SHOULD-FIX and the
receipt read `HOLD`; a delta re-gate would have carried those four into the
next receipt even after they were fixed.

## The rule

When the Apply Gate leaves `manual`/`advisory` findings you intend to fix:

1. Finish the pass honestly — Phase 5 and the receipt for the tree as reviewed
   (a STOP or HOLD receipt for a superseded tree is a record, not a blocker).
2. Make the follow-up edits, then re-run the gate at **full scope with no
   `--parent`**: a fresh receipt counts only what is still unresolved. Reserve
   `--scope … --parent` for the case wrap-up names — a tree that changed under
   a GO receipt — not for clearing a HOLD by fixing its findings.
3. Keep the unresolved count at three or fewer by fixing or by declining with a
   reason the summary records (a spec decision the finding contradicts is a
   reason; "later" is not).

## The consequence of ignoring it

An unattended wrap-up never approves a HOLD, so a branch whose only defect is
the count of reported findings ends without a push. Three full-scope passes
(HOLD → HOLD-by-count → GO) cost three Ceiling-tier reviews here; knowing the
threshold up front would have folded the second pass's follow-ups into the
first. Sibling: [name-the-gate-outcome-file-per-session-in-the-shared-receipt-store.md](name-the-gate-outcome-file-per-session-in-the-shared-receipt-store.md).

## Confirmed again on 2026-10-21 (test-suite-aposd, #336–#347)

A dispatched `software-design-expert-review` of a 102-file test-suite migration
returned **GO** with eight `SHOULD-FIX` seam findings (grammars now spelled in
several files, callers reaching into library state, a recorded duplication) —
all `manual` or `advisory`, so the Apply Gate reported them and the receipt read
`HOLD` by count. On an interactive branch the wrap-up then asks the user to
approve or to fix; nothing else moves. Two things the rule above did not say:

- Decide **before** Phase 5 whether to fix or to carry: here the affected set
  was the whole suite (a runner file changed), so a fix-and-re-gate costs a
  40-minute Windows run per pass.
- A big migration's design findings are mostly "the deep module created a seam
  that is now spelled in N files". Those are follow-up work by nature; expect
  the count to exceed three and plan the approval, rather than meeting the
  threshold by reclassifying.

### What "fix first" costs (2026-10-22)

The user chose to fix the agent-owned findings rather than approve. Three
facts decided the shape of that pass:

- **An unapproved HOLD receipt is not a parent.** `receipt.py check` validates
  the pointer's receipt with `_link_valid` (GO, or HOLD *with*
  `hold_approved_by`); an unapproved HOLD fails it, so after the fix `check`
  prints `stale missing`, not `diff-changed … delta …`, and
  `chain_should_fix_carry` would sum the HOLD's own findings into a delta
  receipt anyway. The fix path is therefore a **full-scope re-gate**: Phases 1–4
  over the whole diff (a second Ceiling-tier design dispatch), Phase 5 again,
  `receipt.py write` with no `--parent`. Only an *approved* HOLD bounds a delta.
- **The second design pass finds the next layer.** Seven seam findings fixed,
  the reviewer returned GO with five new SHOULD-FIX — enough for a second HOLD
  by count. Two more were fixed in the same gate run (the forged trailers, the
  seed-fence coupling) to bring the unresolved count under the threshold; the
  others are carried with their upgrade paths. Budget a second small fix pass
  into "fix first", not just the re-gate.
- **A Builder-tier agent can carry the fix passes.** A `sonnet`
  `backend-developer` landed the seven findings in one dispatch (21dafea: 37
  files, +369/−256) and the two follow-ups in another, green file-by-file,
  with `[AMBIGUITY]` lines where the brief under-specified (the `py_module
  <dir> <var>` form, refusing a third `fail` argument, the one counter
  recorder, the unittest fold duplicated per file). Verification stayed
  central; Linux was checked under WSL before each Windows run.

Outcome: receipt 032af75c **GO** (policy qg1-b803d96b); unresolved: 3 SHOULD-FIX (run's merged capture and the fixture primitives' wrapping idiom, owner agent; the per-piece preambles, owner human) and 3 NITPICK.

## 2026-10-22 — fixing a HOLD's findings from the approve-hold step

The read-shunt build reached wrap-up's `approve-hold` with receipt 96f14a60
(HOLD, six SHOULD-FIX) and chose to fix rather than approve. Two things the
rule above did not say:

- **`check` routes the fixed tree to full scope by itself.** The branch pointer
  names the HOLD receipt; `_chain_valid` rejects an unapproved HOLD, so
  `stale_against_pointer` returns `missing`, not `diff-changed`
  (`receipt.py:455-463`). Wrap-up's table then says one full-scope gate, and no
  `--parent` carry can occur. Do not hand-build a delta call.
- **Each full pass finds new things.** The second pass's Ceiling reviewer
  returned one MUST-FIX (an argument probe that could pair one run's
  transcript with another's outcome) and four SHOULD-FIX on the code the first
  pass's fixes touched; a third pass followed. Fixing by a Builder-tier
  sub-agent with the reviewer's own fix directions pasted verbatim kept each
  round to one dispatch, and the fixes should land as one commit per round so
  the next reviewer's delta log is one range.
- The closure state cannot express "fix instead": observe `approve: declined`
  (terminal `stopped`), remove the branch's state file, and the next
  `closure.py step` starts run 2 at `receipt`.
