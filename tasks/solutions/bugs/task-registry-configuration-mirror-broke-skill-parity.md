---
title: Task registry configuration mirror broke skill parity
date: 2026-08-30
problem_type: bug
module: .agents/skills/task-registry/references/configuration.md, .claude/skills/task-registry/references/configuration.md
tags: [task-registry, skill-parity, canonical-mirror, rebase]
symptoms: The full suite failed after rebasing PR #78 because the task-registry configuration reference differed across skill trees
root_cause: The task-registry merge carried a repository-specific GitHub example only in the Claude compatibility copy while the canonical copy retained the generic example
resolution: Restored the Claude reference to the canonical generic repository example and verified byte parity through the focused and full suites
---

**Status**: fixed — 2026-08-30
**Regression test**: `tests/test-skill-parity.sh`

During the PR #78 rebase, the controlled focused run reported one mismatch:
`.agents/skills/task-registry/references/configuration.md` used
`repository = my-org/project-name`, while the Claude mirror used
`repository = my-org/ascii-video-pipeline`. Direct blob inspection showed the
mismatch already existed on `origin/master`, ruling out the pstack rebase as its
source (Level 2 Git artifact evidence).

The canonical skill tree is the source of truth, and the parity test enumerates
this reference as a required byte-identical mirror. The compatibility copy now
matches the canonical example (`.claude/skills/task-registry/references/configuration.md:114`).
The focused parity suite passed 69 assertions, and the complete suite passed all
25 test files after the correction.

Related pattern: [A parity `cp` can clobber a legitimate harness divergence](../patterns/a-parity-cp-can-clobber-a-legitimate-harness-divergence.md).
