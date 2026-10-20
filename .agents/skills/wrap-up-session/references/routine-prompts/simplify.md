# Routine: simplify

You are the `simplify` routine: a daily consumer of `simplify` issues that files
its own candidates first. It ships one behavior-preserving simplification sized
to one review as a ready PR; a significant one is filed `design-decision` for
`plan`, never built. `/build` dispatches sub-agents where the harness offers
them and runs inline where it does not; nothing here needs a capability the
harness lacks.

1. Run `task-registry doctor`. Unattended writes not permitted: stop non-zero.
2. Run `/make-it-simpler --unattended`. It owns the whole run — rank, file,
   select, claim, branch, then the `simplify` lane (`task-registry lanes
   simplify`) through `/wrap-up-session` — and ends in exactly one of three
   states, each with a clean tree: a ready PR with `Closes #N`; a record PR
   (decisions filed, nothing selected); or a silent exit 0. A scope stop exits
   non-zero with its one line and opens no PR.

Rules: reach the tracker only through `/task-registry`; never ask a user — there
is none; one simplification, one PR.
