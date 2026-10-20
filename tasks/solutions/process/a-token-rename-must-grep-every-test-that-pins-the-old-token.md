---
title: A token rename must grep every test that pins the old token
date: 2026-10-19
problem_type: process
module: /slice § Build Order; /build § Slice Close; .agents/skills/slice/scripts/slice.py § cmd_check
tags: [slice, surface, token-rename, doc-pins, quality-gate]
applies_when: a slice renames a command, flag or phrase that documentation tests grep for (`assert_contains`, `assert_precedes`, a `grep -c` pin), and its Surface lists only the documents it rewrites plus the tests the plan named
---

## A token rename must grep every test that pins the old token

**Claim** (this session observed, 2026-10-19): slice 7 of
`specs/github-rest-in-sandboxes.md` (#298) replaced every `gh pr create` in the
wrap-up skill with `gh_pr.py create`. Its Surface named the four documents and
the two tests the plan knew about (`tests/test-routine-wrapup.sh`,
`tests/test-doc-conventions.sh`). A third test, `tests/test-publish-evidence.sh`,
pinned the publisher's position *relative to the old token*
(`assert_precedes "$PR_SECTION" "publish_evidence.py" "gh pr create"`). Every
slice-level check stayed green: the slice's own `Verify` command ran only the two
named tests, and `slice.py check` compares `git diff --name-only <base>..HEAD`
against the Surface (`.agents/skills/slice/scripts/slice.py:519`), so a file the
slice never edited is invisible to it. The pin failed only in the quality gate's
Phase 5 affected run, after the slice had closed with a clean handover, and was
fixed with a `[SURFACE] +tests/test-publish-evidence.sh` line.

**Rule**: before closing a slice that renames a token, grep the old token across
`tests/` (not only the documents) — `grep -rn 'gh pr create' tests/` here — and
either add every hit's file to the slice's Surface at `/slice` time or report it
as a `[SURFACE]` line while the slice is still open. A documentation pin is a
caller of the token, and a rename that misses one caller is the same defect as a
function rename that misses one call site.

**Consequence of ignoring it**: the handover reads "none undeclared, none
untouched" while a test outside the Surface is red; the first run that sees it is
the gate's affected run or the full suite, where the failure is a new regression
with no slice to own it.

Related: [a-tdd-row-test-file-must-sit-inside-its-slice-surface.md](a-tdd-row-test-file-must-sit-inside-its-slice-surface.md)
covers the mirror case — a TDD row naming a test file outside its Surface, which
`slice.py validate` refuses since #291; this document covers a test file the plan
never named at all, which no validator can know about without a token search.
