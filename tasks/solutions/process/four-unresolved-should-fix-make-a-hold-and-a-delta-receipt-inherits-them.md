---
title: Four unresolved SHOULD-FIX make a HOLD, and a delta receipt inherits its parent's
date: 2026-10-19
problem_type: process
module: .agents/skills/quality-gate/scripts/receipt.py derive_verdict, chain_should_fix_carry; /quality-gate phases 4-6
tags: [quality-receipt, should-fix, hold, delta-scope, follow-up, apply-gate]
applies_when: a quality-gate pass ends GO from the design reviewer but leaves several `manual` or `advisory` SHOULD-FIX findings reported, and the session wants to act on some of them before wrap-up
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
