# Finalizing reviewers regenerates the lane block and discards its completion state

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: route.finalize-discards-lane-completion
kind: bug
spec: none
evidence: `finalized = _demote(...)` then `return _persist_finalized(root, finalized, demotion is not None)` in `finalize_reviewers`, and `if rewrite_lane: todo = _merge_lane(todo, decision, _render_playbook(decision))` in `_persist_finalized` (`.agents/skills/route/scripts/route_issue.py`); `_render_playbook` renders from the decision alone and has no notion of which steps are done, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-05

## Summary

`finalize_reviewers` demotes when the runtime tripwire has not passed, and any
demotion sets `rewrite_lane=True`, which re-renders the `<!-- route-lane -->`
block from the playbook template. The template has no completion state, so every
`[x]` in the checklist reverts to `[ ]`.

Observed on this branch: the lane was fully walked — plan approved, build done,
verification run, reviewers dispatched and finalized, wrap-up complete, PR open
and CI green — and finalizing the reviewers reset all seven items to unchecked.

## Why it matters

The block is two things at once: a tool-managed artifact and the human-readable
record of how far the lane has been walked. Regeneration treats it as purely the
first. The reader after a demotion is told no step has been taken, which is the
opposite of the truth, and re-checking by hand is undone by the next finalize.

The loss is worst in exactly the case that triggers it. A demotion means
something went wrong and the work needs closer human attention — and that is the
moment the record of what has already been reviewed is discarded.

## Acceptance Criteria

- [ ] A demotion that does not change the lane preserves the checklist's completion state
- [ ] A demotion that *does* change the lane states plainly which steps must be re-walked, rather than silently unchecking all of them
- [ ] The distinction is covered in `tests/test-route-decision.sh`

## Notes

Found while running `finalize_reviewers` on this branch at the user's request.
The demotion itself was correct and expected: the tripwire had recorded an
overflow (4 paths outside declared scope) and `_review_demotion` checks
`tripwire_passed` before it looks at reviewer outcomes at all, so the outcomes
could not have avoided it.

Related: the decision's `reviewers` list is fixed at route time, and
`_validate_review_state` requires outcomes to name it exactly — so a reviewer
dispatched later (`critic`, here) cannot be recorded in the decision at all.
