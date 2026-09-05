# A root legitimately emptied upstream disables the whole retirement pass

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.emptied-root-blocks-retirement
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `missing = [r for r in roots if not any(p.startswith(r) for p in template)]` raising `— refusing to retire a root the template cannot vouch for` in `assert_roots_present` (`.agents/skills/sync/scripts/sync-retire.py`); `.agents/git-hooks/` and `.claude/browsers/` each contain exactly one tracked file in this repo, so either is one upstream deletion away from triggering it, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: done
- updated: 2026-09-04

## Summary

`assert_roots_present` conflates two different situations: "the template source is wrong" (a mistyped ref, a bad clone — which it exists to catch) and "a declared root was legitimately emptied upstream". In the second case every downstream Step 6.4 exits 1, retires nothing, and blames the operator's ref.

It also fires *before* `read_keep_patterns`, so a correctly configured project gets no retirement at all until someone edits the template's doc block.

Third distinct case in this family, and covered by none of the existing three: [[sync.retired-root-orphans]] is a root *removed from the block*; [[sync.stale-root-blocks-retirement]] is a *sync-keep pattern* naming a dropped root. This one is a root still declared, present in the project, and empty in the template.

Raised as `owner: human`: the guard is correct to exist and the fix trades one failure mode for another, so the default belongs to a person.

## Acceptance Criteria

- [x] An emptied-but-declared root does not abort retirement for unrelated roots
- [x] A genuinely wrong template source still fails loudly, as today
- [x] The two are distinguishable from the message alone
- [x] `tests/test-sync-retirement.sh` covers both and pins that they are not conflated

## Notes

The strongest form of the critique: the untrusted-template threat model justifies this guard, yet its failure mode is "retirement quietly stops working" — the state this feature was built to end. Found in adversarial review (Pass 4). Related: [[sync.retired-root-orphans]], [[sync.stale-root-blocks-retirement]].

## Resolution

Resolved in the same session it was filed, in **two** steps — the first was reported as complete and was not.

1. An empty declared root is skipped and reported rather than aborting the run, with more than one empty root still refused as a truncated source. Pinned by `tests/test-sync-retirement.sh` §2.
2. That left AC #1 false in the case that matters most. `compute_plan` passed the *scanned* roots to `read_keep_patterns`, so a `sync-keep` line naming a path under the skipped root was "outside every syncable root" — exit 1, every unrelated retirement blocked. A project that had correctly recorded its intent to protect a file was the one most punished for it. Fixed by scoping the pattern check to the **declared** roots, which is what a pattern's legality was always a property of. Pinned by §20.5.

The gap between the two is the lesson: step 1 was verified by the tests written alongside it, and those tests never combined an emptied root with a `sync-keep` naming something under it. Closing on green rather than on the acceptance criterion is what let a false "done" stand — see [[scoping-a-guard-per-item-can-silently-weaken-it]].
