---
title: Port master's edits onto the successor surface when a branch retires the one master edited
date: 2026-09-22
problem_type: pattern
module: merge resolution — AGENTS.md managed block, README skills table, .agents/hooks/
tags: [merge-conflict, retired-surface, agents-md, readme, hooks, sync]
applies_when: Merging the base branch into a branch that deleted, moved or made generated a file the base branch kept editing — a rules file, a catalog table, a hook script, a banner list
---

## Pattern

A branch that retires a surface (deletes `.claude/project.md`, reduces `CLAUDE.md`
to `@AGENTS.md`, moves `.claude/hooks/*.sh` to `.agents/hooks/`, turns the README
skills table into generated output) will conflict with every PR merged to master
in the meantime that edited the old surface. Neither conflict side is right:
"ours" drops master's content, "theirs" resurrects the retired file.

Resolve in three moves, per conflicting file:

1. **Take the branch side** of the conflict so the retired surface stays retired
   (`git checkout --ours -- <file>`).
2. **Read master's hunk for that file** (`git diff <merge-base> origin/master -- <file>`)
   and re-express it on the successor surface: rules text goes into the AGENTS.md
   managed block, a banner line is dropped when the banner no longer lists skills,
   a hand-written table row is replaced by re-running the generator
   (`python3 scripts/render-skills-table.py`).
3. **Grep master's whole diff for the retired paths**, not only the conflicting
   files — clean auto-merges are where the stale references hide. This session
   found four: a `.claude/hooks/pre-compact.sh` call in `/build`'s slice close, a
   `.claude/hooks/session-start.sh` inventory count in `slice/references/sizing.md`,
   a `CLAUDE.md` skills-table pin and a § Workflow pin on `CLAUDE.md` in
   `tests/test-doc-conventions.sh`.

```bash
git diff --name-only <merge-base> origin/master \
  | xargs grep -nE 'CLAUDE\.md §|\.claude/project\.md|\.claude/hooks/|~/\.claude/CLAUDE\.md'
```

Then run the tests that guard the successor surface (`test-instruction-budget`,
`test-citations`, `test-skills-table`, `test-hooks-json`, `test-doc-conventions`)
before the merge commit, and check the block budget the successor carries
(`AGENTS.md` block ≤ 200 lines, file ≤ 16 KiB) — master's prose was written for a
file with no budget.

## Also check the other direction

Master may have tightened a contract the branch's own files violate. PR #176's
`registry/globs.py` accepts only `*`, `?` and `**`; this branch's spec frontmatter
used `{a,b}` brace groups, and `spec-reconcile.py discover` refused the whole run
until they were expanded. See [[spec-implementation-paths-accept-only-star-question-and-double-star]].

Related: [[readme-skill-table-merge-conflict]] — the hand-resolved form of the
README conflict this pattern replaces.
