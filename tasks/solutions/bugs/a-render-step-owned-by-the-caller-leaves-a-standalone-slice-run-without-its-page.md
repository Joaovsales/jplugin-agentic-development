---
title: A render step owned by the caller leaves a standalone /slice run without its page
date: 2026-10-21
problem_type: bug
module: .agents/skills/slice/SKILL.md § Propose, Step 6; .agents/skills/plan/SKILL.md § 3. Slice; tests/test-plan-render.sh § wiring
tags: [visual-plan, slice, plan, wiring, skill-steps, ownership]
symptoms: a `/slice specs/test-suite-aposd.md` run on 2026-10-21, started from a button reply rather than through `/plan`, wrote § Build Order, the plan block and the build prompt but no `specs/<feature>.plan.html`; the user asked why no visual plan was created and whether the plugin was outdated
root_cause: PR #282 put the render in `/plan` Step 3, after its `/slice` call, so only that one caller rendered. `/slice` is also run on its own — the change-request loop ("edit the spec, re-run `/slice`") and any direct invocation — and every such run left the page absent or trailing the spec. The installed plugin (1.6.2) carried #282; the version was not the cause
resolution: fixed — 2026-10-21. `/slice` renders the page itself as propose Step 6, after the readiness gate and under `/visual-plan`'s skip gate, and names it in its required output; `/plan` Step 3 is the `/slice` call alone. `/system-design-planning` Step 6 keeps its render because it re-renders after the self-review and critic edits. The wiring pins moved to `/slice`'s propose section, with a negative pin that `/plan` Step 3 renders nothing
---

**Status**: fixed — 2026-10-21
**Regression test**: `tests/test-plan-render.sh` § wiring — the `/slice's propose phase renders …` assertions and `/plan Step 3 renders nothing itself`

## Prevention

A derived artifact belongs to the step that writes its source. When skill A
writes a file and a later step in skill B renders it, every entry point that
writes the file has to reach the render, and a skill with more than one caller
never does: put the render where the file is written. The check is mechanical —
list the skill's callers and standalone uses and ask which of them reach the
derived step; any that do not is this defect.

Related: [plan-described-the-visual-plan-but-never-rendered-it.md](plan-described-the-visual-plan-but-never-rendered-it.md)
added the step this learning moves. The two overlap on the page and the files,
not on the cause: there the render had no step at all; here it had one, owned
by the wrong skill.
