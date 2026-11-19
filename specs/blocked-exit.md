---
implementation_paths:
  - .agents/skills/slice/scripts/slice.py
  - .agents/skills/slice/references/plan-block.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/build/references/harness-dispatch.md
  - tests/test-slice.sh
  - tests/fixtures/slice/ready-blocked/**
  - tests/test-doc-conventions.sh
---

# Spec: Blocked exit for a slice that cannot be built

> Origin: #440 (esf adoption — mitkox/esf @ e5567fb, `docs/adr/0007-defense-in-depth.md` § 3, BLOCKED is a first-class outcome)

## Summary

A Builder that cannot satisfy a slice as specified has an honest way to stop: it
emits one `[BLOCKED]` line. `/build` ends that slice blocked with no retry and no
`[x]`, writes the reason under the slice heading as a `> Blocked:` line, and
`slice.py ready` keeps the blocked slice and every slice that waits on it out of
the ready set, so independent slices still build and the impossible one is never
re-dispatched.

## Behavior

Every dispatch that serves a slice — the coder and each `code-debugger` attempt —
carries the blocked exit in its prompt: when the slice cannot be done as
specified (a contradictory acceptance criterion, a missing dependency or
credential, a surface that cannot hold the change), the agent stops and returns
one line, and BLOCKED is an acceptable result. Deleting or weakening a test,
mocking the thing under test, or editing outside the Surface to get green is not.

```
[BLOCKED] <reason> | tried: <what was attempted> | needs: <what would unblock it>
```

When a dispatch returns a `[BLOCKED]` line, `/build`:

1. copies it verbatim into `tasks/todo.md` under the slice's heading as
   `> Blocked: <reason> | tried: <…> | needs: <…>`, inside the slice's
   `> Handover:` blockquote;
2. dispatches nothing more for that slice — no Step 3 fix attempt, no rung of
   the escalation ladder, no circuit breaker;
3. leaves the slice header `[ ]` and continues with the next `slice.py ready`
   batch.

`slice.py ready` reads the `> Blocked:` line. A slice whose span holds one is
printed as `blocked: <n> <name>` and never as `ready:`; an open slice whose
`Blocked by` chain reaches a blocked slice is printed as
`waits: <n> <name> on blocked <m>` and never as `ready:`. Slices with no path to
a blocked slice are unaffected.

Phase 1 ends when `ready` names no ready slice. The later phases run over the
closed slices; an acceptance criterion owned by a blocked or waiting slice is
reported as blocked in Phase 4 and never sent back to Phase 1. The Phase 6
report lists every blocked slice with its reason and need, and the slices
waiting on it, on the line next to the ambiguity count.

A human unblocks a slice by deleting its `> Blocked:` line once the need is met;
the next `ready` lists it again.

## Inputs

- A dispatch's returned output containing a line that starts with `[BLOCKED]`.
- A `> Blocked:` line under a `### Slice` heading, or in a flat implicit slice, in a `## Plan:` block.

## Outputs

- `tasks/todo.md`: the `> Blocked:` line under the slice heading.
- `slice.py ready` stdout: `blocked: <n> <name>` and `waits: <n> <name> on blocked <m>`
  lines alongside the existing `ready:` lines; exit 0.
- A malformed `> Blocked:` line refuses readiness with exit 2 and `invalid: <n> blocked line malformed`; reason, tried and needs must all be nonempty.
- `/build`'s Phase 6 report: a `Blocked slices:` line beside `Ambiguities:`.

## Edge Cases

- A `> Blocked:` line inside a fenced code block is an example, not a state:
  `ready` ignores it, as it ignores fenced rows.
- A `> Blocked:` line under a slice whose header is `[x]` changes nothing: the
  slice is done and is neither ready nor blocked.
- A slice waits on the nearest blocked slice in its chain; when several are
  blocked, `ready` names the lowest-numbered one it reaches.
- A flat plan block with no `### Slice` headings is one implicit slice;
  `ready` reads its `> Blocked:` line and excludes it until the marker is removed.
- A bare `> Blocked:` or a record with empty reason, tried or needs refuses readiness before any slice is printed as ready.
- A `[BLOCKED]` line from a Phase 2–4 repair dispatch stops that repair and is
  reported in Phase 6; it never reopens a closed slice.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where does the blocked state persist? | A `> Blocked:` line under the slice heading in `tasks/todo.md`, inside its handover blockquote | assumed | It survives compaction like the `> [AMBIGUITY]` lines, rides into the PR body's § Handovers with the blockquote, and needs no new file |
| 2 | How is re-dispatch prevented mechanically? | `slice.py ready` excludes a slice carrying `> Blocked:` and names its dependents as `waits:` | assumed | `/build` re-runs `ready` after every slice; without this the blocked slice is ready again on the next call |
| 3 | Where is the `[BLOCKED]` line format defined? | `build/references/harness-dispatch.md` § *Blocked exit*, pointed at from the delegation prompt list in `build/SKILL.md` | assumed | The issue names that file, and `build/SKILL.md` is held to a 600-line budget |
| 4 | Does a `[BLOCKED]` from `code-debugger` count? | Yes — any dispatch serving the slice | assumed | The escalation ladder is where an impossible slice burns four attempts |
| 5 | Helix's blocked state | Out of scope: no Helix code exists in this tree; the `> Blocked:` line is the state a later Helix reader consumes | assumed | The issue's last sentence describes a consumer that has not landed |
| 6 | Escalate to `/system-design-planning`? | No | assumed | One internal CLI output and one skill contract change; no persisted data model or external contract changes |

## Acceptance Criteria

- AC1: A `[BLOCKED]` line ends the slice with no retry and no `[x]` — `build/SKILL.md` says a returned `[BLOCKED]` line is written as `> Blocked:` and the slice gets no further dispatch (no Step 3 attempt, no ladder rung) and keeps its `[ ]` header; `slice.py ready` never prints `ready:` for a slice whose span holds `> Blocked:`, and prints `blocked: <n> <name>` instead.
- AC2: `/build`'s Phase 6 report template carries a `Blocked slices:` line next to an `Ambiguities:` line, listing each blocked slice with its reason and need.
- AC3: Slices that depend on a blocked slice are never dispatched — `slice.py ready` prints `waits: <n> <name> on blocked <m>` for an open slice whose `Blocked by` chain reaches a blocked slice (directly or transitively) and never `ready:` for it, while a slice with no path to the blocked one stays ready.
- AC4: The delegation prompt states that BLOCKED is an acceptable result — the `Delegation prompt must include` list in `build/SKILL.md` carries the `[BLOCKED] <reason> | tried: <…> | needs: <…>` exit and the words "an acceptable result", and `harness-dispatch.md` § *Blocked exit* defines the line.

## Implementation Paths

- `.agents/skills/slice/scripts/slice.py` — `ready` reads `> Blocked:` lines per slice span and prints `blocked:` / `waits:`.
- `.agents/skills/slice/references/plan-block.md` — the plan-block grammar names the `> Blocked:` line and how a human clears it.
- `.agents/skills/build/SKILL.md` — the delegation prompt item, the persist-on-return rule, the no-retry rule, the Phase 1 end condition, Phase 4's blocked marking and the Phase 6 report line.
- `.agents/skills/build/references/harness-dispatch.md` — § *Blocked exit*: the line format and what it replaces.
- `tests/test-slice.sh`, `tests/fixtures/slice/ready-blocked/**` — `ready` against blocked, waiting and independent slices.
- `tests/test-doc-conventions.sh` — pins the `/build` contract tokens.

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: `tests/test-slice.sh` and its fixture directory count as two systems but verify the one script.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | ready-skips-blocked | `slice.py ready` prints `blocked:` for a slice carrying `> Blocked:` and `waits:` for every slice whose chain reaches it, and the plan-block grammar names the line | `.agents/skills/slice/scripts/slice.py`, `.agents/skills/slice/references/plan-block.md`, `tests/test-slice.sh`, `tests/fixtures/slice/ready-blocked/**` | — | 3 | `bash tests/test-slice.sh` | 5 files · 3 systems · 1 AC |
| 2 | build-blocked-exit | `/build`'s dispatch contract carries the `[BLOCKED]` exit, persists it as `> Blocked:`, stops retrying, and reports blocked slices in Phase 6 | `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/harness-dispatch.md`, `tests/test-doc-conventions.sh` | 1 | 1, 2, 4 | `bash tests/test-doc-conventions.sh` | 3 files · 2 systems · 3 ACs |

Build prompt:

```
Invoke `/build` for `specs/blocked-exit.md`.
Plan: `## Plan: blocked-exit` in `tasks/todo.md`, 2 slices, ready set 1.
Files: .agents/skills/slice/scripts/slice.py, .agents/skills/slice/references/plan-block.md, .agents/skills/build/SKILL.md, .agents/skills/build/references/harness-dispatch.md, tests/test-slice.sh, tests/fixtures/slice/ready-blocked/**, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: the `[BLOCKED]` line format is defined once, in `build/references/harness-dispatch.md` § *Blocked exit*; `build/SKILL.md` stays at most 600 lines.
```
