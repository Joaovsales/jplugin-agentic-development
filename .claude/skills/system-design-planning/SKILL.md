---
name: system-design-planning
description: Turn an issue or a feature idea into an upstream architecture review — system design, component contracts, data models, constraints, and a dependency-ordered build plan — rendered as a self-contained HTML document a human approves before anything is filed or built. On approval it files one issue per build slice and writes the TDD plan /build consumes unchanged. Use instead of /brainstorm + /plan when the change crosses a component boundary, adds or changes a persisted data model, or introduces or changes an external contract.
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
reviews the rendered document. Only after approval does it file one issue per
build slice and write the `[ ] TDD:` plan that `/build` executes unchanged.

Worked example: `specs/upsert-depends-on.md` and its render
`specs/upsert-depends-on.plan.html` — the design for the `--depends-on` flag that
Step 8 asks for, produced by running this skill against its own shortcut.

## The Iron Law

```
NOTHING IS FILED AND NOTHING IS BUILT UNTIL A HUMAN HAS APPROVED THE RENDERED ARCHITECTURE DOCUMENT.
```

"Approved" is the reviewer's word in chat **after** the `.plan.html` path was
printed. Silence, a partial answer, or agreement given before the render is not
approval.

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
planner tier. See `CLAUDE.md` § Model Routing.

## The Process

### 1. Intake

- `#N` or a registry task ID → read it through
  `python3 .agents/skills/task-registry/scripts/task-registry.py show <ref>`,
  never a tracker CLI. Title, body, criteria and labels are the problem statement.
- Free text → the text is the problem statement.
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
| Build order | slices — each: delivers, depends on, contract exposed, acceptance criteria, size | can each slice ship alone, and is the riskiest unknown first? |
| Decisions | hard-to-reverse choices, recommended option, what makes each option wrong | what is expensive to change later? |
| Acceptance Criteria, Implementation Paths | the `/plan` living-contract format, present tense, plain bullets, `implementation_paths` frontmatter | — |

Rules that make the spec reviewable rather than readable:

- An `inferred` constraint is a question to the reviewer, not a fact.
- Every status field has a transition table, including the in-doubt state when
  an external call can time out.
- Every cross-boundary call states its behaviour on timeout and on duplicate
  delivery.
- Slices are ordered so contracts and data models land before their consumers,
  every slice leaves the suite green, and the slice with the largest unknown is
  first — a spike slice if needed. A slice that depends on a later slice is a
  defect in the order.

Required output: `✓ Spec written: /absolute/path/specs/<feature>.md`

### 4. Self-review

Run `references/review-card.md` top to bottom against the spec. Each "no"
becomes an edit to the spec or a row in *Decisions* — never a remark in chat.

### 5. Adversarial pass (conditional)

When any slice changes a persisted schema or an external contract, dispatch
`critic` under the Review Dispatch Contract in `CLAUDE.md`. Item 1 has no empty
form, so the spec itself is the diff: `git diff --no-index /dev/null
specs/<feature>.md`, inline when small, else truncated-plus-path per
*Large-Artifact Handoff*. Then the spec path and its acceptance criteria
verbatim, `deferrals: none`, the boundary "review the design in this spec, not
the repository — check only that its `file:line` claims are true", and the
four-axis output format. Every finding is answered in the spec — as an edit
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

### 7. Human review gate

Print both paths and this request, then stop:

> Review the rendered document. Reply with findings as
> `[constraints|system-design|contracts|data-models|build-order] <finding> — <evidence>`,
> or **approved**.

Approval is the bare word. A reply that contains any finding line is findings,
not approval, even when it also contains the word "approved".

On findings: edit the spec, re-run Steps 4 and 6 to the same paths, reprint the
paths. Every finding is answered in the spec, not in chat. Loop until approved.

### 8. File slices (after approval only)

One task per slice, in build order. Three moves, in this order: dry-run,
plan block, apply. The dry run prints each slice's id; the plan block seeds a
row carrying that id; the apply then refreshes the seeded row in place instead
of appending a stray `[ ]` row at the end of `tasks/todo.md`.

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
  --derive-id design --spec specs/<feature>.md --fold-title \
  --title '<slice name>' --kind feature \
  --summary 'Slice <n>/<total>: <what it delivers>. After: <previous slice name, or none>.' \
  --criterion '<acceptance criterion>' --criterion '<acceptance criterion>' \
  --evidence 'design: specs/<feature>.md § Build order, slice <n>'
```

Read the preview (`upsert: would create design.<…> (<destination>)`), write
the plan block below, then re-run the same command with `--apply --approve`.

- `--approve` carries the reviewer's word into the write gate. Without it,
  `upsert` honours `require_write_approval` and every slice lands
  `local-pending` — three "publication pending" lines and no issue. The dry run
  never carries it.
- `--kind` is `feature` for new capability, `task` for internal restructuring,
  `operational` for a spike or a migration.
- An unreachable tracker still reports `local-pending`; that is reported as
  such, never retried silently.
- `TODO(shortcut):` `upsert` has no dependency flag, so ordering lives in the
  summary's `After:` line and in the plan block order below. Upgrade path: a
  `--depends-on` flag on `upsert`; the index already parses `(blocked-by: …)`.

The slice number lives in the summary, not the title: `--fold-title` folds the
title into the id, so a slice keeps its task when a re-plan renumbers it and
mints a new one only when it is renamed. Slice names are frozen at first
filing; a renamed slice retires the old task explicitly.

The plan block. If a `## Plan: <feature>` block already exists — an interrupted
filing, a second approval round — replace its `### Slice` sections in place;
otherwise **append**. Never leave two blocks for one feature: `/build` runs
every `[ ]` row it finds. `> Spec:` stands alone on its line —
`/wrap-up-session` anchors the path to end-of-line and drops the association
when anything follows it.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
> Visual: specs/<feature>.plan.html
> Approved <YYYY-MM-DD> by <reviewer>

### Slice 1/<total>
- [ ] <slice name> <!-- task-id: design.<id> -->
  [ ] TDD: <test that pins acceptance criterion 1> -> <minimal implementation>
  [ ] TDD: <test that pins acceptance criterion 2> -> <minimal implementation>

### Slice 2/<total>
- [ ] <slice name> <!-- task-id: design.<id> -->
  [ ] TDD: <test> -> <implementation>
```

The `- [ ]` row under each heading is the registry's row: the apply rewrites it
with the summary and the issue link, and `/build` reads it as a slice header,
not as work. The indented `[ ] TDD:` rows are the work.

Required output: `✓ Plan written: /absolute/path/tasks/todo.md`, then one line
per slice: `✓ Filed: <task-id> → <#N | local, publication pending>`.

### 9. Hand off

`/build` runs the plan block top to bottom. The `- [ ]` row under each `### Slice`
heading is a slice header: `/build` claims it through `/task-registry` when its
first `TDD:` child starts and closes it when the last one passes, and never
dispatches a coder against it. It does not read the filed task body, so the
plan block is self-sufficient: every `[ ] TDD:` row names the criterion it
pins. When an implementation contradicts the spec,
`/build` stops and the change comes back here — the spec is the contract, and
`/wrap-up-session` reconciles it when the implementation surface moves.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The issue already describes the design" | It describes a wish. Ownership, failure units and transition tables are not in it until you write them. |
| "Constraints are obvious" | Unwritten constraints are the ones the agent violates. One line each, with the check that would catch a violation. |
| "One issue is simpler than five slices" | One issue gives `/build` no order and the reviewer no checkpoint. Slices are the review's leverage. |
| "The reviewer said it looks good before I rendered" | Approval attaches to the rendered document. Render, then ask. |
| "I'll settle the data model while building" | Data outlives code. It is the most expensive element to get wrong and the cheapest to review now. |
| "A diagram is decoration" | The diagram is where the missing arrow — the timeout nobody owns — becomes visible. |
| "Filing now saves a round-trip" | Filing before approval publishes a design nobody agreed to. |
| "I did not read that module but I know how it works" | Then it is `UNVERIFIED`. A confident wrong path costs the builder hours. |

## Red Flags — STOP

- A task was filed before the word "approved" appeared in chat
- A contract row with no error semantics or no idempotency answer
- A status field without a transition table
- A constraint without a detection method
- A slice that depends on a later slice
- A path or symbol not read during recon, presented without `NEW` or `UNVERIFIED`
- A reviewer finding answered in chat but absent from the spec

## Integration

- **Replaces**: `/brainstorm` → `/plan` for changes that meet the *When to Use*
  bar. Not a replacement for `/debug` (bugs) or `/prd` (greenfield projects).
- **Calls**: `task-registry show` (intake) and `upsert` (filing);
  `.agents/skills/visual-recap/scripts/visual-render.py` (render); `critic` (Step 5).
- **Precedes**: `/build`, which consumes the plan block and the slice tasks
  unchanged. `/auto-push` and `/yolo` still start from `/plan`; this skill is
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
