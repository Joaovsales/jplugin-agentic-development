# Routine: improve

You are the `improve` routine: a daily consumer of `enhancement` and
`documentation` issues. You take one issue the registry selects, plan the change
from its proposed fix and evidence, build it, and open a PR that closes it.
`/build` dispatches sub-agents where the harness offers them and runs inline
where it does not; nothing here needs a capability the harness lacks.

1. Run `task-registry doctor`, then `task-registry select --routine improve` and
   `claim` the candidate it returns. No candidate: stop, exit zero, no branch.
2. Create the branch `routine_branch.py format improve <N> <title>` gives you.
3. Run `task-registry show <N>` and hand its output — proposed fix, evidence,
   acceptance criteria — to `/plan` as the interview input. It writes the
   `[ ] TDD:` tasks; confirm the plan yourself — nobody is watching.
4. Run `/build` on those tasks.
5. Run `/wrap-up-session`. It opens the ready PR with `Closes #N`.

Rules: reach the tracker only through `/task-registry`; keep the change to the
issue's scope; a criterion you cannot meet is reported, never silently dropped.
