---
title: /plan described the visual plan's review export but no step rendered the page
date: 2026-10-09
problem_type: bug
module: .agents/skills/plan/SKILL.md § 3. Slice the Spec; tests/test-plan-render.sh § wiring
tags: [visual-plan, plan, wiring, skill-steps, test-pins]
symptoms: a /plan run on 2026-10-09 ended with a spec and a build prompt and no specs/<feature>.plan.html, although /plan Step 4 told the user to use the page's Export review and /slice Step 5 named its Not ready panel
root_cause: PR #271 wired plan_render.py into /visual-plan and /system-design-planning Step 6 only, and the wiring pins in tests/test-plan-render.sh looped over exactly those two files, so the history entry's "both planners render through it" was never checked against /plan. Prose that refers to an artifact's features is not a step that produces the artifact
resolution: fixed — 2026-10-09. /plan Step 3 renders the page after /slice, honours /visual-plan's skip gate and prints the Visual written line; every re-run of Step 3 re-renders. Five wiring assertions pin the step inside Step 3 and after the /slice call
---

**Status**: fixed — 2026-10-09
**Regression test**: `tests/test-plan-render.sh` § wiring — the `/plan Step 3 …` assertions

## Prevention

When a skill's prose refers to a generated artifact (a page, a report, a receipt),
grep that skill for the command that writes it. A wiring test should list every
consumer the change set claims to cover, not just the ones it edited.
