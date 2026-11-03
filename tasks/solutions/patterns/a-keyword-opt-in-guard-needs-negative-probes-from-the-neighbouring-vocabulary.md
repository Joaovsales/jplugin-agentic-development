---
title: A keyword opt-in guard needs negative probes from the neighbouring vocabulary
date: 2026-10-16
problem_type: pattern
module: .agents/skills/design-stack/scripts/hyperframes.py § should_run_hyperframes; three.py § should_run_three
tags: [design-stack, guard, opt-in, regex, tests, quality-gate]
applies_when: a guard decides by matching words in free task or brief text whether to opt a task into an expensive or side-effectful pipeline (video, 3D, deploy)
---

## A keyword opt-in guard needs negative probes from the neighbouring vocabulary

**Pattern**: a word that names the pipeline's output inside its own domain is
often an everyday verb in the host domain. The first HyperFrames guard matched
`render` and `explainer`, so "Fix the re-render flicker on hover" and "Add an
explainer tooltip" opted ordinary UI work into the video pipeline; the brief
path matched the same terms with no negation, so a Motion rule mentioning an
existing background video opted every task on the project in. The quality
gate's design review caught it (2026-10-16); the spec's own AC5 probes were all
drawn from the video domain and passed.

**Rule**: before the opt-in regex ships, write the negative probes from the
*neighbouring* vocabulary the guard will actually see — the host domain's common
verbs that share a stem (`render`, `explainer`), and a mention of the thing
being *present* rather than *requested* ("keeps the looping background video").
Keep one `_mentions(term, text)` helper that carries the negation window
(`.agents/skills/design-stack/scripts/hyperframes.py:7-20`) and run every text
path through it; a second bare `re.search` for the brief is a second, weaker
definition of the same word. Record the vocabulary as a spec decision (D10 in
`specs/design-stack-hyperframes.md`) so the next source does not re-argue it.

**Consequence of ignoring it**: `/build` runs the pipeline on unrelated tasks and
reports `prototype` gates nobody asked for, and a project-wide brief rule turns a
task-level opt-in into a permanent one.

Related: [scoping-a-guard-per-item-can-silently-weaken-it](../process/scoping-a-guard-per-item-can-silently-weaken-it.md).
