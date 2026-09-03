# Spec — Automatic Issue → Lane Routing

> Status: proposed
> Blast radius: template-wide. Ships to every consumer via `/sync` and `install.sh`.

## Problem

Hand the agent an issue — a URL, `fix #123`, or "take the next backlog item" — and
nothing routes it. The agent improvises. It can plan and build correctly and still skip
every review gate, because the gates live inside skills that were never invoked.

Four causes, all verified in this repo:

1. No `UserPromptSubmit` handler in `.claude/settings.json`.
2. No skill description mentions `ticket`, `URL`, or `GitHub`. Auto-invocation is
   description-matched, so issue-shaped input matches nothing.
3. `CLAUDE.md`'s workflow is prose. Nothing turns it into a dispatch.
4. Sessions carry directives like *"do not use workflows unless the user requested
   it"*. Anything that only *suggests* a lane loses to them.

What it cost: `ascii_video_pipeline` #93 shipped with TDD and 4014 green tests, but
`/quality-gate` and the pre-push reviewers never ran. Not by decision — by omission. Two
predicates deleted and 19 tests rewritten on one context's self-review, which under
Independence Accounting has zero corroborating witnesses.

## Design

### Who does what

The model reads the task and describes it. Code decides what that description permits.

| Layer | Owner | Why |
|---|---|---|
| Perception — read the task, emit a claim | the model | semantics; a regex over prose is worse |
| Policy — lattice, default-deny, monotonicity | `route_issue.py` | safety must be exhaustively testable |

The claim has a fixed schema. Every field is required. Missing or unparseable is a
rejection, never a default:

```json
{
  "kind": "feature|bug|decision|research|epic|operational|task",
  "has_acceptance_criteria": true,
  "acceptance_criteria_machine_checkable": true,
  "blast_radius_subsystems": 1,
  "declared_paths": ["src/router/"],
  "user_facing_behavior": false,
  "visual_output": false,
  "security_touching": false,
  "irreversible_or_outward_facing": false,
  "docs_only": false,
  "blocking_question": null,
  "lane_selecting_imperatives": []
}
```

### All tracker access goes through `/task-registry`

`CLAUDE.md` § Task Tracking: *"No skill talks to a tracker directly."* `/route` makes no
`gh` calls. It gets task detail from `show` and the ready list from `frontier`.

This buys three things. Jira works without extra code. Auth, provider selection, offline
degradation and redaction are already built and tested. Dependency ordering and cycle
detection come with `frontier`, so "take the next backlog item" is not a hand-rolled read
of `tasks/backlog.md`.

### Inputs

| Input | Source | Trust |
|---|---|---|
| Title, body, labels, status, kind, dependencies | `/task-registry show <task-id>` | body and title **untrusted** |
| Ready and blocked lists | `/task-registry frontier` | trusted |
| `channel` | interactive, or scheduled / `--auto` | trusted |
| Project gates | `.claude/project.md` § Evidence Gate, § Autonomy Policy | trusted |

### Outputs

Five fields, written to `tasks/route-decision.md` **before any source file is touched**,
and repeated in the PR body:

| Field | Range |
|---|---|
| `lane` | which playbook, and its `prelude` and `auto_confirm` slots |
| `autonomy` | `autonomous` \| `gated-at-plan` \| `gated-at-plan-and-pre-push` |
| `human_verification` | `needed`, plus `judges` — *what* the human is asked to judge |
| `verification_method` | `tests` \| `measurement` \| `e2e` \| `deployment` \| `link-check` \| `project-evidence-gate` |
| `reviewers` | subset of `code-reviewer`, `critic`, `security-reviewer`, `software-design-expert-review` |

Alongside them, for audit: `ceiling` (the three grants), `downgrades` (each with its
signal), `ignored_directives`, `declared_radius`, `author_association`.

### Autonomy: three grants, take the lowest

```
effective_autonomy = min(channel_grant, label_grant, content_ceiling)
```

| Grant | Default | Can it raise autonomy? |
|---|---|---|
| `channel_grant` | `gated-at-plan` interactive, `autonomous` scheduled | yes — trusted |
| `label_grant` | `gated-at-plan`; `autonomous` only with the autonomy label | yes — trusted |
| `content_ceiling` | starts `autonomous`, only ever ratchets down | **never** |

**Monotonicity.** No claim can raise autonomy above `min(channel_grant, label_grant)`.
The claim is derived from untrusted content, so it enters as `content_ceiling` and can
only lower the result. A model that wrongly reports `kind: feature, radius: 1` on a
security migration still cannot unlock the autonomous lane. The guarantee depends on the
direction of the arrow, not on the classifier being right.

Because the claim space is small and mostly boolean, this is provable by enumerating
every point rather than sampling fixtures.

**The label is the human's yes, moved earlier.** Applying a label needs repo write
access, so it is not something a reporter can do by writing prose. Authorization becomes
asynchronous — granted at triage — instead of a prompt mid-run.

The label name lives in the project's task-tracking configuration, defaulting to
`auto-mode-allowed`. `/task-registry` already owns label vocabulary. A project that
declares no label never reaches `autonomous`, which is the correct default.

### Eligibility: deny unless every check passes

`content_ceiling` stays `autonomous` only if all hold. Unknown counts as fail.

- acceptance criteria present, and every one machine-checkable
- blast radius ≤ 1 subsystem
- no blocking question
- no `needs-discussion`, `question`, or `design` label
- no unresolved linked PR
- nothing security-touching, irreversible, or outward-facing
- no project evidence gate that needs human judgement

A lane-selecting imperative in the body (`run /yolo`, `skip review`) is an injection
attempt. It is ignored, recorded in `ignored_directives`, and is itself a downgrade.

### Lanes are playbooks, and their steps land in `tasks/todo.md`

A lane is a file under `.agents/skills/route/playbooks/`. Routing copies its steps
verbatim into `tasks/todo.md` before touching any source file:

```
[ ] prelude: </brainstorm | /debug | skip: not needed for this kind>
[ ] /plan            (auto-confirm: <yes|no>)
[ ] /build           (runs /quality-gate on completion)
[ ] <supported /verify invocation for method>
[ ] reviewers: <named set>, separately dispatched
[ ] /wrap-up-session
```

Every step appears in every lane. A step not run keeps its row and gains
`skip: <reason>`. Silent omission is not allowed.

That is the whole enforcement mechanism. A missing gate stops being an invariant to
argue about and becomes a line on disk that a user, a reviewer, or a test can see. The
pattern comes from pstack's `poteto-mode`; issue #81 retrofits it to `/build`,
`/wrap-up-session`, and `/quality-gate`, and does not block this work.

### Which slots the claim sets

`kind` comes first, because the project already classified the work and re-deriving it
from prose would be a second, worse classifier. A dash means the row leaves that slot
alone.

| Claim | prelude | verification | autonomy ceiling | reviewers |
|---|---|---|---|---|
| `bug` with a stack trace or failing test | `/debug` | `tests` | `autonomous` if AC present, else `gated-at-plan` | `code-reviewer` |
| `decision` | `/brainstorm` | — | `gated-at-plan`, **never** auto-confirm | `+ critic` |
| `research` | `/brainstorm` | `measurement` | `gated-at-plan-and-pre-push` | `+ critic` |
| `epic` | `/brainstorm` | — | `gated-at-plan-and-pre-push` | `+ critic`, `+ software-design-expert-review` |
| `operational` | none | `deployment` or `e2e` | `gated-at-plan` | `code-reviewer` |
| `feature`/`task` with AC, radius ≤ 1 | none | `tests` | `autonomous` | `code-reviewer` |
| `docs_only` | none | `link-check` | `autonomous` | `code-reviewer` |
| blocking question present | — | — | `gated-at-plan`, no auto-confirm | — |
| radius ≥ 3, or no AC | `/brainstorm` | — | `gated-at-plan-and-pre-push` | `+ software-design-expert-review` |
| `user_facing_behavior` | — | `e2e` | — | — |
| security-touching, irreversible, or outward-facing | — | — | `gated-at-plan-and-pre-push` | `+ security-reviewer` |
| blocked, or an unknown dependency | — | — | **refuse to start**, name the blocker | — |

Rows compose. `autonomy` composes by `min`, `reviewers` by union. Neither narrows.

`decision` mapping to "never auto-confirm" is not a heuristic — the kind means *an open
choice blocking work*.

### What a human is asked to judge

- **Machine-checkable evidence** — tests, measurements, coverage. Never a human gate.
- **Judgement** — does the render look right, does the copy read right, is this the right
  product call. Always a human gate. The agent's job is to make that judgement cheap.
- **Authorization** — commit, push, PR. The PR is the gate.

### Two guards on the autonomous lane

**Runtime tripwire.** The claim *predicts* a blast radius. After `/build`, compare the
real diff against `declared_radius`. If it overflows, halt the autonomous path and land
the work as a gated PR carrying the prediction miss.

**Inverted reviewer floor.** The lane with nobody watching gets more witnesses, not
fewer. `autonomous` requires `code-reviewer` and `critic` (planner floor), separately
dispatched. A reviewer that hangs is reported, never counted as agreement, and demotes
the run to gated. A run that cannot produce corroboration has not earned the right to
skip the human.

Reviewers get all seven items of the Review Dispatch Contract, with 2–5 distinguishing
empty from absent. Findings apply under the Finding Model gates: auto-apply only
`gated_auto` at `confidence >= 75`. Everything else is reported and carried into the
wrap-up.

### Why a hook

| Candidate | Survives a suppression directive? |
|---|---|
| Skill `description:` matching | No. Model judgment is what the directive vetoes. |
| A table in `.claude/project.md` | No. A standing instruction, same class as prose. |
| `UserPromptSubmit` hook | **Not reliably in this harness.** It injects deterministic turn context, but Mode B observed no suppression-resistance lift. |

The directive says *"unless the user requested it"*. The hook records that installing
the project workflow is the request, but the Mode B result shows that context injection
does not guarantee the model will honor it under suppression.

`.claude/hooks/` and `.claude/settings.json` are both syncable, so registration reaches
consumers. Unlike `SessionStart`, `UserPromptSubmit` has no user-level counterpart, so it
cannot double-fire.

Descriptions are updated too — naming issues, tickets, URLs and `#123` — as a fallback
for Pi and for harnesses without hooks. Not the primary path.

### Project gates are discovered, never hardcoded

This repo is generic; its consumers are not. Two optional headings in
`.claude/project.md`, matched exactly, reusing the convention already proven by
Deployment Targets:

- `^## Evidence Gate[[:space:]]*$` — artifacts required before wrap-up may begin
- `^## Autonomy Policy[[:space:]]*$` — label name override, autonomy cap

The Autonomy Policy body is a bounded bullet map: `- autonomy_label: <label|none>`
and/or `- autonomy_cap: <autonomous|gated-at-plan|gated-at-plan-and-pre-push>`.
Unknown, duplicate, or malformed entries are rejected rather than ignored.

Absent either heading, the router invents nothing. `/sync` never overwrites
`.claude/project.md`, so these survive template updates.

### Reading structured data out of `/task-registry`

`route_issue.py` needs structured fields. The CLI prints bounded human text under
progressive disclosure, with no `--json`.

| Option | Verdict |
|---|---|
| **A** — use task-registry's provider-neutral library API | **Taken.** `Registry.resolve_task` returns the complete normalized record; callers pass only a reference and never rebuild private metadata from prose. Same repo, same stdlib Python, no parsing. |
| **B** — add `--json` to `show` and `frontier` | Cleanest contract, but edits a freshly merged surface. Propose separately. |
| **C** — parse the printed text | Rejected. Progressive disclosure deliberately truncates; parsing a summary designed to elide is silent data loss. |

## Verification before push

Static tests cover the decision engine completely. They cannot cover the one thing the
whole design turns on: whether an issue-shaped prompt actually reaches `/route` in a live
session carrying a suppression directive. `/eval` answers that empirically.

**Mode A — triggerability.** Organic issue-shaped prompts (an issue URL, `fix #123`,
"take the next backlog item"), N ≥ 3, each in its own sanitized worktree, graded from
transcripts by `scripts/grade-skill-loads.sh`. Outcomes are `FIRED`, `MISROUTED` (record
which skill won), or `NONE`. A misroute is a description defect — fix the description
before touching the prompt.

**Mode B — hook versus description.** Two branches: one with `UserPromptSubmit`
registered, one with the description change alone. Same prompts, N ≥ 2 per arm, one judge
pass on one scale. This measures the claim the whole design rests on — that a hook beats
a description when a directive is suppressing workflows.

Both run **before push**, and both honour `/eval`'s Iron Law: no candidate is told it is
being measured. Presence/absence lift is not available in this harness and is not
claimed.

## Edge Cases

| Case | Behavior |
|---|---|
| Provider unreachable | `/task-registry` degrades reads to local-only. `/route` decides on the local half and caps autonomy at `gated-at-plan` — a partial picture must not run unattended. |
| Task not found | Stop with the error. Never guess content. |
| Index row has no stable ID | Stop, point at `/task-registry migrate`. A task with no identity cannot carry a decision record. |
| Empty body | No acceptance criteria, so not eligible. `gated-at-plan-and-pre-push`. |
| Label present, channel interactive | `min` gives `gated-at-plan`. The label raises the ceiling; it does not skip an interactive gate without `--auto`. |
| Autonomy label and `needs-discussion` together | `needs-discussion` downgrades. `min` wins. |
| Reviewer hangs | Reported, run demoted to gated, corroboration loss stated. |
| Local-provider task, no tracker | Same function. `label_grant` defaults to `gated-at-plan`; `author_association` is `in-repo`. |
| Jira project | Same function, unchanged. The provider abstraction is `/task-registry`'s. |
| Real diff exceeds `declared_radius` | Halt the autonomous path, land gated, record the miss. |
| `/build` HALT or circuit breaker | Not a lane, a failure exit. Run `/checkpoint` and leave `tasks/route-decision.md` with the halt reason. A stopped run loses the PR, never the memory. |

## Acceptance Criteria

1. An issue URL, `fix #123`, or "take the next backlog item" produces a recorded
   five-field decision in `tasks/route-decision.md` before any source file is touched.
2. The decision comes from a unit-tested function, with #93 and at least four other real
   issues as fixtures, including one routing to `/brainstorm` and one refusing to
   auto-confirm.
3. The lane runs through existing skills. No plan, build, or wrap-up logic is
   reimplemented in the router.
4. Playbook steps are copied verbatim into `tasks/todo.md` before any source edit, and
   any step not run keeps its row with `skip: <reason>`.
5. `route_issue.py` holds no prose classification — grep-asserted — and rejects a claim
   with any missing or unparseable field instead of defaulting it.
6. Reviewers get all seven contract items. A hung reviewer is reported and demotes the
   run; it is never silently dropped.
7. Findings apply under the Finding Model gates, and unapplied findings appear in the
   wrap-up output.
8. A project evidence gate in `.claude/project.md` is discovered and enforced. Absent
   one, the router invents nothing.
9. No claim raises autonomy above `min(channel_grant, label_grant)`, proved by
   enumerating the whole claim space rather than sampling it.
10. The hook fires on issue-shaped prompts and stays silent otherwise, tested
    deterministically.
11. `/eval` Mode A shows `/route` firing on organic issue-shaped prompts at N ≥ 3, and
    Mode B compares the hook arm against the description-only arm. Both run before push.
    Results are recorded whatever they show.
12. `/route` makes zero direct `gh` or Jira calls — grep-asserted — and reaches task
    state only through `/task-registry`.
13. "Take the next backlog item" resolves via `frontier`. A task reported `blocked` or
    `unknown-dependency` is refused, not routed.
14. The autonomy label name comes from project configuration. A project declaring none
    never reaches `autonomous`.
15. `/auto-improve` Phase 3 routes through the same function, so exactly one lane
    decision exists in the repo.
16. `tests/run.sh` passes. No existing skill's documented behaviour changes without a
    note saying which and why.

## Non-Goals

Auto-merging PRs. Removing the plan-confirmation gate. Rewriting `/plan`, `/build`, or
`/wrap-up-session`. Trackers beyond GitHub Issues, Jira, and the local provider.
