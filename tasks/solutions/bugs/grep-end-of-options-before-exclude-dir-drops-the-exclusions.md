---
title: grep `--` placed before --exclude-dir silently drops the exclusions
date: 2026-09-07
problem_type: test-failure
module: tests/test-sweep-routines.sh
tags: [bash, grep, sweeps, tests, retired-files]
symptoms: "the AC9 retired-needle sweep in tests/test-sweep-routines.sh listed specs/ and tasks/ files as hits even though the command named `--exclude-dir=specs --exclude-dir=tasks`; the sweep looked correctly scoped and was not"
root_cause: "`grep -rlF -- \"$needle\" . --exclude-dir=specs …` puts `--` before the exclude flags. `--` ends option parsing, so every `--exclude-dir=` after it is read as a file operand. Those operands do not exist, grep reports them on stderr (which the test discarded with 2>/dev/null), and the recursive walk of `.` runs with no exclusions at all"
resolution: "move `--` to the end of the option list, immediately before the needle (tests/test-sweep-routines.sh:214-219), with a comment stating why the order matters"
---

**Status**: fixed — 2026-09-07

## Symptoms

`bash tests/test-sweep-routines.sh` failed AC9 with a hit list that included
`specs/sweep-routines.md` and `tasks/todo.md` — exactly the directories the
command excluded by name. The needle itself was correct (built at runtime, see
the linked pattern), and the exclusion flags were spelled correctly.

## Root cause

GNU grep treats `--` as the end of options. Anything after it is a pattern or
file operand, never a flag. The original line was:

```bash
grep -rlF -- "$retired" . --exclude-dir=.git --exclude-dir=tasks --exclude-dir=specs
```

so grep searched `.` recursively and then tried to open files literally named
`--exclude-dir=.git`, `--exclude-dir=tasks`, and so on. Each produced a
"No such file or directory" on stderr, which `2>/dev/null` hid, and the walk of
`.` proceeded with zero exclusions.

The failure mode is quiet by construction: the command exits 0 with a plausible
list, and the only diagnostic is on the stream that a `-l` sweep conventionally
discards.

## Resolution

All options first, then `--`, then the needle, then the paths
(`tests/test-sweep-routines.sh:214-219`). The comment above the command records
the ordering rule so a later edit does not reintroduce it.

## Prevention

- In any `grep -r` that mixes `--exclude-dir` with `--`, the `--` goes last.
- Do not discard stderr on a sweep whose result gates a test; if it must be
  discarded, assert on a known-excluded path once to prove the exclusions
  actually apply.

Related: `../patterns/construct-retired-paths-at-runtime-to-keep-literal-sweeps-strict.md`
(the needle construction this sweep uses) and
`grep-zero-matches-aborts-hooks-under-set-e-pipefail.md` (the other quiet grep
exit-status trap in this repo's shell tests).
