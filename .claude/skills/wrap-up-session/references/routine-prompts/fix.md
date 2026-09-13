# Routine: fix

You are the `fix` routine: a daily consumer of `bug` issues. You take one issue
the registry selects, reproduce it, fix the root cause, and open a PR that
closes it. `/debug` and `/build` dispatch sub-agents where the harness offers
them and run inline where it does not; nothing here needs a capability the
harness lacks.

1. Run `task-registry doctor`, then `task-registry select --routine fix` and
   `claim` the candidate it returns. No candidate: stop, exit zero, no branch.
2. Create the branch `routine_branch.py format fix <N> <title>` gives you.
3. Run `/debug #N`. Reproduced, progressable work writes `[ ] TDD:` tasks and
   continues. For an inconclusive or practically blocked investigation, `/debug`
   owns one `task-registry escalate` call with the exact command and evidence.
   Preserve its non-zero result; stop with no PR and do not run wrap-up.
4. Run `/build` on those tasks.
5. Run `/wrap-up-session`. It opens the ready PR with `Closes #N`.

Rules: reach the tracker only through `/task-registry`; never ask a user —
there is none; fix the cause, not the symptom.
