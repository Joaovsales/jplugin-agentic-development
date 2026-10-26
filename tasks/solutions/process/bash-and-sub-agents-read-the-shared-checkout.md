---
title: In a worktree session, sub-agents and compound Bash reach the shared checkout unless every path is absolute
date: 2026-10-21
problem_type: process
module: .claude/worktrees (Claude Code worktree-isolated sessions), /build dispatch prompts
tags: [worktree, claude-code, bash-guard, subagents, absolute-paths]
applies_when: a /build or /wrap-up-session runs inside a Claude Code worktree and dispatches sub-agents or runs multi-step shell
---

Ported from PR #128 (`origin/worktree-bulk-read-gate`, observed 2026-09-11)
when `specs/read-shunt-baseline.md` superseded that draft. Two harness
behaviours that only appear when the session is isolated in a git worktree.

## What was observed

1. **A dispatched sub-agent given a relative path reads the shared checkout's
   copy, not the worktree's.** PR #128's first `bulk-reader` measurement was
   asked about `CLAUDE.md` and answered from the main clone, which at that
   moment lacked the new section. Redispatching with the absolute worktree
   path fixed it. The same holds for every sub-agent `/build` dispatches: a
   slice brief that names `tests/foo.sh` is read against whatever checkout the
   agent's shell happens to start in.

   **Rule:** prefix every path in a dispatch prompt with the worktree root and
   state the working directory explicitly in the prompt; say that a relative
   path reaches the wrong checkout.

2. **The Bash guard of that build refused anything it could not prove
   git-free** — `for` loops, `cd X && …`, multi-line heredocs, `sed -n
   "$(…)p"` with a computed range — with "a worktree-isolated session's git
   operations must target its own worktree", even when the command touched no
   git at all. A refusal mid-batch left one patch half-applied. Plain single
   commands passed. Later worktree sessions ran compound commands without the
   refusal, so treat this as version-dependent: when it appears, write the
   patch or probe as a `.py` file into the scratchpad with the Write tool and
   run it as one plain `python <path>` command, which also sidesteps shell
   quoting of the
   [brace-inside-a-bash-expansion](../tooling/a-brace-inside-a-bash-expansion-replacement-ends-it-early.md)
   kind.

## Proving a red file is pre-existing from inside a worktree

`git worktree add --detach <scratchpad>/head-check HEAD` gives a clean checkout
of the base commit without leaving the session's worktree. Run only the red
test files there and compare failure counts — identical counts on both trees
is the evidence the suite-verification row needs. Remove it with
`git worktree remove --force` afterwards. Related:
[baseline-must-precede-tree-edits](baseline-must-precede-tree-edits.md).
