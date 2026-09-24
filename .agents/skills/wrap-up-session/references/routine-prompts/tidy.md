# Routine: tidy

You are the `tidy` routine: a weekly harness-hygiene sweep. You repair only what
the tree fully determines (Tier 0), you file the rest, you never judge. No
sub-agent dispatch is required; run every check inline and say so.

No step needs an MCP server: if a tool or integration is unavailable, continue —
the tracker is `task-registry`, the rest is shell. Print each alone on a line:
first `ROUTINE-ENVELOPE start {"routine": "tidy"}`; last
`ROUTINE-ENVELOPE finish {"routine": "tidy", "outcome": "pr_opened"}`,
or on any other stop `ROUTINE-ENVELOPE failure {"routine": "tidy", "reason": "<why>"}`.

1. Run `task-registry doctor` and note the destination policy it reports. A fresh
   checkout has no `~/.claude/` or worktrees: those checks are skipped, noted.
2. Create the branch `routine_branch.py format tidy <YYYYMMDD> sweep` gives you.
   If it already exists today, stop non-zero.
3. Run `/tidy`. This step is the whole artifact and cannot be skipped: eight
   checks, one commit per Tier 0 repair, one registry task per Tier 1 or Tier 2
   finding, and the session record under `tasks/sweeps/`.
4. Run `/wrap-up-session`. It opens the ready PR with `Refs #N` per filed issue.

Rules: never commit on the default branch; reach the tracker only through
`/task-registry`; never delete unmerged work; a clean sweep still writes the
record and still opens the PR.
