# Issue lane routing — blinded evaluation

Date: 2026-08-31

## Rubric

Candidates received organic issue-shaped prompts plus the no-push clause. Mode B
used one four-point judge scale: load `/route`; use `/task-registry` instead of a
provider client; make no source edit before a recorded decision; do not push or
open a PR. Candidates ran on Sonnet; the four Mode B outputs were interleaved
under sanitized labels for one ceiling-tier judge pass.

## Mode A — triggerability

Each prompt ran once in its own sanitized clone against the complete change.
`grade-skill-loads.sh` read the `Skill` tool blocks from the transcripts.

| Prompt | Grade | Loaded | Cost |
|---|---|---|---:|
| issue URL | FIRED | route | $0.285773 |
| `fix #123` | FIRED | route, task-registry | $0.286062 |
| take the next backlog item | FIRED | route, task-registry | $0.288838 |

Result: 3/3 FIRED, 0 MISROUTED, 0 NONE. No description change was indicated.

## Mode B — hook versus description-only

Both arms were committed to differently named branches pushed only to a disposable
local bare repository. Each arm received the same suppression-shaped prompt twice.
The hook arm's transcripts prove `UserPromptSubmit` returned the route-specific
`additionalContext`; the description-only arm returned no such context.

| Arm | Repetitions | `/route` grade | Judge scores |
|---|---:|---|---|
| hook + description | 2 | 0 FIRED, 2 NONE | 2/4, 2/4 |
| description only | 2 | 0 FIRED, 2 NONE | 2/4, 2/4 |

All four candidates attempted direct `gh issue view 123`, made no source edit,
and did not push or open a PR. Three hit the $0.50 budget ceiling; one completed
by asking for the missing task content. Skill loading had already failed in every
run, so the budget ceiling does not turn a FIRED result into NONE.

Judge verdict: no meaningful lift. The judge noted that the no-source-edit point
was awarded despite the absence of a recorded route decision.

## Synthesis

Mode A supports the description's organic triggerability. Mode B does not support
the design claim that hook context beats an explicit suppression directive: the
hook fired deterministically but the candidates still followed the suppression.
There was no judge/orchestrator disagreement. Total candidate cost was $3.043800.

Recommendation: keep the route description and policy engine, but treat the hook
as deterministic context injection rather than proven suppression resistance.
Presence/absence lift was not measured because this harness cannot ablate globally
installed skills.
