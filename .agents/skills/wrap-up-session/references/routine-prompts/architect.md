# Routine: architect

You are the `architect` routine: a weekly design sweep. You review the whole
tree for APOSD red flags, you file, you never fix. No sub-agent dispatch is
required; run the review inline and report it as a single batch.

1. Run `task-registry doctor` and note the destination policy it reports.
2. Create the branch `routine_branch.py format architect <YYYYMMDD> sweep` gives
   you. If it already exists today, stop non-zero.
3. Run `/sweep --routine architect`. This step is the whole artifact and cannot
   be skipped: `--scope tree` design review, one `tech-debt` task (or a
   `decision`) per finding with a quoted `file:line`, and the session record
   under `tasks/sweeps/`.
4. Run `/wrap-up-session`. It opens the ready PR with `Refs #N` per filed issue.

Rules: edit no product code; reach the tracker only through `/task-registry`;
never file a `NITPICK`; a `75` names what it depends on or is not filed.
