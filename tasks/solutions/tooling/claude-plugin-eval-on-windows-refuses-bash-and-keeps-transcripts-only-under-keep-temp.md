---
title: claude plugin eval on Windows refuses a Bash grant and keeps the session transcript only under --keep-temp
date: 2026-10-21
problem_type: tooling
module: claude plugin eval (Claude Code 2.1.306); evals/read-shunt; .agents/skills/eval/scripts/grade-read-shunt.py; .agents/skills/eval/scripts/arrange-plugin-eval-results.py
tags: [eval, claude-plugin-eval, windows, sandbox, transcripts, keep-temp, max-cost-usd]
applies_when: running `claude plugin eval` on this Windows machine, or grading what a run left behind with a transcript-reading grader
---

## What the runner does here

Observed on 2026-10-21 while running the read-shunt suite's smoke case
(`tasks/eval-results/read-shunt/smoke-2026-10-21.md`):

- **A `Bash` grant is refused before any turn runs.** `--allow-tools Bash Edit Write`
  ends with "Sandbox required but unavailable … Windows sandbox is not active"
  after 0 turns and about $0.0005 of judge cost. Drop `Bash` from the grant on
  Windows (`evals/read-shunt/README.md` § *Run* says so); a case that needs shell
  routing-around to show cannot run here.
- **The results directory is not the transcript.** `evals/<suite>/results/<ts>/`
  holds `aggregate-result.json` and `report.html` only. The session transcript
  survives only with `--keep-temp`, under the temp home
  `<TEMP>/claude-eval-<id>/`: `out/trace.jsonl` is stream-json (`parent_tool_use_id`,
  `tool_use_result`, `result`), and `config/projects/<encoded cwd>/<session>.jsonl`
  is the ordinary session shape `read_transcript.py` pins. Copy the latter into
  the grader's layout and remove the temp home afterwards.
- **One paid run means `--ablation none`.** The default `with-without` ablation
  runs a second, plugin-less arm. `--max-cost-usd` exits 2 on breach and is
  required on every paid run in this repository; `--trust-plugin` is needed when
  started from a session.

## The rule

Grade from the kept session JSONL, never from `aggregate-result.json`'s score
alone: the score says whether the case passed, the transcript says what the
agent read. Run with `--keep-temp`, then
`arrange-plugin-eval-results.py <TEMP> <aggregate-result.json> --arm <name> --out <results>`
builds `<results>/<arm>/<task>/run-<n>/{transcript.jsonl,outcome.json}` from the
kept homes (`tracePath` names each run's) and the aggregate's `score` / `passed`;
it refuses to write anything when a home is gone or a run directory exists.

Related: [print-mode-skill-probes-on-windows-git-bash](print-mode-skill-probes-on-windows-git-bash.md)
covers the `claude -p` path the same graders read; the sandbox refusal is new to
`claude plugin eval`.
