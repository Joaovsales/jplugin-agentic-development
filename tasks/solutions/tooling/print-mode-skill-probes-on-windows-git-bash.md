---
title: Print-mode skill probes on Windows Git Bash need MSYS_NO_PATHCONV, PYTHONUTF8 and an isolated CLAUDE_CONFIG_DIR
date: 2026-09-21
problem_type: tooling
module: claude -p e2e probes — /eval Mode A and /verify-evidence --scope e2e for skill routing
tags: [windows, git-bash, claude-p, eval, e2e, plugin-dir]
applies_when: running `claude -p "/skill ..."` sessions from Git Bash to prove that a typed command routes or that a skill fires, and grading the result from transcripts
---

## The setup this session used

`claude -p "<prompt>" --plugin-dir <worktree> --output-format json
--max-budget-usd 1.50`, cwd a project-shaped scratch worktree, the plugin loaded
from the worktree under test so the new skills are the ones measured. Verdicts
are read from the session `.jsonl`: the first user turn (`<command-name>` shows
the harness routed a typed command), the `Skill` tool-use blocks (which skills
loaded), and `Edit`/`Write` blocks (what was written). Never grade from what the
session says about itself.

## Three things that silently break it on this machine

1. **Path conversion rewrites the prompt.** Git Bash turns `/grill-me …` into
   `C:/Program Files/Git/grill-me …` before `claude` sees it. Export
   `MSYS_NO_PATHCONV=1` and pass Windows-form paths for `--plugin-dir` and
   `CLAUDE_CONFIG_DIR`.
2. **Non-ASCII output kills the grader.** Python prints to cp1252 here; a grader
   that echoes `❓`, `➡️` or an em dash dies with `UnicodeEncodeError`, and a
   grader that dies mid-print reads as "no hits". Export `PYTHONUTF8=1` first.
3. **User-scope skills and installed plugins contaminate routing.** Point
   `CLAUDE_CONFIG_DIR` at a directory holding only credentials, so the only
   `/name` that can resolve is the one under `--plugin-dir`. Without it a probe
   can pass by loading the installed copy of an old skill.

## Cost and blinding

This session observed $1.2–2.6 per session of two to sixteen turns under a
`--max-budget-usd 1.50` cap per invocation; a six-session Mode A run cost $7.31.
No eval vocabulary in any path or prompt, and the sessions were never told they
were measured. The Workflow tool's sanitized-worktree fan-out from
`.agents/skills/eval/references/probe-recipe.md` was not used; six print-mode
sessions launched together stood in for it.

## Related

- [settings-declared-plugin-installs-at-trust-and-leaves-only-the-cache.md](settings-declared-plugin-installs-at-trust-and-leaves-only-the-cache.md)
  — the install side of the same plugin; this document is the probe side.
- [../process/windows-suite-failures-compare-against-a-clean-head-worktree.md](../process/windows-suite-failures-compare-against-a-clean-head-worktree.md)
  — the same cp1252 class of failure inside the test suite.

## User-scope skill copies win over project-local ones (2026-09-22)

The AC 15 walkthrough for `specs/plan-slices-and-handover.md` ran two `claude -p`
sessions in a fixture repository that carried the branch's skills under
`.claude/skills/` and `.agents/skills/`, with the default `CLAUDE_CONFIG_DIR`.
Both sessions' `Skill` results named `~/.claude/skills/plan`, `…/build`,
`…/quality-gate` and `…/wrap-up-session` as the base directory — the installed,
pre-branch copies — and only `slice`, which had no user-scope copy, resolved to
the fixture's `.claude/skills/slice`. Each session noticed the vocabulary
mismatch against its arguments, read the project-local `SKILL.md` with `cat` or
`Read`, and followed it, so the run still exercised the text under test; but the
routing was the agent's judgement, not the harness's.

Grade which copy loaded from the transcript: the skill-injection user turn
carries `Base directory for this skill: <path>`. A run that is meant to prove a
project-local skill fires must use the isolated `CLAUDE_CONFIG_DIR` described
above, or the user-scope copy is what fires. This is the inverse of the earlier
observation that a project-level `.claude/` shadows `~/.claude/` — under Claude
Code 2.1.277 with skills installed at user scope, the user-scope copy loaded.
