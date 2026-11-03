---
title: Classify UI lifecycle explicitly before creating a design brief
date: 2026-10-01
problem_type: bug
module: .agents/skills/design-stack/scripts/brief.py, .agents/skills/prd/SKILL.md
tags: [design-stack, onboarding, project-lifecycle, visual-stability]
symptoms: A new UI project with scaffold files was refused as an existing UI, while an existing UI could inherit spatial defaults for rules its owner had not authored.
root_cause: Directory contents were used as a proxy for whether a project already had visual rules; file presence does not encode project lifecycle.
resolution: Callers classify new-ui or existing-ui explicitly; existing UI requires owner choice and authored palette, typography, layout, motion, and accessibility rules.
---

# Classify UI lifecycle explicitly before creating a design brief

This session found that a file-presence check treated a greenfield project with
a README or other scaffold as an existing UI. The corrected onboarding boundary
uses explicit `new-ui` and `existing-ui` kinds (`brief.py:98-114`), and `/prd`
names those kinds even when scaffold files exist (`.agents/skills/prd/SKILL.md:59-69`).
The fixture covers both a scaffolded new UI and an existing UI whose owner
supplied only a partial rule set (`tests/test-design-stack-brief.sh:111-133`).

Use this distinction when a workflow must preserve an existing user's design:
project files are evidence of files, not of whether the owner approved visual
rules.
