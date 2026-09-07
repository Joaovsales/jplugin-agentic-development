# Task tracking

> This project's configuration contract, read by `/task-registry`. Declared from
> `.claude/project.md` (Claude Code) and `AGENTS.md` (Pi) — never from
> `CLAUDE.md`, which `/sync` overwrites wholesale. `docs/` is outside every
> syncable root, so what is chosen here survives a template update.
>
> Only the keys this project actually decides are listed. Everything omitted
> takes the shipped default; start from
> `.agents/skills/task-registry/templates/task-tracking.md` for the full
> annotated set.

```ini
[tracker]
provider = github
repository = Joaovsales/jplugin-agentic-development

; A floor, deliberately not lowered. `CLAUDE.md` requires explicit authorization
; for external status changes, so `--apply` alone never writes to the tracker —
; a scheduled routine passes `--approve` too, per run. Setting this false here
; would put that decision in a file instead of in a human.
require_write_approval = true

; ---------------------------------------------------------------------------
; Selection and routing. The label vocabulary below is the one this repository's
; issues actually carry; `kind_precedence` and `[routines.selectors]` are the
; shipped defaults, restated so a vocabulary change is a one-file edit here
; rather than a code edit.
[routines]
claim_label = in-progress
kind_precedence = bug, design-decision, tech-debt, enhancement, documentation

[routines.selectors]
plan = design-decision
fix = bug, tech-debt
improve = enhancement, documentation

; What each routine RUNS. Replaces wholesale, so every selected routine needs a
; chain here. `build` carries one though it is deferred (#97/#98), so
; `task-registry workflow <ref>` can answer "this routine owns your issue and is
; not runnable yet" instead of "no routine owns it" — a different fact, and one
; that should not send a correctly labelled issue back to triage.
[routines.skills]
plan = /plan, /wrap-up-session
fix = /debug, /build, /quality-gate, /wrap-up-session
improve = /plan, /build, /quality-gate, /wrap-up-session
build = /build, /quality-gate, /wrap-up-session
```

## Credentials

None are read from this file. GitHub uses whatever `gh auth status` reports.
