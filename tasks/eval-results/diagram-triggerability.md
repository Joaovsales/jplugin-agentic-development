# /diagram triggerability — blinded evaluation

Date: 2026-10-19 · Spec: `specs/diagram-skill.md` AC9, risk R1 · Mode A only

## Rubric

Does the harness route an organic request to `jplugin:diagram`, and does it
leave the three neighbouring "make a picture" skills alone? Six prompts, two
repetitions each, graded from the `Skill` tool-use blocks in the transcripts
by `.agents/skills/eval/scripts/grade-skill-loads.sh`. Three prompts should
reach `/diagram`; three should reach `/html-presentation`, `/visual-plan` or
`/html-presentation` again (the "one-page explainer" boundary, D5). Every
prompt carried the no-push clause and a scope limit; none named a skill, a
process or a file the clone lacked.

Candidates ran on Sonnet as fresh `claude -p` sessions, each in its own
`--shared` clone of the build branch at `f30c1c5` (the plugin cache this
session's sub-agents inherit was pinned at 1.6.5, before the skill existed,
so in-harness sub-agents could not see it; the refreshed 1.7.0 cache is what
a fresh process loads). Each clone's `origin` pointed at an invalid URL.

## Mode A — triggerability

| Prompt (abridged) | Target | Rep 1 | Rep 2 | Loaded | Cost |
|---|---|---|---|---|---:|
| "draw me the architecture of this repo's test harness … something I can open in the browser" | `/diagram` | NONE | FIRED | –, `jplugin:diagram` | $0.370 |
| "visualize the flow of install.sh step by step … keep it to the main path" | `/diagram` | NONE | NONE | –, – | $0.306 |
| "archify this: the module tree under .agents/skills/task-registry/scripts" | `/diagram` | FIRED | FIRED | `jplugin:diagram` ×2 | $0.231 |
| "turn these notes into a short HTML report I can send the team" | `/html-presentation` | NONE | NONE | –, – | $0.244 |
| "render specs/tidy-skill.md as a visual plan page" | `/visual-plan` | MISROUTED¹ | MISROUTED¹ | `jplugin:visual-plan` ×2 | $0.209 |
| "make me a one-page explainer on how the task registry picks its provider — conclusion first" | `/html-presentation` | MISROUTED¹ | MISROUTED¹ | `artifact-design` ×2 | $0.562 |

¹ Graded against `jplugin:diagram`; for the three non-target prompts
"MISROUTED" means "loaded a skill other than `/diagram`", which is the
wanted outcome. Total candidate cost: $1.92.

Against `jplugin:diagram`: 3/12 FIRED, 4 MISROUTED, 5 NONE. Read per target:

- `/diagram` prompts: **3/6 fired.** Both "archify this" reps and one
  "draw the architecture" rep loaded the skill, ran the resolver, reported
  Archify absent with the install command and produced nothing (D3 held). The
  other "draw" rep hand-wrote an SVG into an HTML file; both "visualize the
  flow … step by step" reps answered with an ASCII flow in chat. Under-
  triggering, never a wrong skill.
- Neighbouring prompts: **0/6 loaded `/diagram`.** The visual-plan prompt
  routed correctly twice. The HTML-report prompt loaded no skill at all
  (hand-written HTML) and the one-page explainer loaded Anthropic's
  `artifact-design` and published a private artifact — both findings about
  `/html-presentation`'s description, not about this skill, and recorded
  here only as context. R1 (collision with the three picture skills) did not
  occur in twelve runs.

## Synthesis

The misses share a shape: a request phrased as "visualize / draw … the flow,
step by step, something I can open" with no diagram type named, which the
candidates satisfied by drawing in chat or by hand. The original description
listed the verbs but led with the tool and the ten type names. The rewrite
leads with the user's intent ("a picture of how something is built or runs"),
quotes the organic phrasings that missed, says explicitly that a step-by-step
flow or a browser-openable picture with no type named still routes here, and
forbids the three substitutes the misses used (ASCII, Mermaid, hand-written
SVG). "Archify this" and the explicit route-away list are kept.

The rewrite was not re-measured: per D10 this run is information, not a gate,
and the result feeds the wording rather than the merge. There was one judge
(the orchestrator); no second grader, so no disagreement to record.

Recommendation: **rewrite** (applied in the same slice); re-run Mode A after
the next description edit, and open a separate finding for
`/html-presentation`, whose description lost both of its organic prompts here.
