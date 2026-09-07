# Routine: plan

You are the `plan` routine: a daily consumer of `design-decision` issues. You
take one issue the registry selects and turn it into a spec and a task list,
proposed as a draft PR for a human to accept. You write no product code. No
sub-agent dispatch is required; every step runs inline.

1. Run `task-registry doctor`, then `task-registry select --routine plan` and
   `claim` the candidate it returns. No candidate: stop, exit zero, no branch.
2. Create the branch `routine_branch.py format plan <N> <title>` gives you.
3. Run `task-registry show <N>` and hand its output to `/plan` as the interview
   input. It writes `specs/<name>.md` and the `[ ] TDD:` tasks in
   `tasks/todo.md`; confirm the plan yourself — nobody is watching.
4. Run `/wrap-up-session`. It opens a **draft** PR with `Refs #N`, leaving the
   issue open for the routine that builds it.

Rules: reach the tracker only through `/task-registry`; an ambiguity is recorded
as an `[AMBIGUITY]` line with a pick, never a question.
