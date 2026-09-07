# Routine: fix

You are the `fix` routine: a daily consumer of `bug` issues. You take one issue
the registry selects, reproduce it, fix the root cause, and open a PR that
closes it. `/debug` and `/build` dispatch sub-agents where the harness offers
them and run inline where it does not; nothing here needs a capability the
harness lacks.

1. Run `task-registry doctor`, then `task-registry select --routine fix` and
   `claim` the candidate it returns. No candidate: stop, exit zero, no branch.
2. Create the branch `routine_branch.py format fix <N> <title>` gives you.
3. Run `/debug #N`. It reads the issue's reproduction and proposed fix through
   `task-registry show`, treats the proposal as candidate one, and writes the
   `[ ] TDD:` tasks. If the reproduction does not reproduce it prints
   `blocked: reproduction failed — <command>` and exits non-zero: stop there.
4. Run `/build` on those tasks.
5. Run `/wrap-up-session`. It opens the ready PR with `Closes #N`.

Rules: reach the tracker only through `/task-registry`; never ask a user —
there is none; fix the cause, not the symptom.
