# Debug skill run: reproduced and fixable

- Result: **PASS**
- Isolated repository: `/tmp/routine-skill-reproduced`
- Branch: `routine/fix/verification-reproduced`
- Task: `bug.normalized-name-whitespace`
- Skill executed: `.agents/skills/debug/SKILL.md`

## Reproduction and verification

The task's reproduction was run verbatim before any defect edit:

```text
cd verification_fixture && python3 test_name_tools.py
before fix: exit 1
after fix:  exit 0
```

Before the fix, `test_trims_and_lowercases_name` reported
`'  alice  ' != 'alice'`. After the minimal root-cause edit it ran one test and
reported `OK`. The repository suite, `bash tests/run.sh`, subsequently exited 0
with `RESULT: all 42 test files passed`.

## Required debug prelude

Reproduction confirmed: **YES** — the issue's exact command deterministically
failed before the edit.

1. `normalized_name` omitted whitespace stripping in
   `verification_fixture/name_tools.py:2`.
   Supporting evidence: the controlled failing test and direct evaluation of
   `.lower()` preserving spaces (Level 1).
   Disconfirming check: `.strip().lower()` returned exactly `alice`.
2. The regression test encoded the wrong contract.
   Supporting evidence: the only mismatch was the expected trimmed value
   (Level 4).
   Disconfirming check: the task title, reproduction, proposed fix, and acceptance
   criterion all explicitly require trimming.
3. Python imported a shadow module rather than the fixture implementation.
   Supporting evidence: the repository has a minimal new module (Level 5).
   Disconfirming check: `name_tools.__file__` resolved to
   `/tmp/routine-skill-reproduced/verification_fixture/name_tools.py`.

Picked candidate 1 because candidates 2 and 3 were directly disproved. The root
cause was the implementation's missing `strip()` call. The fix changed
`value.lower()` to `value.strip().lower()` and retained the failing test as the
regression test. Phase 4 recorded the isolated bug document and issue-intake TDD
row; the trivial fixture revealed no broader reusable pattern.

## Routine outcome

The actual skill decision was **Reproduction confirmed; continue the normal fix
path**. It did not invoke `task-registry escalate`.

The fresh final task read reported:

```text
status: open
labels: bug
external: local:bug.normalized-name-whitespace
```

`needs-investigation` is absent. `tasks/routine-runs` contains 0 files and has 0
git changes. The post-fix selector exited 0 and returned the parent:

```text
candidate:     bug.normalized-name-whitespace — Normalize surrounding username whitespace
matched label: bug
claim label:   in-progress — write it with `task-registry claim bug.normalized-name-whitespace --routine fix --apply --approve` before branching
remaining:     0 other candidate(s) in this pool
```

No commit or push was made.
