---
name: brainstorm
description: Explore a feature idea through divergent design thinking before committing to a spec. Use before /plan for non-trivial features requiring design decisions.
argument-hint: "[feature idea or problem statement]"
disable-model-invocation: false
harness: universal
# TODO(shortcut): Step 3 restates /grilling's round format so a session that fails to load the
# primitive still asks in rounds; the cost is that the load has no reply-level tell. Upgrade path:
# shrink Step 3 to a pointer once /eval Mode A shows the chain holding without the restatement.
---

# /brainstorm — Divergent Design Exploration

## Overview
Step back and ask what you're really trying to do. Explore the problem space before narrowing to a solution. The interview runs in frontier rounds through `/grilling`, and the vocabulary it settles is written to the glossary as it settles.

## The Hard Gate

```
DO NOT invoke /plan, /build, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.
```

## The Process

### Step 1 — Explore Context
- Read existing codebase structure (package.json, directory layout, key files)
- Check for related specs in specs/, prior plans in tasks/todo.md
- Grep tasks/solutions/ frontmatter (architecture-decision, pattern docs) for architectural context and past decisions
- Read `tasks/concepts.md` so Step 3 can challenge the user's terms against the existing glossary
- Understand what already exists before proposing anything new

**Reading prior art on a JS-rendered page.** `WebFetch` returns the empty shell
for an SPA and gives no signal that it did, so a page can read as "nothing there"
when the content simply had not run yet. If `lightpanda fetch <url>` is available
it executes the scripts first and dumps HTML or markdown. It is optional — when
it is absent, use `WebFetch` and say what you could not read. **A missing
lightpanda is not an error and never blocks the exploration.**

### Step 2 — Offer Visual Aids
If the topic benefits from diagrams, mockups, or flowcharts:
- Offer to create ASCII diagrams, Mermaid charts, or component trees
- Visual aids help align understanding before committing to design

### Step 3 — Interview Through `/grilling`
Invoke `/grilling` with the problem statement as the root of the design tree and these four stock questions as the seed frontier:
- What problem does this solve? Who benefits?
- What are the constraints (performance, security, backwards-compat)?
- What does "done" look like?
- Are there examples of similar features in the codebase or elsewhere?

Rounds arrive in `/grilling`'s `❓` / `➡️` format: the whole frontier at once, numbered, a recommended answer on every question. A user who set `/grilling`'s opt-out line gets one question per turn instead; that opt-out applies here unchanged. **Prefer multiple-choice bodies** — they're faster for the user and reduce ambiguity. Facts are looked up by a Scout-tier sub-agent; decisions are put to the user.

While the interview runs, the domain layer in `references/domain-modeling.md` is active: challenge terms against `tasks/concepts.md`, sharpen vague ones, stress-test relationships with concrete scenarios, cross-reference claims with the code, write each resolved project-specific term to `tasks/concepts.md` the moment it resolves, and offer — never assume — an architecture decision when all three of its gates hold.

The moment a term resolves is the user's answer. The reply to a round opens with the glossary writes that round's answers settled — the `Edit` to `tasks/concepts.md`, then one line per term (`glossary: **quarantine** written`) — before it asks the next frontier. A reply that names a new project term, or says one is now settled, and asks another question without having written it has skipped this step.

Step 3 ends when the frontier is empty and the user confirms the understanding is shared. The settled decisions constrain Step 4's options rather than being re-asked.

### Step 4 — Propose 2-3 Approaches
Present distinct design options with trade-offs:

```markdown
## Option A: [Name]
**Approach**: [How it works]
**Pros**: [Benefits]
**Cons**: [Drawbacks]
**Complexity**: [Low/Medium/High]
**Files affected**: [Key files]

## Option B: [Name]
**Approach**: [How it works]
**Pros**: [Benefits]
**Cons**: [Drawbacks]
**Complexity**: [Low/Medium/High]
**Files affected**: [Key files]

## Recommendation
[Which option and why, with clear reasoning]
```

### Step 4.5 — Pre-mortem Analysis
For each proposed approach, run a pre-mortem:

> "It's 3 months from now and this approach failed. Why?"

Generate **3-5 specific failure scenarios** per approach:
- Integration risks (breaks existing features, incompatible with current patterns)
- Scale issues (works for 10 users, breaks at 10,000)
- Maintenance burden (hard to modify, debug, or extend later)
- Hidden dependencies (assumes library stays maintained, API stays stable)
- Team friction (requires knowledge most developers don't have)

Add these failure scenarios to the trade-off table for each approach. Highlight any approach where a failure scenario is both **likely AND high-impact**.

### Step 5 — Present Design Sections
For complex features, break the design into digestible sections:
- Present each section (architecture, data flow, error handling, testing) separately
- Wait for user feedback on each section before moving to the next
- Scale depth to complexity — simple features get a single summary

### Step 6 — Write the Design Spec
Once the user approves a direction, write a formal spec to `specs/<feature-name>.md`:
- Architecture overview
- Component breakdown
- Data flow
- Error handling strategy
- Testing approach
- Acceptance criteria

Use the same living-contract format `/plan` writes, so a brainstormed spec is
maintained by `/wrap-up-session` on equal terms with a planned one. A design spec
that skips the metadata is invisible to reconciliation and goes stale first —
precisely because exploratory work moves the most:

```markdown
---
implementation_paths:
  - src/feature/**
  - tests/test_feature.py
---

# Spec: [Feature Name]

[Architecture, components, data flow, error handling, testing approach]

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | [question] | [decision] | user | [reason] |

## Acceptance Criteria
- [Verifiable criterion 1]
- [Verifiable criterion 2]

## Implementation Paths
- `src/feature/**` — [what this code does for the feature]
- `tests/test_feature.py` — [what it verifies]
```

Acceptance Criteria are ordinary bullets, and every section states current
behavior in the present tense. Full path rules live in `/plan` § *Write the Spec*.
Use the canonical terms settled in Step 3; a spec that needs a term the glossary
does not have reopens the interview rather than coining one silently. § Decisions
rows are all `Source: user` — Step 3 settled them through the interview, never
by assumption — so `/plan` Step 1 can print `DECISIONS CARRIED` and carry them
forward instead of re-asking.

### Step 7 — Self-Review the Spec
Before presenting to the user, check the spec for:
- Placeholders or "TBD" items (remove or resolve them)
- Contradictions between sections
- Ambiguous language that could be interpreted multiple ways
- Missing edge cases
- Testability — can every criterion be verified?

### Step 8 — User Approval
Present the complete spec. Ask:
> "Does this design meet your requirements? Confirm with 'y' to proceed to planning."

**Do not proceed without explicit approval.**

### Step 9 — Hand Off to /plan
After approval, invoke `/plan` with the approved spec as input to create the task breakdown.

## Multi-System Projects
For features spanning multiple subsystems:
- Decompose into independent sub-projects
- Each sub-project gets its own design section
- Identify integration points between sub-projects
- Consider which sub-projects can be built in parallel

## When NOT to Use /brainstorm
- Trivial changes (typo fix, config update, small bug fix)
- Feature is already well-defined with clear requirements
- User explicitly says "just do it" or provides a complete spec

Go directly to /plan instead.

## Key Principles
- **Diverge before converging** — explore options before committing
- **Rounds, not drips: ask the whole frontier, recommend on every question** — one numbered round with a ➡️ on each question beats a drip of single questions, unless the user's `/grilling` opt-out line is set, which wins
- **Facts are the agent's job, decisions are the user's** — look up what the environment can settle; ask only what it cannot
- **Glossary is a glossary** — `tasks/concepts.md` holds definitions only; decisions and implementation detail go to the spec or the store
- **Show trade-offs** — never present a single option as the only way
- **Hard gate on implementation** — no code until design is approved
- **Scale to complexity** — simple features need less ceremony
