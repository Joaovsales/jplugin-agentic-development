---
implementation_paths:
  - .agents/skills/wrap-up-session/references/routines.md
  - .agents/skills/wrap-up-session/references/routine-prompts/improve.md
  - .agents/skills/go/SKILL.md
  - .agents/skills/task-registry/lanes/improve.md
  - .agents/skills/task-registry/lanes/refactor.md
  - .agents/skills/task-registry/lanes/babysit.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/slice/SKILL.md
  - AGENTS.md
  - tests/test-doc-conventions.sh
  - tests/test-go-lanes.sh
  - tests/test-routines-contract.sh
---

# Spec: Crossing the plan handover from a lane

## Behavior

`/plan` Step 6 and `/system-design-planning`'s hand-over end the planning
session with a build prompt and never build. Four lanes chain a planner into
`/build`: `simplify` crosses through the override `/make-it-simpler` §
*Overrides* owns, in every mode; `improve` (a routine consumer, and interactive
through `/go`), `refactor` and `babysit` (interactive only) have no owning
skill. One section, `.agents/skills/wrap-up-session/references/routines.md` §
*Crossing the plan handover*, is the map of every crossing and the rule for the
lanes without an owner:

- **A skill that owns a Step 6 override** — `/auto-push`, `/yolo`,
  `/make-it-simpler` — crosses on its own terms; the section names them and
  restates none of their overrides.
- **Unattended lane run** (a routine branch, per § *Unattended detection*) with
  no owning skill. The run owns an override on the planner's hand-over step: it
  prints no build prompt, `/build` runs in place in the same session, and
  `/build`'s pre-flight files with `/slice <spec> --file` and **no**
  `--approve` — nobody typed the build prompt, so the project's approval floor
  decides, exactly as for `/yolo`. The lane's later steps follow in the same
  session. It is the fourth named exception to the fresh-session rule.
- **Interactive lane run** (`/go`) with no owning skill. The handover is
  honoured: the planning session ends at the build prompt, which stays the
  session's last message, and the fresh session the human starts with it is the
  review gate. `/go` appends ` — handed over: build prompt` to each lane line
  after the planner step instead of running it, and its reply precedes the
  prompt. The build session runs those steps: the build prompt ends in
  `/wrap-up-session`, and `/build` runs `/quality-gate`.

**Fresh context for an in-place build.** Whenever `/build` runs in the session
that planned it — any of the four exceptions — the implementation still gets a
fresh context: every slice dispatches to a sub-agent, a lone ready slice and
each slice of a serialized pair included, carrying only what a dispatched slice
already carries (its rows, the spec, its blockers' handovers). The coordinating
session keeps verification central, as it does today. Where the harness offers
no sub-agents, `/build` runs inline and says so in one line. The rule lives in
`/build`, which executes it; § *Crossing the plan handover* cites it.

`go/SKILL.md`, the three ownerless lane files and `routine-prompts/improve.md`
cite the section by name and restate none of it. The stale claims that `/plan`
asks "Confirm with 'y'" or is "where the human is asked before code changes" are
replaced: the gate is the build prompt, and a human crosses it by starting a
fresh session.

## Inputs

- A lane run reaching its planner step (`/plan <ref>`, or
  `/system-design-planning`, `improve` step 1's alternative route).
- Whether the run is unattended, read by `routines.md` § *Unattended detection*.
- Whether `/build` was invoked in place by a planning session or started by a
  build prompt.

## Outputs

- Unattended, no owner: no build prompt; `/build` runs in place; slices filed
  `--file` without `--approve`; the lane continues to `/wrap-up-session`.
- Interactive, no owner: the build prompt as the session's last message; the lane
  block's post-planner lines carry ` — handed over: build prompt`.
- In-place `/build`: one sub-agent dispatch per slice, every slice.

## Edge Cases

- **`plan` lane.** Its chain is `/plan` → `/wrap-up-session`; nothing past the
  planner builds, so the rule does not apply. `/plan` prints the build prompt
  and the lane still runs `/wrap-up-session`, whose draft PR is what the human
  reviews.
- **`improve` routed through `/system-design-planning`.** The same override
  applies to its hand-over step; `/plan`'s row keeps its `skip:`.
- **`babysit` with no requested change.** Its `/plan` row is skipped; there is
  no handover to cross.
- **Refactor before-proof.** The interactive build session never saw the
  before-proof run; it reads it from the spec, whose acceptance criteria are
  "the before-proof still holds" and name the command.
- **`simplify` through `/go`.** Builds in place, because `/make-it-simpler` owns
  that override in every mode; the interactive rule is for ownerless lanes only.
- **No sub-agents in the harness.** The in-place build runs inline, with one
  line saying the fresh-context dispatch was unavailable — never silently.
- **A build session started by a build prompt.** Already fresh; dispatch stays
  as today (parallel for disjoint ready slices, otherwise in the main context).

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | How does an unattended ownerless lane cross `/plan`'s handover? | It owns a Step 6 override: no prompt, `/build` in place, `--file` without `--approve`; the same override covers `/system-design-planning`'s hand-over | user | Nobody is watching to start a fresh session; the approval floor stands in for the human, as for `/yolo` |
| 2 | How does an interactive `/go` run cross it? | It honours the handover: the planning session ends at the build prompt; later lane lines carry ` — handed over: build prompt` | user | The fresh session is the review gate by design; `/go` adds no gate of its own and must not remove one |
| 3 | Where does the rule live? | One § *Crossing the plan handover* in `routines.md`, next to § *The shared spine*, mapping every crossing; `/go`, the ownerless lane files and the improve prompt cite it | user | One home; `routines.md` already owns § *Unattended detection*, which the rule keys on |
| 4 | Fix the stale "Confirm with 'y'" / "human is asked" wording? | Yes, in this change | user | Same misconception, same lines |
| 5 | Change `/plan`, `/slice`'s handover, `/yolo`, `/auto-push`, `/make-it-simpler`? | No | user | Callers own overrides; `/plan` never learns who calls it; `/make-it-simpler` (#222) already owns `simplify`'s crossing |
| 6 | How does `/make-it-simpler`'s exception (merged in #222) fit? | It stays the third named exception and the owner of `simplify`'s crossing; the lane rule is the fourth; `AGENTS.md` step 3 names all four | assumed | Master shipped it before the general rule; keeping its numbering leaves its `SKILL.md` and pins untouched |
| 7 | Does `/build`'s pre-flight sentence change? | Yes — one clause: an unattended lane run omits `--approve` alongside `/yolo`, citing the section; `/slice`'s Integration line likewise | assumed | `/build` is what passes the flag; a rule it does not read would not reach it |
| 8 | Does the `plan` lane count? | No — nothing past its planner builds | assumed | The rule is about crossing into `/build` |
| 9 | Can an unattended build start with a fresh context? | Yes, inside the session: an in-place `/build` dispatches every slice to a sub-agent, even a lone one | user | The planning context stays in the coordinator; the code is written in clean contexts, with no host change |
| 10 | Which in-place builds dispatch every slice? | All four exceptions, not only unattended lane runs | assumed | The stale context comes from building in the planning session, which all four share; an attended `/auto-push` build carries the same history |
| 11 | A second host session for the build (two `claude -p` runs, or a chained cloud trigger)? | Out of scope; a follow-up next to the deferred `build` routine (#98) | user | It changes the routine host contract and, on cloud routines, rests on unprobed trigger behaviour |

## Acceptance Criteria

- AC1 — `routines.md` carries a `### Crossing the plan handover` section that names `/auto-push`, `/yolo` and `/make-it-simpler` as owning their crossing and `simplify` as crossing through `/make-it-simpler` § *Overrides*; names the ownerless lanes `improve`, `refactor`, `babysit`; for unattended runs states that no prompt is printed, `/build` runs in place, and the pre-flight runs `--file` without `--approve`, and that it applies to `/system-design-planning`'s hand-over too; for interactive runs states that the build prompt stays the session's last message and later lines carry ` — handed over: build prompt`; and cites `/build` for the fresh-context dispatch. Pinned in `tests/test-routines-contract.sh`.
- AC2 — `routine-prompts/improve.md` cites § *Crossing the plan handover* and no longer says "confirm the plan yourself". Pinned in `tests/test-routines-contract.sh`.
- AC3 — `go/SKILL.md` cites § *Crossing the plan handover*, names the ` — handed over: build prompt` append as the second edit it may make to a block, says its reply precedes the build prompt, and no longer says "Confirm with 'y'". Pinned in `tests/test-go-lanes.sh`, whose AC7 comment names the build prompt, not "Confirm with 'y'", as `/plan`'s gate.
- AC4 — `lanes/improve.md`, `lanes/refactor.md` and `lanes/babysit.md` each cite § *Crossing the plan handover* on their planner step, and none says "where the human is asked before code changes". `task-registry lanes` chains are unchanged (`tests/test-lane-catalogue.sh` stays green). Pinned in `tests/test-go-lanes.sh`.
- AC5 — `AGENTS.md` step 3 names four exceptions that build in the planning session: `/auto-push`, `/yolo`, `/make-it-simpler`, and an unattended lane run citing § *Crossing the plan handover*; the existing make-it-simpler pin in `tests/test-doc-conventions.sh` § pipelines is updated to the new sentence; `tests/test-instruction-budget.sh` stays green.
- AC6 — `build/SKILL.md` pre-flight and `slice/SKILL.md` § Integration name an unattended lane run as omitting `--approve` alongside `/yolo`. Pinned in `tests/test-doc-conventions.sh` § pipelines.
- AC7 — `/plan`, `/yolo`, `/auto-push` and `/make-it-simpler` are byte-unchanged against `master` (`git diff --quiet master -- .agents/skills/plan .agents/skills/yolo .agents/skills/auto-push .agents/skills/make-it-simpler`).
- AC8 — `build/SKILL.md` § *Parallel Dispatch Assessment* states that a build running in the session that planned it dispatches every slice to a sub-agent — a lone ready slice and each slice of a serialized pair included — keeps verification central, and, with no sub-agents in the harness, runs inline and says so in one line; a build-prompt session's dispatch is unchanged. Pinned in `tests/test-doc-conventions.sh` § build.

## Implementation Paths

- `.agents/skills/wrap-up-session/references/routines.md` — the map of crossings and the ownerless-lane rule
- `.agents/skills/wrap-up-session/references/routine-prompts/improve.md` — the unattended host prompt that reaches the handover
- `.agents/skills/go/SKILL.md` — interactive runs honour the handover
- `.agents/skills/task-registry/lanes/{improve,refactor,babysit}.md` — planner steps cite the rule
- `.agents/skills/build/SKILL.md` — who omits `--approve`; every slice dispatched when built in place
- `.agents/skills/slice/SKILL.md` — who omits `--approve`
- `AGENTS.md` — the fourth named exception
- `tests/test-routines-contract.sh`, `tests/test-go-lanes.sh`, `tests/test-doc-conventions.sh` — the pins

## Build Order

Sizing: 5 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 5: 3 systems (build, slice, test-doc-conventions) — the `/slice` edit is one Integration clause mirroring `/build`'s pre-flight; split, it would be a one-clause slice editing the same § pipelines block again.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Rule home in routines | § Crossing the plan handover in `routines.md` maps every crossing; the improve routine prompt cites it | `.agents/skills/wrap-up-session/references/routines.md`, `.agents/skills/wrap-up-session/references/routine-prompts/improve.md`, `tests/test-routines-contract.sh` | — | 1, 2 | `bash tests/test-routines-contract.sh` | 3 files · 2 systems · 2 ACs |
| 2 | Go honours the handover | `/go` cites the rule, appends ` — handed over: build prompt`, replies before the prompt; stale "Confirm with 'y'" gone | `.agents/skills/go/SKILL.md`, `tests/test-go-lanes.sh` | — | 3 | `bash tests/test-go-lanes.sh` | 2 files · 2 systems · 1 AC |
| 3 | Lane planner steps cite the rule | improve, refactor, babysit planner steps cite the rule; "human is asked" wording gone | `.agents/skills/task-registry/lanes/improve.md`, `.agents/skills/task-registry/lanes/refactor.md`, `.agents/skills/task-registry/lanes/babysit.md`, `tests/test-go-lanes.sh` | 2 | 4 | `bash tests/test-go-lanes.sh && bash tests/test-lane-catalogue.sh` | 4 files · 2 systems · 1 AC |
| 4 | Fourth named exception | `AGENTS.md` step 3 names four exceptions; the make-it-simpler pin follows the new sentence | `AGENTS.md`, `tests/test-doc-conventions.sh` | — | 5, 7 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh && git diff --quiet master -- .agents/skills/plan .agents/skills/yolo .agents/skills/auto-push .agents/skills/make-it-simpler` | 2 files · 2 systems · 2 ACs |
| 5 | In-place build dispatches every slice | `/build` dispatches every slice to a sub-agent when built in the planning session; `/build` and `/slice` name the unattended lane run as omitting `--approve` | `.agents/skills/build/SKILL.md`, `.agents/skills/slice/SKILL.md`, `tests/test-doc-conventions.sh` | 4 | 6, 8 | `bash tests/test-doc-conventions.sh && bash tests/test-skill-invocation-chain.sh` | 3 files · 3 systems · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/lane-plan-handover.md`.
Plan: `## Plan: lane-plan-handover` in `tasks/todo.md`, 5 slices, ready set 1, 2, 4.
Files: .agents/skills/wrap-up-session/references/routines.md, .agents/skills/wrap-up-session/references/routine-prompts/improve.md, .agents/skills/go/SKILL.md, .agents/skills/task-registry/lanes/improve.md, .agents/skills/task-registry/lanes/refactor.md, .agents/skills/task-registry/lanes/babysit.md, .agents/skills/build/SKILL.md, .agents/skills/slice/SKILL.md, AGENTS.md, tests/test-doc-conventions.sh, tests/test-go-lanes.sh, tests/test-routines-contract.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/lane-plan-handover.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: `/plan`, `/yolo`, `/auto-push`, `/make-it-simpler` stay byte-unchanged (D5); interactive `/go` runs of ownerless lanes stop at the build prompt, only unattended ones build in place (D1, D2); the crossing map is stated once, in routines.md § Crossing the plan handover, and cited everywhere else (D3); `/make-it-simpler` stays the third named exception, the lane run is the fourth (D6); every in-place build dispatches every slice to a sub-agent, inline only when the harness has none, said in one line (D9, D10); no second host session (D11).
```
