---
name: plan
description: Interview user, write a feature spec, slice it into session-sized build steps, and end with a build prompt for a fresh session. Use for any non-trivial feature before coding.
argument-hint: "[feature description]"
disable-model-invocation: false
harness: universal
---

# /plan — Structured Spec + Plan Mode

Enter plan mode to define a spec and task breakdown **before any code is written**.

## Model Routing

Sub-agent delegations follow the Model Routing table in `/build` (planner tier for planning/architecture, scout tier for exploration).
- **Claude Code** — pass `model` explicitly per that table, except for *ceiling*-tier
  agents (`code-reviewer`, `security-reviewer`, `software-design-expert-review`,
  `critic`), which take no `model` so they inherit the session model. `critic` carries a
  **planner floor**: pass the planner alias if the session model is below planner tier.
  See `.agents/references/model-routing.md`.
- **Pi** — no per-call model params; routing resolves from `subagents.agentOverrides` (requires the `pi-subagents` extension). Use `scout` for codebase exploration.
- **Codex** — use the managed `explorer` role for read-only codebase
  exploration and the managed `planner` role for planning. Resolve `critic`'s
  planner floor against the parent tier before dispatch; inherit when the
  parent meets the floor. The provider mapping lives in `config/agent-policy.toml`.
- The planning phase requires the strongest reasoning model for architecture decisions

## Steps

### 0. Pre-Flight — Context Loading

Before interviewing, load available project context:

1. **Check this repository first — before any outward search.** Your own merged
   work is the highest-priority prior art, and the one category `gh search code`
   and package registries structurally cannot find.
   - `git rev-list --count HEAD..@{upstream}` — if non-zero, **STOP and pull**. A
     stale clone makes every subsequent read an incomplete picture, and a spec
     written against it can re-specify a capability that already shipped.
   - `gh pr list --state merged --limit 20` — scan titles for the capability you
     are about to spec. A closed-but-superseded PR often names the merged one.
   - Grep the tree for a skill, module, or script that already covers it. If one
     exists, the plan is an extension of it or a justification for not extending.

   Only once this comes back empty do the outward rungs apply (`gh search repos`,
   `gh search code`, package registries).

2. **Check for `tasks/project-context.md`** — if exists, read it for broader project context (architecture, conventions, protection list)
3. **Check for `tasks/backlog.md`** — if exists and an argument was provided:
   - Match the argument against backlog item names
   - If match found: use the backlog item description as the starting point for the spec
   - Mark the item as `[~]` (in progress) in `tasks/backlog.md`
   - If no match: list available `[ ]` items and ask user to pick one
4. **If no backlog exists**: proceed normally (interview from scratch)

### 1. Interview the User, Carrying Settled Decisions Forward
Ask clarifying questions to fully understand the feature:
- What is the desired behavior? What problem does it solve?
- What are the inputs and outputs?
- What are the edge cases and failure modes?
- What constraints exist (performance, security, backwards-compatibility)?
- Which existing files/components are likely involved?
- What does "done" look like? How will we verify it works?

Before asking, look for a settled tree: a `specs/<feature-name>.md` that
already carries a § Decisions table, or a `/grilling` run in this
conversation whose frontier is already empty for this feature. `/grill-me`
and `/brainstorm` are the user's optional precursors to `/plan` — a feature
may go through either and never reach this skill. When a settled tree
exists, print `DECISIONS CARRIED: <n> from <spec path | conversation>` and
ask only the `open` rows plus whatever the six questions above still leave
unanswered — settled rows are never re-asked. With neither source, interview
as described above and fill § Decisions from the answers.

If working from a backlog item, use its description and the PRD context to pre-fill known answers. Only ask about gaps.

Wait for complete answers before proceeding.

### 1.5. Escalate When the Design Bar Is Met

Before writing the spec, check whether a settled answer meets the bar in
`.agents/skills/system-design-planning/SKILL.md` § When to Use. When it
does, print `Escalating to /system-design-planning: <criterion>` and invoke
`/system-design-planning` with the decisions gathered so far — it does not
re-ask them.

### 2. Write the Spec (MUST persist to disk)

For a UI feature, read the project's `DESIGN.md` and carry its direction,
references and visual rules into the spec. If an existing UI has no brief,
stop with `SelectionRequired` before planning; non-UI work skips this step.
A new route/screen or substantial redesign is a major UI concept: write a
reviewable `design/concepts/<feature>.html`, compute its SHA-256 from the saved
bytes, and cite its path and digest in a § Decisions row before `/slice` prints
the build prompt. The row must tell the owner to start the build with a prompt
containing that exact digest; `/build` records the digest-bound receipt. Re-read
the bytes before emitting the prompt so a stale digest cannot be approved.
An owner-started prompt is required for a major UI build; an unattended run
waits. A localized UI change follows the approved brief without a new concept.

This step is not complete until both conditions hold:

1. The file `specs/<feature-name>.md` exists on disk (verify with `ls specs/`)
2. You have printed its **absolute path** in your message output

**Forbidden:**
- Presenting the spec inline as a code block without writing the file
- Claiming the spec is "drafted" without a path to point to
- Asking the user "should I save this?" — always save, then confirm location

**Required output format at end of Step 2:**

```
✓ Spec written: /absolute/path/to/specs/<feature-name>.md
```

If you cannot write the file (permission error, directory missing), STOP and report the error — do not fall back to inline presentation.

A spec is a **living contract**: it states what the code does now, not what it
was once going to do. Write every section in the present tense, and declare the
implementation surface in frontmatter so `/wrap-up-session` can find this spec
again when that surface changes. Acceptance Criteria are ordinary bullets — a
checkbox records an intention, and a spec records a fact.

Spec template:

```markdown
---
implementation_paths:
  - src/feature/**
  - tests/test_feature.py
---

# Spec: [Feature Name]

## Summary
[Optional: two to four sentences — what changes, for whom, the one decision not to miss]

## Behavior
[What the feature does, from the user's perspective]

## Inputs
[What data/events trigger this feature]

## Outputs
[What it produces — return values, side effects, UI changes]

## Edge Cases
- [Edge case 1 and expected behavior]
- [Edge case 2 and expected behavior]

## Risks
[Optional]

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | [what could go wrong] | M | H | [how it is caught or prevented] | [1] |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | [question] | [decision] | user | [reason] |

`Source` is `user` for an answer the user gave in the interview, `assumed`
for one `/plan` picked without asking (state why in the row), and `open` for
one nobody has decided yet.

## Open questions
[Optional]

| ID | Question | Blocks | Needed from |
|---|---|---|---|
| Q1 | [a fact someone outside the session must supply] | [slice numbers, or none] | [who] |

## Acceptance Criteria
- AC1: [Verifiable criterion 1]
- AC2: [Verifiable criterion 2]
- AC3: [Verifiable criterion 3]

## Implementation Paths
- `src/feature/**` — [what this code does for the feature]
- `tests/test_feature.py` — [what it verifies]
```

A vague requirement is rewritten as a measurable acceptance criterion before
it enters § Acceptance Criteria, and the rewrite is shown to the user.

The optional sections are typed on the visual plan: § Summary becomes its
lead, a § Risks row with high impact and no mitigation and a § Open questions
row that `Blocks` a slice become blockers, and an `open` decision or a blocking
question keeps `/slice` from printing a build prompt. Omit a section rather
than fill it with placeholders.

**Write it to be read:** remove repetition, empty qualifiers and workflow
narration — the spec states what the system does, not how the interview went —
and write connected sentences, not slash-packed shorthand: "an export over
50000 rows is split into parts" over "export/split/50k".
§ Build Order is not written here — `/slice` writes it in Step 3.

`implementation_paths` is the matching contract; the `## Implementation Paths`
section explains each path's role to a human. Paths are repository-relative
POSIX paths or globs — never absolute, never `..`. Only `*` and `?` (neither
crosses `/`) and `**` (which does) are accepted. Declare the complete current
surface, including tests and configuration whose changes can alter or verify the
behavior, not merely the files this session touched.

### 3. Slice the Spec

Invoke `/slice specs/<feature-name>.md [--issue #N]`. It sizes the spec's
acceptance criteria into session-sized slices, writes § Build Order and the
plan block into `tasks/todo.md` per its own grammar, and prints the build
prompt — see `.agents/skills/slice/SKILL.md` for what each output means and
how it is written. `/plan` does not size slices, write a plan block, or
print a build prompt itself.

### 4. Present

Show the user both the spec and the plan block `/slice` wrote. Ask no
question — the fresh session that opens with the build prompt is the review
gate, not a word typed into this one. Change requests are applied in place:
edit the spec, then re-run Step 3, for as long as the user keeps making
them.

**A review export is a change request.** The visual plan's **Export review**
copies a block the user pastes back here:

```text
Review of specs/<feature>.md @ <sha256[:12]>
D4: pick B — <note>
Q2: answer — <text>
AC5: ok
S4: questioned — <note>
```

Compare its hash with `python3 .agents/skills/visual-plan/scripts/plan_render.py --hash specs/<feature>.md`
first. A mismatch is refused, naming both hashes — `review is of <block hash>,
the spec is now <current hash>: re-render the plan and review again` — and
nothing is applied. On a match, apply every line:

- `<ID>: answer — <text>` settles the question: move it into § Decisions as a
  `settled` row when it decides something, otherwise delete it from
  § Open questions.
- `<ID>: pick <letter> — <note>` settles the open decision on that option,
  lettered in the order its Options cell lists them; the note joins the
  rationale.
- `<ID>: questioned — <note>` becomes a spec edit that resolves the note, or
  an `open` decision row when it needs the user's call.
- `<ID>: ok` changes nothing.

Then re-run Step 3, so the Build Order, the plan block and the prompt match
the edited spec.

### 5. Divergence Check

If `tasks/project-context.md` exists, compare the new spec's decisions against it:

- New dependencies or libraries not in the `[ARCHITECTURE]` section
- Data model changes (new entities, changed relationships)
- Contradictions with stated technical architecture
- New non-functional requirements not in `[NON-FUNCTIONAL]`

**If divergence detected**, prompt the user:
> "This spec introduces [specific change, e.g., 'Redis for caching — not in current architecture']. Update the PRD and project context? (y/n)"

If yes:
1. Update only the affected sections in the source PRD (`specs/prd-*.md`)
2. Regenerate `tasks/project-context.md` from the updated PRD
3. Append the change to the PRD's Revision History table

If no: note the divergence in the spec as a conscious decision and proceed.

### 6. Hand Over

The session's last message is:

```
Spec and plan are ready to be built. Start a fresh session with this prompt:
```

followed by the build prompt, verbatim from § Build Order (see
`.agents/skills/slice/references/build-prompt.md` for the template). `/plan`
files nothing and never invokes `/build`; both happen only in the session
that prompt starts.
