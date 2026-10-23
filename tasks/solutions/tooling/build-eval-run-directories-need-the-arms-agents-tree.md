---
title: A /build eval run directory needs the arm's .agents tree installed, and claude -p cost is cumulative per result event
date: 2026-10-21
problem_type: tooling
module: tests/fixtures/build-eval/ — /eval Mode B comparisons of two plugin versions with claude -p
tags: [eval, claude-p, build, plugin-dir, cost, mode-b]
applies_when: running an A/B comparison of two versions of a workflow skill in throwaway project directories with `claude -p --plugin-dir`, and reading cost from the stream-json output
---

## The trap

`--plugin-dir` loads a version's skills and agents, but the skills call scripts by
project-relative paths (`python3 .agents/skills/slice/scripts/slice.py …`), which
`/sync` installs into a real project. A run directory seeded with only the
feature's code has no `.agents/`, so `/build` finds no `slice.py`, runs inline and
both arms behave the same. This session's first wave of eight runs was discarded
for that reason; nothing in the run's output said a step had been skipped.

## The rule

Install each arm's committed tree into every run directory before the run, as
`/sync` would — `tests/fixtures/build-eval/README.md:48`:

```bash
git -C "$PLUGIN" archive HEAD .agents .claude/agents | tar -x -C "$RUN"
```

Check one transcript per arm for a real `slice.py` call before scoring the wave.

## Reading cost

In `--output-format stream-json`, this session observed `total_cost_usd` to be
cumulative for the session and repeated on every `result` event (a run that
resumes on a background-agent notification emits more than one). Take the last
or largest value per run, never the sum of the events; sum across runs only to
get an arm's total (`README.md:143`). Whether background sub-agent cost is
included could not be confirmed from the stream.

Related: [print-mode skill probes on Windows Git Bash](print-mode-skill-probes-on-windows-git-bash.md).
