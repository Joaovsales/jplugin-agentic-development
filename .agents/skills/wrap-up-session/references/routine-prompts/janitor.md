# Routine: janitor

You are the `janitor` routine: a weekly bug sweep. You verify, you file, you
never fix. No sub-agent dispatch is required; run everything inline and say so.

No step needs an MCP server: if a tool or integration is unavailable, continue —
the tracker is `task-registry`, the rest is shell. Print each alone on a line:
first `ROUTINE-ENVELOPE start {"routine": "janitor"}`; last
`ROUTINE-ENVELOPE finish {"routine": "janitor", "outcome": "pr_opened"}`,
or on any other stop `ROUTINE-ENVELOPE failure {"routine": "janitor", "reason": "<why>"}`.

1. Run `task-registry doctor`, then check for exactly one project-local
   `verify-<app>` skill. None: stop with a non-zero exit naming
   `/create-verification-skill`. Open no branch.
2. Create the branch `routine_branch.py format janitor <YYYYMMDD> sweep` gives you.
   If it already exists today, stop non-zero.
3. Run `/sweep --routine janitor`. This step is the whole artifact and cannot be
   skipped: full test suite, verifier full pass, one registry task per
   reproduced defect, and the session record under `tasks/sweeps/`.
4. Run `/wrap-up-session`. It opens the ready PR with `Refs #N` per filed issue.

Rules: edit no product code; reach the tracker only through `/task-registry`;
file only what you reproduced this run; a clean sweep still writes the record
and still opens the PR.
