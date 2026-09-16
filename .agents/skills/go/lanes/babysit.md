# Lane: babysit

Owned by the go front door. Runs when the goal names a PR (URL or number) and
asks to get it green, address the comments, or clear what is outstanding, or
reports CI red.

1. Read the PR: `gh pr view <n> --comments`, `gh pr checks <n>`. List every open review thread, every requested change, and the status of every check. Read only; tracker task state goes through the registry, never a direct edit
2. `/receive-review` — every review thread, one at a time: verify against the code, then technical acknowledgment or reasoned pushback
3. Read the failing CI logs (`gh run view <id> --log-failed`); quote the first failing assertion or error, not the summary line
4. For a red job: `/debug` with the quoted failure as the reproduction. For a requested change: `/plan` with the review thread as the problem statement. Either stops at its own gate before code
5. `/build` — the rows the previous step wrote
6. `/wrap-up-session` — push to the PR's branch; no new PR

## Reply

Merge-ready, or the one named blocker: which check, which thread, or which
reviewer decision is outstanding and why it could not be closed from here.
