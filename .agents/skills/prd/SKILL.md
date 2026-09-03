---
name: prd
description: Interview the user about a greenfield project, produce a structured PRD, ordered backlog, and agent context file. Use as the entry point for new projects.
argument-hint: "[project idea or description]"
disable-model-invocation: false
harness: universal
---

# /prd — Product Requirements Document Generator

## Overview

Entry point for greenfield projects. Interviews the user, produces a structured PRD, decomposes it into an ordered backlog, and generates a compressed project-context file for agent consumption.

## Model Routing

**This command MUST use `model: opus` for all agent delegations.**
- PRD creation is a planning/architecture activity — requires strongest reasoning
- For codebase exploration or searches, use `model: "haiku"` via the Explore agent

## The Hard Gate

```
DO NOT invoke /plan, /build, or write any code until the PRD is approved
and the backlog is generated.
```

## Outputs

| File | Purpose | Audience |
|------|---------|----------|
| `specs/prd-<name>.md` | Full PRD document | Humans + planning agents |
| `tasks/backlog.md` | Ordered work items grouped by phase | Humans + `/plan` |
| `tasks/project-context.md` | Compressed, section-labeled agent briefing | Sub-agents only |

## The Process

### Step 1 — Explore Existing Context

- Read codebase structure if anything exists (package.json, directory layout, key files)
- Grep `tasks/solutions/architecture/` for prior decisions
- Check if a PRD or backlog already exists:
  - If PRD exists: ask "Update the existing PRD or create a new one?"
  - If backlog exists with completed items: warn that regenerating will need to preserve `[x]` items

**Researching an external product or competitor.** `WebFetch` returns the empty
shell for a JS-rendered page without signalling that it did, which reads as an
absence of information rather than a failure to read. Where `lightpanda fetch
<url>` is installed it runs the page's scripts first and dumps HTML or markdown.
It is optional — fall back to `WebFetch` and record what you could not read.
**A missing lightpanda is not an error and never blocks the interview.**

### Step 2 — Hybrid Draft + Interview

From the user's initial prompt and any existing context:

1. **Draft a skeleton PRD** covering as many sections as possible from available information
2. **Identify gaps** — sections where information is missing or ambiguous
3. **Interview the user on gaps only**, one question at a time
4. **Prefer multiple-choice questions** — faster for the user, reduces ambiguity
5. Do NOT dump all questions at once. Ask one, wait for answer, then ask the next based on the response.

Focus interview questions on:
- Business context and problem (if not clear from prompt)
- User personas and their key needs
- Must-have vs. nice-to-have features
- Technical constraints or preferences
- Non-functional requirements (performance, security, scale)
- What's explicitly out of scope

### Step 3 — Write the PRD

Write `specs/prd-<name>.md` with the following structure.

Sections 1-8 are **traditional product requirements** (for humans and planning agents).
Sections 9-11 are the **agent-optimization layer** (for decomposition and execution).

```markdown
# PRD: [Project Name]

## 1. Overview
- Project name and one-line description
- Problem statement: what pain exists today
- Vision: what the world looks like after this is built
- Target users / personas (name, role, key need)

## 2. Goals & Success Criteria
- 3-5 measurable project goals
- Definition of "done" for the overall project
- Key metrics or outcomes that indicate success

## 3. User Stories
Grouped by feature area / persona.
Format: As [persona], I want [action], so that [benefit]
Priority: Must-have / Should-have / Nice-to-have (MoSCoW)

## 4. Functional Requirements
Organized by module or feature area.
Each requirement has:
- Description (what it does)
- Acceptance criteria using EARS notation:
  WHEN [condition] THE SYSTEM SHALL [behavior]
- Priority (Must / Should / Nice)

## 5. Non-Functional Requirements
- Performance targets (response times, throughput)
- Security requirements (auth, data protection, compliance)
- Scalability expectations
- Accessibility standards
- Browser/device/platform support

## 6. Technical Architecture
- Tech stack (languages, frameworks, databases, infra)
- System boundaries and integrations
- Data model overview (key entities and relationships)
- Key architectural decisions and rationale

## 7. Out of Scope / Non-Goals
- Explicit list of what this project does NOT include
- Things that might seem implied but are deliberately excluded
- Future considerations parked for later

## 8. Dependencies & Assumptions
- External services, APIs, third-party tools
- Team/resource assumptions
- Technical assumptions

## 9. Phases & Dependency Order
- Ordered phases, each ending in something verifiable
- Each phase lists which functional requirements it addresses
- Explicit dependencies: "Phase 2 requires Phase 1's API endpoints"
- Phase sizing: each phase should be 1-3 specs worth of work

## 10. Protection List
- Files, systems, or patterns that must NOT be modified
- Existing functionality that must be preserved
- External contracts or APIs that cannot change
(For greenfield: "No protected files — greenfield project.")

## 11. Risks & Mitigations
- Technical risks (new technology, complex integrations)
- Scope risks (requirements likely to change)
- Mitigation strategy for each

## Revision History
| Date | Section | Change | Trigger |
|------|---------|--------|---------|
| YYYY-MM-DD | Initial | PRD created | /prd |
```

### Step 4 — Self-Review

Before presenting to the user, check the PRD for:
- **No placeholders or TBD items** — resolve or remove them
- **All acceptance criteria are boolean-testable** — EARS notation, no subjective language
- **Non-goals section is populated** — AI cannot infer from omission
- **Phases have clear dependency ordering** — no circular dependencies
- **Protection list is populated** — even if minimal for greenfield
- **No contradictions between sections**
- **No ambiguous language** that could be interpreted multiple ways

### Step 5 — User Review

Present the full PRD. Ask:
> "Does this PRD capture your requirements? I can adjust any section. Confirm with 'y' to generate the backlog."

Iterate on feedback until approved. **Do not generate backlog without explicit approval.**

### Step 6 — Generate Backlog

Decompose the PRD into `tasks/backlog.md`:

```markdown
# Backlog: [Project Name]
> PRD: specs/prd-<name>.md
> Generated: YYYY-MM-DD

## Phase 1: [Phase Name]
> Dependencies: none
> Verifiable outcome: [what you can demo/test when phase is done]

- [ ] [Feature/module name] — [one-line description]
- [ ] [Feature/module name] — [one-line description]

## Phase 2: [Phase Name]
> Dependencies: Phase 1
> Verifiable outcome: [what you can demo/test when phase is done]

- [ ] [Feature/module name] — [one-line description]
- [ ] [Feature/module name] — [one-line description]
```

**Backlog item sizing rules:**
- Each item is "spec-sized" — big enough to need `/plan` but small enough to be one coherent feature
- Target: 3-8 items per phase, 2-5 phases per project
- If >5 phases or >30 items: suggest splitting into multiple PRDs or calling out an MVP phase

**Status conventions:**
- `[ ]` — not started
- `[~]` — in progress (being planned or built)
- `[x]` — done

### Step 7 — Generate Project Context

Compress the PRD into `tasks/project-context.md` for selective agent injection:

```markdown
# Project Context: [Project Name]
> Source PRD: specs/prd-<name>.md
> Generated: YYYY-MM-DD — regenerate with /prd if PRD changes

## [ARCHITECTURE]
Tech stack, system boundaries, data model overview.
Concise — facts only, no rationale.

## [PROTECTION]
Files and systems that must not be modified.

## [NON-FUNCTIONAL]
Performance, security, scalability, accessibility targets.

## [CURRENT-PHASE]
Which phase is active, what's been completed, what's next.

## [CONVENTIONS]
Naming conventions, patterns, coding standards specific to this project.
```

**Token efficiency rules:**
- Strip rationale, keep facts
- Use bullet points, not paragraphs
- No section should exceed 20 lines
- If a section is empty, write "None" — don't omit the header

### Step 8 — Present Summary

Show the user:

```
══════════════════════════════════════
  PRD COMPLETE — [Project Name]
══════════════════════════════════════

📄 PRD: specs/prd-<name>.md
📋 Backlog: tasks/backlog.md ([N] items across [M] phases)
🤖 Agent Context: tasks/project-context.md

Phase 1: [Phase Name] — [N] items
Phase 2: [Phase Name] — [N] items
...

Suggested next step:
  /plan [first-backlog-item-name]

══════════════════════════════════════
```

## Updating an Existing PRD

When `/prd` finds an existing PRD:

1. Ask: "Update existing PRD or start fresh?"
2. If updating:
   - Show current PRD sections as a starting point
   - Interview on what changed
   - Update only affected sections
   - Append to Revision History
   - Regenerate `tasks/project-context.md`
   - Regenerate `tasks/backlog.md` — preserve `[x]` items, update `[ ]` items
3. If starting fresh:
   - Archive old PRD to `specs/archive/prd-<name>-<date>.md`
   - Proceed with normal flow

## Key Principles

- **Hybrid draft + interview** — draft from available context, interview on gaps only
- **Boolean-testable criteria** — EARS notation, no subjective language
- **Explicit non-goals** — AI cannot infer from omission
- **Dependency ordering** — agents must know what to build first
- **Living document** — PRD evolves via `/plan` divergence checks and `/wrap-up-session` staleness checks
- **Two audiences** — full PRD for humans and planners, compressed context for coding agents
- **Hard gate** — no code until PRD is approved and backlog is generated
