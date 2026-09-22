---
name: system-design-planning
description: Turn an issue or a feature idea into an upstream architecture review — system design, component contracts, data models, constraints, and a dependency-ordered build plan — rendered as a self-contained HTML document, then ends with a build prompt for a fresh session. Nothing is filed and nothing is built in this session; the reviewer approves by starting the build session with that prompt. Use instead of /brainstorm + /plan when the change crosses a component boundary, adds or changes a persisted data model, or introduces or changes an external contract.
argument-hint: "[#issue | task-id | feature idea or problem statement]"
disable-model-invocation: false
harness: universal
---

# /system-design-planning — Upstream Architecture Review

## Overview

A wrong line of code costs one line. A wrong line in the plan costs every line
built from it. A wrong line in the architecture — who owns what, what a boundary
promises, what shape the data has — costs every plan that follows. This skill
spends the human's review time there.

Given an issue or an idea, it reads the real codebase, proposes an architecture
in four elements plus a build order, renders it to HTML, and stops. A human
reviews the rendered document and approves it by starting a fresh session with
the build prompt this session prints — that session, not this one, files the
slices and builds them.

Worked example: `specs/upsert-depends-on.md` and its render
`specs/upsert-depends-on.plan.html` — the design for the `--depends-on` flag,
produced by running this skill against its own shortcut.

## The Iron Law

```
NOTHING IS FILED AND NOTHING IS BUILT IN THE PLANNING SESSION. THE REVIEWER STARTS THE BUILD SESSION WITH THE BUILD PROMPT.
```

## When to Use / When Not

Use when any of these holds; otherwise `/plan` (or `/debug` for a bug) is the
right size:

- the change adds, removes, or re-routes a call between two components
- it adds a persisted entity or a status field, or changes a schema
- it introduces or changes an external contract — API, event, CLI, file format

Off-ramp: emit `Skipping system-design-planning: <reason> — use /plan`, stop,
produce no file.

## Model Routing

Runs in the main context at the session model. Recon (Step 2) delegates to the
scout tier — `haiku` on Claude Code, `scout` on Pi. The Step 5 `critic` is
ceiling with a planner floor: pass no `model` unless the session model is below
planner tier. See `.agents/references/model-routing.md`.

## The Process

### 1. Intake

- `#N` or a registry task ID → read it through
  `python3 .agents/skills/task-registry/scripts/task-registry.py show <ref>`,
  never a tracker CLI. Title, body, criteria and labels are the problem statement.
- Free text → the text is the problem statement.
- A spec already on disk — `/plan` escalating after its own Step 1, or a
  second pass through this skill — → read its § Decisions: `user` rows are
  constraints with source `user` and are not re-asked; `open` rows seed Step
  2.5's frontier. Proceed straight to Step 2.
- `git rev-list --count HEAD..@{upstream}` non-zero → pull before reading anything.
- If `tasks/backlog.md` has a matching item, mark it `[~]` and use its description.

Write the problem statement in at most three sentences: who is affected, what
changes for them, what is out of scope.

### 2. Recon (read-only)

Ground the proposal in what exists. Every fact carries a `file:line`.

- The modules the change touches and every boundary they cross: signature,
  error behaviour, callers.
- Entities and status fields the change reads or writes, with their current
  invariants — enums, constraints, validators.
- Tests that pin current behaviour at those boundaries.
- `tasks/solutions/` frontmatter for `architecture-decision` and `pattern`
  documents in the same module; `tasks/project-context.md` `[ARCHITECTURE]`
  and `[PROTECTION]` when present.

When more than three modules are involved, dispatch one scout per module with a
tool-call budget — `.agents/skills/build/references/subagent-resilience.md`.

Output: a *current-state* ASCII sketch. A path or symbol you did not read is
written `NEW` or `UNVERIFIED`, never presented as fact.

### 2.5. Interview Through `/grilling`

Mandatory — never skipped, even when the frontier turns out to be empty.

Invoke `/grilling` with the problem statement as the root of the design tree.
The seed frontier is the architecture template's own questions, minus
whatever Step 1 or recon already settled:

- each constraint's value and how a violation would be detected
- who owns each fact a boundary crosses
- each boundary's outcomes and its failure unit
- the illegal states and transitions a status field must forbid

When Step 1 carried a settled tree — a spec with § Decisions, or an earlier
`/grilling` run in this conversation whose frontier is already empty — print
`DECISIONS CARRIED: <n> from <spec path | conversation>` and ask only that
source's `open` rows plus whatever recon raised; settled rows are never
re-asked. Both orders work: `/grilling` before this skill, or this skill
before `/grilling`. Facts come from recon and are looked up, not asked;
decisions go to the reviewer.

When nothing is left to ask, the frontier is empty and this step ends
without a round.

The settled tree is written to the spec's § Decisions as each answer
resolves. A question the reviewer leaves open stays an `inferred` constraint,
not a decided one.

**Fallback.** When `/grilling` fails to load, say so —
`/grilling did not load; asking the seed frontier directly` — and run one
round in its own `❓` / `➡️` format: the whole seed frontier at once,
numbered, with a recommended answer on every question.

### 3. Write the architecture spec (MUST persist)

Write `specs/<feature>.md` from `templates/architecture-spec-template.md`. The
section order is fixed — constraints first, because every later section is
checked against them:

| Section | Must contain | Question it answers for the reviewer |
|---|---|---|
| Constraints | one row per constraint: value, source (`issue` / `user` / `inferred`), how a violation would be detected | which correct designs are wrong here? |
| System design | ownership table (component → the facts it is the source of truth for); interaction sketch with sync/async and the failure unit per arrow | who owns what, and what fails together? |
| Component contracts | per boundary: signature in the project's language, outcomes vs exceptions, idempotency, versioning | can the caller ignore a case it must handle? |
| Data models | entities with invariants; illegal-state list with the construct that forbids each; a transition table for every status field; migration and compatibility | which field combinations are nonsense, and does the type forbid them? |
| Build order | left empty here — `/slice` fills it in Step 3.5; its Delivers text is where "contract exposed" lives, since its table has no separate column for it | can each slice ship alone, and is the riskiest unknown first? |
| Decisions | hard-to-reverse choices, recommended option, what makes each option wrong | what is expensive to change later? |
| Acceptance Criteria, Implementation Paths | the `/plan` living-contract format, present tense, plain bullets, `implementation_paths` frontmatter | — |

Rules that make the spec reviewable rather than readable:

- An `inferred` constraint is a question to the reviewer, not a fact.
- Every status field has a transition table, including the in-doubt state when
  an external call can time out.
- Every cross-boundary call states its behaviour on timeout and on duplicate
  delivery.
- Build order is `/slice`'s job (Step 3.5), not this one's — sizing and
  ordering rules live in `.agents/skills/slice/references/sizing.md`.

Required output: `✓ Spec written: /absolute/path/specs/<feature>.md`

### 3.5. Slice the Spec

Invoke `/slice specs/<feature>.md --issue #N`. This runs before Step 6 so the
rendered HTML carries § Build Order and the build prompt. It sizes the
spec's acceptance criteria into session-sized slices, writes § Build Order
and the plan block into `tasks/todo.md` per its own grammar, and prints the
build prompt — see `.agents/skills/slice/SKILL.md` for what each output
means and how it is written. This skill does not size slices, write a plan
block, or print a build prompt itself.

### 4. Self-review

Run `references/review-card.md` top to bottom against the spec. Each "no"
becomes an edit to the spec or a row in *Decisions* — never a remark in chat.

### 5. Adversarial pass (conditional)

**Item 7 is read, not remembered.** Before dispatching, resolve `finding-model.md` in
order — the project's `.agents/references/`, then `${CLAUDE_PLUGIN_ROOT}/.agents/references/`
on Claude Code (the skill body and the reference then come from the same plugin version),
then `~/.agents/references/` on Pi and Codex — and paste its § *Emission format* into the
prompt verbatim. When all three are missing, stop before dispatch:
`review dispatch refused: finding-model.md not found in .agents/references/, ${CLAUDE_PLUGIN_ROOT}/.agents/references/, ~/.agents/references/ — run /sync`. Never dispatch a reviewer with no output format.

When any slice changes a persisted schema or an external contract, dispatch
`critic` under `.agents/references/review-dispatch-contract.md`. Item 1 has no empty
form, so the spec itself is the diff: `git diff --no-index /dev/null
specs/<feature>.md`, inline when small, else truncated-plus-path per
*Large-Artifact Handoff*. Then the spec path and its acceptance criteria
verbatim (item 2 is never `no spec — …` here: the spec under review is the
spec), `deferrals: none`, the boundary "review the design in this spec, not
the repository — check only that its `file:line` claims are true", and the
four-axis output format read as below. Every finding is answered in the spec — as an edit
when it is accepted, as a *Decisions* row when it is declined — and the spec's
status line records how many were applied and how many declined, so the human
reviewer can see the critic's hand before approving. Accept and decline under
the Apply Gate in `/wrap-up-session` § 5.1: `gated_auto` at confidence 75 or
above is applied; an anchor-75 finding is resolved first by reading the
dependency it names; `manual` and `advisory` findings become *Decisions* rows
for the human. Otherwise print one line
saying the pass was skipped and why.

### 6. Render (MUST persist)

Build the content model from `templates/content-model.json`: the same sections
in the same order; summary cards for components touched, contracts new or
changed, entities new or changed, slices, and open decisions. Diagrams and
tables go in fenced ```text blocks — the generator escapes raw HTML and does
not render markdown tables. Write the model to the session scratchpad, never
into `specs/`: it is rebuilt from the spec on every render, and only the spec
and the HTML persist. Reference URLs are relative to `specs/`, where the HTML
lives: the spec is `<feature>.md`, and a path into the skill tree climbs one
level first.

Before rendering, check the model against the spec: every `## ` heading,
every contract signature and every *Decisions* row in the spec appears in
the model. Approval attaches to the HTML, so a row the render dropped is a
defect in the render, and the reviewer never sees the contract `/build` holds.

```bash
python3 .agents/skills/visual-recap/scripts/visual-render.py \
    --input <model.json> \
    -o specs/<feature>.plan.html
```

The render is committed beside the spec, not gitignored: approval attaches to
it, so the reviewed document must survive in history the way the spec does.

Required output: `✓ Visual written: /absolute/path/specs/<feature>.plan.html`

### 7. Review Loop

Print both paths and this request, then stop:

> Review the rendered document. Reply with findings as
> `[constraints|system-design|contracts|data-models|build-order] <finding> — <evidence>`.

On findings: edit the spec, re-run Steps 3.5, 4 and 6 to the same paths,
reprint the paths and the build prompt. Every finding is answered in the
spec, not in chat. Loop until the reviewer has nothing left to say, then
print:

> Spec and plan are ready to be built. Start a fresh session with this prompt:

followed by the build prompt `/slice` printed in Step 3.5, verbatim — see
`.agents/skills/slice/references/build-prompt.md`. The reviewer approves by
starting that session, not by a word typed into this one; this session
files nothing and builds nothing either way.

### 9. Hand off

The build session files the slices first, through `/build`'s pre-flight
(`/slice specs/<feature>.md --file --approve`) — this planning session filed
nothing. `/build` then runs the plan block `/slice` wrote top to bottom: the
`- [ ]` row under each `### Slice` heading is a slice header, claimed
through `/task-registry` when its first `TDD:` child starts and closed when
the last one passes, never dispatched to a coder directly — see
`.agents/skills/slice/SKILL.md` for the plan block's grammar. `/build` does
not read the filed task body, so the plan block is self-sufficient: every
`[ ] TDD:` row names the criterion it pins. When an implementation
contradicts the spec, `/build` stops and the change comes back here — the
spec is the contract, and `/wrap-up-session` reconciles it when the
implementation surface moves.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The issue already describes the design" | It describes a wish. Ownership, failure units and transition tables are not in it until you write them. |
| "Constraints are obvious" | Unwritten constraints are the ones the agent violates. One line each, with the check that would catch a violation. |
| "One issue is simpler than five slices" | One issue gives `/build` no order and the reviewer no checkpoint. Slices are the review's leverage. |
| "The reviewer said it looks good before I rendered" | Approval attaches to the rendered document. Render, then ask. |
| "I'll settle the data model while building" | Data outlives code. It is the most expensive element to get wrong and the cheapest to review now. |
| "A diagram is decoration" | The diagram is where the missing arrow — the timeout nobody owns — becomes visible. |
| "Filing now saves a round-trip" | Filing is `/build`'s pre-flight, in the build session. Filing here publishes a design nobody has reviewed yet. |
| "I did not read that module but I know how it works" | Then it is `UNVERIFIED`. A confident wrong path costs the builder hours. |

## Red Flags — STOP

- A task was filed in the planning session
- A contract row with no error semantics or no idempotency answer
- A status field without a transition table
- A constraint without a detection method
- A slice that depends on a later slice
- A path or symbol not read during recon, presented without `NEW` or `UNVERIFIED`
- A reviewer finding answered in chat but absent from the spec

## Integration

- **Replaces**: `/brainstorm` → `/plan` for changes that meet the *When to Use*
  bar. Not a replacement for `/debug` (bugs) or `/prd` (greenfield projects).
- **Calls**: `task-registry show` (intake, Step 1); `/grilling` (§2.5);
  `/slice` (Step 3.5, which owns sizing, the plan block and filing);
  `.agents/skills/visual-recap/scripts/visual-render.py` (render); `critic` (Step 5).
- **Precedes**: `/build`, which a fresh session starts with the build prompt
  this skill prints; that session, not this one, files the plan block and the
  slice tasks. `/auto-push` and `/yolo` still start from `/plan`; this skill is
  the supervised entry point.
- **Pairs with**: `/software-design-expert-review` after the build, auditing
  what was built against what was designed; `/wrap-up-session`, which keeps
  `specs/<feature>.md` a living contract.

## Key Principles

- **Review where the leverage is.** Human hours go to the four elements and the
  build order, not to the pull request.
- **Ground every claim.** `file:line` for what exists, `NEW` for what does not,
  `inferred` for what you guessed.
- **Make illegal states unrepresentable — in the document too.** A transition
  table, an outcome type and a constraint check can be verified; prose cannot.
- **The HTML is the gate.** Approval attaches to the rendered document, and the
  spec behind it is the contract `/build` and `/wrap-up-session` hold.
