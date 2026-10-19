---
title: Sub-agents inherit the session-start plugin roster, so eval a new skill in fresh processes
date: 2026-10-19
problem_type: tooling
module: /eval Mode A; .agents/skills/eval/scripts/grade-skill-loads.sh; the jplugin plugin cache under ~/.claude/plugins/cache
tags: [eval, triggerability, plugin-cache, sub-agent, claude-p, roster]
applies_when: a session adds or renames a skill and wants to measure whether the harness routes to it (/eval Mode A, spec AC9-style triggerability runs) before the plugin is reinstalled
---

## The claim

Claude Code serves `jplugin` skills from the plugin cache
(`~/.claude/plugins/cache/jplugin-agentic-development/jplugin/<version>/`), not
from the working tree, and a session's skill roster is a snapshot taken when
the session starts. Every sub-agent the `Agent` tool spawns inherits that
snapshot. On 2026-10-19 a probe agent spawned after `/diagram` had been written
and committed listed `jplugin:html-presentation`, `jplugin:visual-plan` and
`jplugin:visual-recap` — and no `jplugin:diagram`. Even after
`claude plugin update jplugin@jplugin-agentic-development` refreshed the cache
to 1.7.0 (`Restart to apply changes`), a second probe sub-agent still saw the
old roster.

A fresh process does see it: `claude -p` started after the update listed
`jplugin:diagram` first.

## The rule

To eval a skill that did not exist when the session began:

1. Bump the plugin version (the version guard requires it anyway) and run
   `claude plugin update jplugin@jplugin-agentic-development` so the cache
   holds the new tree.
2. Run every candidate as a fresh `claude -p "<organic prompt>" --model sonnet
   --output-format stream-json --verbose --permission-mode bypassPermissions`
   process in its own `git clone --shared` of the branch with `origin` set to
   an invalid URL. The stream-json transcript carries the `Skill` tool-use
   blocks `grade-skill-loads.sh` parses; name each transcript
   `agent-<label>.jsonl` and grade against the loaded name as the tool
   records it (`jplugin:diagram`, not `diagram`).
3. Cut the clones from the branch under test, not `origin/master`, when the
   skill's own scripts must exist for the candidate to get past the resolver;
   say so in the report.

`.agents/skills/eval/references/probe-recipe.md` shows the Workflow-tool shape
of the same run; this is the shape that works when the Workflow tool is not
authorised or the roster is stale.

## The consequence of ignoring it

Twelve in-harness candidates would all grade `NONE` for a skill they cannot
see, and the description defect the eval exists to find would be reported as
"never fires" with the wrong cause. Related:
[in-the-template-repo-follow-the-repos-skills-not-the-plugin-cache.md](in-the-template-repo-follow-the-repos-skills-not-the-plugin-cache.md)
(the parent session reading the cache rather than the tree) and the report
`tasks/eval-results/diagram-triggerability.md`.
