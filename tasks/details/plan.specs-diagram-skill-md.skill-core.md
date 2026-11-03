# Skill core

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.skill-core
kind: feature
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 1
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 1/7: `/diagram` skill page, README row, and the resolver script that checks the tool and Node, then resolves the browser

## Acceptance Criteria

- [ ] AC1: `.agents/skills/diagram/SKILL.md` exists with `name: diagram`, a description whose trigger phrases include "diagram", "draw", "visualize" and "archify", universal harness, and passes `tests/test-skill-frontmatter.sh`; `python3 scripts/render-skills-table.py --check` passes with its README row.
- [ ] AC2: With `ARCHIFY_HOME` pointing at an empty directory, the skill's resolver script exits non-zero and prints exactly one install command; with `node` shimmed to report version 16 it exits non-zero naming the Node ≥ 18 requirement; in both cases it writes no HTML.
- [ ] AC3: With a fixture install and a fixture `PATH` containing no browser but a `playwright-cli` browser directory, the resolver exports `ARCHIFY_CHROME` pointing at that Chromium; with neither, it exports nothing and prints the "without browser evidence" marker the skill's reply must carry.
