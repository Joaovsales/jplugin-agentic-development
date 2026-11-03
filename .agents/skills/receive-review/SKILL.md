---
name: receive-review
description: Process incoming code review feedback with technical rigor. Use when receiving review comments on PRs, from users, or from automated review tools.
disable-model-invocation: false
harness: universal
---

# /receive-review — Processing Code Review Feedback

## Overview
Code review requires technical evaluation, not emotional performance.

**Core principle:** Verify before implementing. Ask before assuming. Technical correctness over social comfort.

## The Response Pattern

```
WHEN receiving code review feedback:

1. READ: Complete feedback without reacting
2. UNDERSTAND: Restate requirement in own words (or ask for clarification)
3. VERIFY: Check against codebase reality
4. EVALUATE: Technically sound for THIS codebase?
5. RESPOND: Technical acknowledgment or reasoned pushback
6. IMPLEMENT: One item at a time, test each
```

## Forbidden Responses

**NEVER use performative agreement:**
- "You're absolutely right!"
- "Great point!" / "Excellent feedback!"
- "Thanks for catching that!"
- "Let me implement that now" (before verification)
- ANY gratitude expression toward feedback

**INSTEAD:**
- Restate the technical requirement
- Ask clarifying questions
- Push back with technical reasoning if wrong
- Just start working — actions speak louder than words

**If you catch yourself about to write "Thanks":** DELETE IT. State the fix instead.

## Handling Unclear Feedback

```
IF any item is unclear:
  STOP — do not implement anything yet
  ASK for clarification on unclear items

WHY: Items may be related. Partial understanding = wrong implementation.
```

**Example:**
```
User: "Fix items 1-6"
You understand 1,2,3,6. Unclear on 4,5.

WRONG: Implement 1,2,3,6 now, ask about 4,5 later
RIGHT: "I understand items 1,2,3,6. Need clarification on 4 and 5 before proceeding."
```

## Source-Specific Handling

### From the User (Project Owner)
- Trusted — implement after understanding
- Still ask if scope is unclear
- No performative agreement
- Skip to action or technical acknowledgment

### From External Reviewers (PR comments, automated tools)
```
BEFORE implementing:
  1. Check: Technically correct for THIS codebase?
  2. Check: Would it break existing functionality?
  3. Check: Is there a reason the current implementation exists?
  4. Check: Works on all target platforms/versions?
  5. Check: Does the reviewer understand the full context?

IF suggestion seems wrong:
  Push back with technical reasoning

IF can't easily verify:
  Say so: "I can't verify this without [X]. Should I investigate or proceed?"

IF conflicts with user's prior architectural decisions:
  Stop and discuss with user first
```

## YAGNI Check

When a reviewer suggests "implementing properly" or adding "professional" features:
```
1. Grep codebase for actual usage
2. IF unused: "This isn't called anywhere. Remove it (YAGNI)?"
3. IF used: Then implement properly
```

Don't add features nobody uses just because a reviewer suggests it.

## Triage: Change / Verify / Consider

Classify every feedback item before touching anything. An item is not addressed
because a sentence landed somewhere; it is addressed when a demonstrated gap is
closed at the layer that owns it.

| Class | Evidence behind the item | Action |
|-------|--------------------------|--------|
| **Change** | A concrete failure, a reproduction, or a named contradiction in the code | Fix it |
| **Verify** | A plausible concern with no evidence yet — "this might race" | Go look. Do **not** edit. Report what you found; only a confirmed finding becomes a Change |
| **Consider** | A preference, an alternative design, a future idea | Record it and move on. Do **not** edit |

**Do not edit for `Verify` or `Consider` items.** Editing on an unverified concern
is how speculative complexity enters a codebase with a reviewer's name attached to
it. Absence of evidence is weaker than this project's own bar for a change.

### For each `Change`, find the owning layer

Fix the gap where it lives, not where it was noticed:

| Layer | Fix looks like |
|-------|----------------|
| Activation contract | Frontmatter, description, trigger wording |
| Outcome spine / boundary | What the skill is *for*; its done condition |
| Runtime protocol | The ordered steps an invocation follows |
| Loading / placement | *Where* an instruction sits, so it fires at the right moment |
| Deterministic enforcement | A test, guard, or hook — not prose |
| Shared rule | the `AGENTS.md` managed block, a reference under `.agents/references/`, or a convention used by several skills |

**Prose is the fix only when it is the smallest mechanism that closes the gap.** If
a guard can enforce it, write the guard instead — see `/writing-skills` §
*Right-Sizing Mechanical Guards*.

**Reviewer wording is a hypothesis about mechanism, not authority over it.**
Sometimes the reviewer's one-line fix is exactly right; sometimes the same evidence
points at a different layer. When the same cause shows up across several skills,
fix the shared rule once rather than patching each skill.

### Then reconcile

After the edit, reread the surrounding block and remove or rewrite whatever the
change made duplicated, contradictory, or obsolete. Stacking a new rule on top of
the one it supersedes is how skills accumulate contradictions.

For a multi-item round, record one line per item:

```
<item> -> Change|Verify|Consider | <owning layer> | <mechanism> — <why>
```

## Implementation Order

For multi-item feedback:
1. **Triage** every item as Change / Verify / Consider (above)
2. **Clarify** anything unclear FIRST
3. Then implement the `Change` items in this order:
   - Blocking issues (breaks, security)
   - Simple fixes (typos, imports)
   - Complex fixes (refactoring, logic)
4. Test each fix individually
5. Run full suite to verify no regressions
6. Reconcile the affected blocks

## When to Push Back

Push back when:
- Suggestion breaks existing functionality
- Reviewer lacks full context
- Violates YAGNI (unused feature)
- Technically incorrect for this stack
- Legacy/compatibility reasons exist
- Conflicts with user's architectural decisions

**How to push back:**
- Use technical reasoning, not defensiveness
- Ask specific questions
- Reference working tests/code as evidence
- Involve the user if architectural

## Acknowledging Correct Feedback

When feedback IS correct:
```
CORRECT: "Fixed. [Brief description of what changed]"
CORRECT: "Good catch — [specific issue]. Fixed in [location]."
CORRECT: [Just fix it and show the diff]

WRONG: "You're absolutely right!"
WRONG: "Great point!"
WRONG: ANY gratitude expression
```

## Gracefully Correcting Your Pushback

If you pushed back and were wrong:
```
CORRECT: "You were right — I checked [X] and it does [Y]. Implementing now."
WRONG: Long apology or defending why you pushed back
```

State the correction factually and move on.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Performative agreement | State requirement or just act |
| Blind implementation | Verify against codebase first |
| Batch without testing | One at a time, test each |
| Assuming reviewer is right | Check if it breaks things |
| Avoiding pushback | Technical correctness > comfort |
| Partial implementation | Clarify all items first |

## Integration
- Used during: PR review cycles, /build when reviews return feedback, /wrap-up-session code review phase
- Pairs with: /verify-evidence (verify before claiming fix is done)
