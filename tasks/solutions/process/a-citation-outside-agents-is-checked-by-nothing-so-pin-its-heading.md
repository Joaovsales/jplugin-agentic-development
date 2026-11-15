---
title: A § citation outside .agents/ is checked by nothing, so pin its heading in the test that owns the file
date: 2026-11-13
problem_type: process
module: tests/test-citations.sh, tests/test-solutions-schema.sh, tasks/solutions/README.md, project-template/
tags: [make-it-simpler, one-home, citations, simplify-routine, test-pins]
applies_when: a deduplication replaces restated text in a file under tasks/, project-template/, README.md or specs/ with a `` `/<skill>` § *<Heading>* `` citation
---

## The rule

`tests/test-citations.sh` resolves citations only in Markdown under `.agents/`,
`.claude/agents/` and `AGENTS.md` (its header, "Scope"). A citation written
anywhere else — the store README, its `project-template/` seed — becomes a dead
pointer silently when the cited heading is renamed. When a simplification puts a
citation there, the test that already pins that file must also assert the cited
heading exists in its home (an anchored `assert_file_matches` on the `###` line),
and the citation itself (`assert_prose_contains`).

## What happened

The 2026-11-13 `simplify` run (#387) replaced the overlap-scoring tables in both
store READMEs with `/learn` § *4. Score Overlap Before Writing*.
`tests/test-solutions-schema.sh` § Overlap dimensions gained the heading pin,
because no suite check would have caught a rename. The Phase 4 review also noted
that `/learn`'s headings carry step numbers, which `make-it-simpler/references/safe-moves.md`
practice 1 forbids. Each new citer of a numbered heading makes a later
renumbering cost more. Renaming those headings to plain names belongs in its own
change.
