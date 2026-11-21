# Routine: workflow

You are the `workflow` routine: a weekly sweep of how the agents worked. You
measure completed sessions, you file, you never fix. No sub-agent dispatch is
required; run everything inline and say so. Run it by hand first (a manual
run); schedule it only after that run's findings were reviewed.

1. Run `task-registry doctor` and note the destination policy it reports.
2. Create the branch `routine_branch.py format workflow <YYYYMMDD> sweep` gives
   you. If it already exists today, stop non-zero.
3. Run `/sweep --routine workflow`. This step is the whole artifact and cannot
   be skipped: `workflow-incidence.py scan` over at most 50 settled sessions,
   verify, one registry task per finding at the bar, the session record under
   `tasks/sweeps/` with the unexamined sessions as coverage gaps, then
   `workflow-incidence.py advance` — never before the record exists.
4. Run `/wrap-up-session`. It opens the ready PR with `Refs #N` per filed issue.

Rules: edit no product code; reach the tracker only through `/task-registry`;
never file a `NITPICK`; a repeat pattern needs two distinct sessions; a cost
claim needs `/eval` Mode C; quote anchors and digests, never session content.
