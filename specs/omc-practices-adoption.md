# Spec: OMC Best Practices Adoption

_Date: 2026-04-04 | Source: Deep analysis of oh-my-claudecode vs coding-agent-workflow_

## Overview

Adopt the highest-value practices from oh-my-claudecode (OMC) into our workflow. These changes range from new files (Critic agent, `/deslop` skill) to incremental edits (commit trailers, evidence hierarchy). No infrastructure dependencies are added — everything remains pure markdown/shell.

## Impact Classification

Each change is classified by its impact on existing workflow behavior:

| Change | Impact | Why |
|--------|--------|-----|
| Critic agent | **MAJOR** — adds new review stage to `/build` | New adversarial gate between code-reviewer and completion |
| `/deslop` skill | **MODERATE** — new skill, integrates into `/build` Phase 3 | Runs alongside `/simplify`, new detection scope |
| Commit trailers | **INCREMENTAL** — edit to `/wrap-up-session` Step 7 | Additive change to commit message format |
| READ-ONLY review agents | **MODERATE** — changes agent behavior constraints | Review agents can no longer "helpfully" fix code they should only flag |
| Architectural circuit breaker in `/build` | **INCREMENTAL** — extends existing error handling | `/debug` already has this; `/build` gets the same pattern |
| Evidence hierarchy in `/debug` | **INCREMENTAL** — adds reference doc + edits Phase 1 prompt | Strengthens existing root-cause methodology |
| Persistence loop in `/build` | **MODERATE** — changes Phase 4 from single-pass to bounded loop | Build can now retry spec validation up to 3 rounds |
| Kill switch env vars | **INCREMENTAL** — edits hooks only | Safety valve for hook debugging |
| Pre-mortem in `/brainstorm` | **INCREMENTAL** — adds one step to existing 9-step process | New Step 4.5 between proposals and presentation |

## Detailed Behavior

### 1. Critic Agent (NEW — `.claude/agents/critic.md`)

A read-only adversarial quality gate. Unlike `code-reviewer` (constructive), Critic actively looks for flaws.

**Protocol:**
1. **Pre-commitment**: Generate 3-5 predictions about likely problems before reading the code
2. **Verification**: Read thoroughly, extract all technical claims, verify against source code
3. **Multi-perspective**: Review through 3 lenses — security engineer, new team member, ops engineer
4. **Gap analysis**: Search for what's missing (unstated assumptions, edge cases, broken dependencies)
5. **Self-audit**: Rate own confidence, check if author could refute findings, distinguish flaws from preferences
6. **Synthesis**: Produce structured verdict

**Verdicts:** `REJECT` | `REVISE` | `ACCEPT-WITH-RESERVATIONS` | `ACCEPT`
**Severity:** `CRITICAL` (blocks execution) | `MAJOR` (significant rework) | `MINOR` (suboptimal)
**Escalation:** Adversarial mode triggers when any CRITICAL finding OR 3+ MAJOR findings

**Constraints:**
- Model: `opus` (requires strongest reasoning for adversarial review)
- READ-ONLY: Write and Edit tools are conceptually blocked (instruction-level, not tool-level)
- Never manufactures problems — only reports verified issues
- No praise padding — single sentence acknowledgment if good

**Integration with `/build`:** Adds optional Phase 2.5 — Critic Review after the 2-stage code review, triggered only for complex or high-risk tasks (tasks touching auth, payments, data models, or >100 LOC changed).

### 2. `/deslop` Skill (NEW — `.claude/skills/deslop/SKILL.md`)

Detects and removes AI-generated anti-patterns that `/simplify` doesn't catch.

**Detection targets:**
- Hedge words in comments: "should", "might", "probably", "seems to", "arguably"
- Unnecessary type annotations on obvious types (e.g., `const name: string = "hello"`)
- Over-documented simple functions (docstring longer than function body)
- Defensive error handling for impossible internal cases (e.g., `catch` on a pure function)
- Filler abstractions: wrapper classes/functions that add no value
- Verbose logging that repeats the function name or obvious context
- Empty catch blocks or `catch (e) { throw e }` patterns
- Comments that restate the code: `// increment counter` above `counter++`

**Process:**
1. Identify changed files via `git diff --name-only`
2. For each file: scan for slop patterns (instruction-based, no regex engine)
3. Apply deletions — favor removing over rewriting
4. Run tests after each file to confirm no behavior change
5. Report: files cleaned, patterns removed, lines deleted

**Integration with `/build`:** Runs in Phase 3 after `/simplify`, before Phase 4 spec validation.

### 3. Commit Trailers (EDIT — `/wrap-up-session` Step 7)

Add structured git trailers to commit messages for decision audit trail.

**Trailers (all optional, include only when relevant):**
- `Constraint:` — limitations that shaped the implementation
- `Rejected:` — alternatives considered and why they were dismissed
- `Not-tested:` — known gaps in test coverage with reasoning
- `Confidence:` — HIGH | MEDIUM | LOW — self-assessed certainty

**Example:**
```
feat: add token refresh rotation

Implement automatic refresh token rotation on use with 1-hour expiry.

Constraint: Must maintain backwards compat with v2 API clients
Rejected: Considered sliding window expiry, too complex for current auth model
Not-tested: Concurrent refresh race condition under load
Confidence: HIGH
```

### 4. READ-ONLY Constraint on Review Agents (EDIT — 3 agent files)

Add explicit instruction to `code-reviewer.md`, `security-reviewer.md`, and new `critic.md`:

```
**CONSTRAINT: You are READ-ONLY.**
You MUST NOT use Write or Edit tools. Your role is to identify and report issues.
You do not fix code — you flag it for the implementing agent to fix.
If you are tempted to edit a file, STOP and report the finding instead.
```

This prevents review agents from "helpfully" modifying code they should only be evaluating. The implementing agent (backend-developer, frontend-developer) handles fixes based on review feedback.

### 5. Architectural Circuit Breaker in `/build` (EDIT — error handling)

Currently `/build` has: "Max 3 fix attempts per regression before escalating to user."

**Enhancement:** After 3 failed fixes on the same test/criterion, escalate differently:

1. **First 3 attempts**: Normal `code-debugger` delegation
2. **After 3 failures**: Spawn `planner` agent (opus) to analyze whether the spec or architecture is the problem
3. **Planner returns**: Either revised approach (continue with new plan) or "architecture problem" (halt, escalate to user with diagnosis)

This mirrors OMC's executor → architect escalation pattern.

### 6. Evidence Hierarchy in `/debug` (EDIT + NEW reference doc)

Add formal evidence strength ranking to Phase 1 delegation prompt.

**Hierarchy (strongest → weakest):**
1. Controlled reproduction (test that isolates the exact cause)
2. Primary artifacts (timestamped logs, metrics, git history)
3. Multiple independent sources converging on same explanation
4. Single code-path inference (fits observation but not uniquely discriminating)
5. Circumstantial clues (naming, temporal proximity, stack position)
6. Intuition or analogy

New reference doc: `.claude/skills/debug/evidence-hierarchy.md`

### 7. Persistence Loop in `/build` Phase 4 (EDIT)

Current Phase 4 does spec validation once and loops back if criteria fail, but has no bounds or repeated-failure detection.

**Enhancement — Bounded persistence:**
```
Phase 4 — Spec Validation (Persistence Loop)
  max_rounds: 3

  For each round:
    1. Re-read specs/[feature-name].md
    2. Walk through each Acceptance Criterion
    3. If all ✅: break → Phase 5
    4. If any ❌:
       a. Compare against previous round's failures
       b. If SAME criteria failed as last round → HALT
          (circular fix detected — escalate to user with diagnosis)
       c. If DIFFERENT failures → create new [ ] tasks, loop to Phase 1
    5. After round 3 with remaining ❌: HALT with full status report
```

### 8. Kill Switch Environment Variables (EDIT — hooks)

Add early-exit check to both hooks:

```bash
# At top of session-start.sh and auto-test-runner.sh
if [ "${DISABLE_WORKFLOW_HOOKS:-0}" = "1" ]; then
  exit 0
fi
```

This allows debugging the workflow itself without hooks interfering.

### 9. Pre-mortem in `/brainstorm` (EDIT — new step)

Add Step 4.5 between "Propose approaches" (Step 4) and "Present design" (Step 5):

**Step 4.5 — Pre-mortem Analysis:**
For each proposed approach, generate 3-5 specific failure scenarios:
- "It's 3 months later and this approach failed because..."
- Focus on: integration risks, scale issues, maintenance burden, hidden dependencies
- Add failure scenarios to the trade-off table for each approach

## Files Changed

| File | Action | Lines Changed (est.) |
|------|--------|---------------------|
| `.claude/agents/critic.md` | CREATE | ~120 |
| `.claude/skills/deslop/SKILL.md` | CREATE | ~90 |
| `.claude/skills/debug/evidence-hierarchy.md` | CREATE | ~40 |
| `.claude/skills/build/SKILL.md` | EDIT | ~40 (Phase 4 loop + circuit breaker + deslop integration) |
| `.claude/skills/wrap-up-session/SKILL.md` | EDIT | ~25 (commit trailers) |
| `.claude/skills/debug/SKILL.md` | EDIT | ~15 (evidence hierarchy in Phase 1 prompt) |
| `.claude/skills/brainstorm/SKILL.md` | EDIT | ~20 (pre-mortem step) |
| `.claude/skills/simplify/SKILL.md` | EDIT | ~5 (note about `/deslop` complement) |
| `.claude/agents/code-reviewer.md` | EDIT | ~8 (READ-ONLY constraint) |
| `.claude/agents/security-reviewer.md` | EDIT | ~8 (READ-ONLY constraint) |
| `.claude/hooks/session-start.sh` | EDIT | ~3 (kill switch) |
| `.claude/hooks/auto-test-runner.sh` | EDIT | ~3 (kill switch) |
| `.claude/settings.json` | NO CHANGE | — |
| `CLAUDE.md` | EDIT | ~15 (add critic to agents table, /deslop to skills table, model routing) |

## Acceptance Criteria

- [ ] Critic agent exists at `.claude/agents/critic.md` with 5-phase protocol, verdicts, severity levels, adversarial escalation, and READ-ONLY constraint
- [ ] `/deslop` skill exists with AI-specific detection targets, deletion-first methodology, and test-after-each-file process
- [ ] `/wrap-up-session` Step 7 includes commit trailer protocol with `Constraint:`, `Rejected:`, `Not-tested:`, `Confidence:` examples
- [ ] `code-reviewer.md` and `security-reviewer.md` include READ-ONLY constraint block
- [ ] `/build` Phase 4 has bounded persistence loop (max 3 rounds) with repeated-failure detection and halt conditions
- [ ] `/build` error handling includes architectural circuit breaker (3 failures → planner agent escalation)
- [ ] `/build` Phase 3 references `/deslop` after `/simplify`
- [ ] `/debug` Phase 1 prompt includes evidence strength hierarchy (6 levels)
- [ ] Evidence hierarchy reference doc exists at `.claude/skills/debug/evidence-hierarchy.md`
- [ ] `/brainstorm` includes pre-mortem step (Step 4.5) between proposals and presentation
- [ ] Both hooks have `DISABLE_WORKFLOW_HOOKS` kill switch at top
- [ ] `CLAUDE.md` agents table includes `critic` with model `opus`
- [ ] `CLAUDE.md` skills table includes `/deslop`
- [ ] `CLAUDE.md` model routing rules include critic under planning agents (opus)

## Out of Scope

- No MCP server or bridge infrastructure (stays markdown-only)
- No tmux/multi-AI orchestration
- No magic keyword detection (stays with slash commands)
- No HUD/status line changes
- No changes to `/plan`, `/tdd`, `/verify-evidence`, `/prd` skills
- No new hooks beyond kill switch edits
