---
name: brainstorm
description: Explore a feature idea through divergent design thinking before committing to a spec. Use before /plan for non-trivial features requiring design decisions.
argument-hint: "[feature idea or problem statement]"
disable-model-invocation: false
harness: universal
---

# /brainstorm — Divergent Design Exploration

## Overview
Step back and ask what you're really trying to do. Explore the problem space before narrowing to a solution.

## The Hard Gate

```
DO NOT invoke /plan, /build, /tdd, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.
```

## The Process

### Step 1 — Explore Context
- Read existing codebase structure (package.json, directory layout, key files)
- Check for related specs in specs/, prior plans in tasks/todo.md
- Grep tasks/solutions/ frontmatter (architecture-decision, pattern docs) for architectural context and past decisions
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

### Step 3 — Ask Clarifying Questions
Ask questions **one at a time** to understand the full picture:
- What problem does this solve? Who benefits?
- What are the constraints (performance, security, backwards-compat)?
- What does "done" look like?
- Are there examples of similar features in the codebase or elsewhere?

**Prefer multiple-choice questions** when possible — they're faster for the user and reduce ambiguity.

Do NOT dump all questions at once. Ask one, wait for answer, then ask the next based on the response.

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

## Acceptance Criteria
- [Verifiable criterion 1]
- [Verifiable criterion 2]

## Implementation Paths
- `src/feature/**` — [what this code does for the feature]
- `tests/test_feature.py` — [what it verifies]
```

Acceptance Criteria are ordinary bullets, and every section states current
behavior in the present tense. Full path rules live in `/plan` § *Write the Spec*.

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
- **One question at a time** — respect the user's attention
- **Show trade-offs** — never present a single option as the only way
- **Hard gate on implementation** — no code until design is approved
- **Scale to complexity** — simple features need less ceremony
