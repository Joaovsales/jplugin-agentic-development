---
name: writing-skills
description: Author new skills with proper structure, iron laws, and reference docs. Use when creating or improving skills for the workflow.
argument-hint: "[skill name or purpose]"
harness: universal
---

# /writing-skills — Skill Authoring Guide

## Overview

Skills are the building blocks of the workflow. A well-written skill makes the agent consistently follow a process. A poorly-written skill gets ignored or misapplied.

## Skill File Structure

Every skill lives in `.agents/skills/<skill-name>/SKILL.md` — the one canonical tree. Pi and Codex read it from `~/.agents/skills/`; Claude Code loads the same tree through the `jplugin` plugin manifest (`.claude-plugin/plugin.json`), so a new skill needs no second copy. A skill that only makes sense on one harness declares it in frontmatter (`harness: claude`) instead of living in a harness-specific directory:

```
.agents/skills/
  my-skill/
    SKILL.md              # Main skill file (required)
    reference-doc.md      # Supporting reference (optional)
    template.md           # Templates for output (optional)
    helper-script.sh      # Automation scripts (optional)
```

### YAML Frontmatter (Required)

```yaml
---
name: skill-name                    # Kebab-case, matches directory name
description: One-line purpose.      # When to invoke this skill
argument-hint: "[what to pass]"     # Optional — shown in help
disable-model-invocation: false     # false unless the skill is a user-only front door — see the note below
---
```

> **`disable-model-invocation`.** `disable-model-invocation: false` is the default
> and what the Skill tool requires for any skill another skill invokes; set to
> `true` (or omitted in some environments) the Skill tool refuses it with
> "Error: Skill X cannot be used with Skill tool due to disable-model-invocation".
> `disable-model-invocation: true` is reserved for user-only front doors that
> must never fire on their own. `/grill-me` is the example: it is typed, never
> dispatched, and delegates to the model-invocable `/grilling`. Check the harness
> in use before shipping one: a typed slash command may route through the Skill tool,
> and then the flag blocks the user too. On Claude Code the routing is
> The typed route with the flag in place is verified on Claude Code (2.1.277, print
> mode); Pi and Codex are unverified, so a `harness: universal` front door carries
> that caveat until someone types it there.
> proven by typing the command in a session and reading the transcript's
> `<command-name>`; the walkthrough is recorded in `tasks/e2e-log.md`.

### Markdown Body

Follow this structure for consistency:

```markdown
# /skill-name — Short Title

## Overview
One paragraph: what it does, why it matters.

## The Iron Law (if applicable)
A non-negotiable rule in a code block. Use sparingly — only for critical behavioral constraints.

## The Process
Numbered steps with clear actions. Each step should be:
- Specific enough that the agent can't misinterpret it
- Small enough to complete in one action
- Verifiable — you can tell if it was done correctly

## Common Rationalizations (if applicable)
| Excuse | Reality | table for anticipated shortcuts

## Red Flags — STOP (if applicable)
Bulleted list of signals the process is being violated

## Integration
- Called by: [which skills invoke this one]
- Pairs with: [complementary skills]

## Key Principles
3-5 bullet points capturing the spirit of the skill
```

## When to Use Iron Laws

Add an iron law when:
- The agent has a known tendency to skip the step
- Skipping causes significant downstream problems
- The rule is truly non-negotiable (no valid exceptions)

**Examples of good iron laws:**
- "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" (TDD)
- "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST" (Debug)
- "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE" (Verify)

**Don't overuse them.** If everything is an iron law, nothing is.

## When to Add Rationalization Tables

Add when the agent commonly talks itself out of following the process. Each row pairs an excuse with its factual rebuttal.

Good rationalization tables:
- Address the specific excuses the agent actually generates
- Keep "Reality" responses short and direct
- Cover 7-12 rationalizations (enough to be comprehensive, not so many they're ignored)

## When to Add Reference Documents

Add companion files when:
- A technique needs detailed examples (code samples, scripts)
- Content would make the main SKILL.md too long (>150 lines)
- The reference is useful across multiple skills
- You have executable scripts (shell, Python) that automate part of the process

Keep reference docs focused on ONE technique each.

## Quality Checklist

Before finalizing a skill:

- [ ] Name matches directory name (kebab-case)
- [ ] Description clearly states WHEN to use the skill
- [ ] Process steps are specific and verifiable
- [ ] No vague instructions ("consider", "think about", "maybe")
- [ ] Iron laws used only for truly non-negotiable rules
- [ ] Integration section documents skill relationships
- [ ] No placeholder text ("TBD", "add later")
- [ ] Tested by reading through as if you had no context — could you follow it?

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Skill directory | kebab-case | `receive-review/` |
| Main file | Always `SKILL.md` | `SKILL.md` |
| Reference docs | kebab-case `.md` | `root-cause-tracing.md` |
| Scripts | kebab-case with extension | `find-polluter.sh` |
| Templates | `*-template.md` | `bug-report-template.md` |

## Prose Admission Rules

Every line of skill prose is read by a model on every invocation, so every line has
a running cost. A line earns its place only if at least one of these is true:

1. **It states a falsifiable constraint** — something you could point at an output
   and say "this violated it".
2. **It counters a known default tendency** — the model would do otherwise without
   the line. You should be able to name the tendency.
3. **It supplies domain knowledge that changes a decision** — a fact about this
   repo, tool, or protocol the model cannot infer.

A line that does none of these is removed, not reworded.

**Inadmissible, regardless of how true it sounds:**

| Category | Example | Why it fails |
|----------|---------|--------------|
| Vague effort language as a standalone instruction | "Be thorough." "Produce high-quality work." "Think carefully." | Unfalsifiable. Nothing distinguishes compliance from non-compliance, so it changes no behaviour while consuming budget on every run. Replace with the observable rule you actually want. |
| Motivational rationale on a directive that already stands | "Run the tests — quality matters and the team depends on it." | The directive was complete. The clause adds tokens and dilutes the instruction. |
| Repetition away from a drift point | The same rule restated in three sections "for emphasis" | Repetition is a placement tool, not an emphasis tool. Repeat a rule **only** where placement changes whether it fires. |

**When repetition is genuinely required**, protect the duplicate with a parity
assertion in `tests/` so it cannot rot into two divergent copies. An unguarded
required duplicate is a future contradiction.

A targeted effort cue is admissible only when it counters a *documented* tendency
you have actually observed — then it qualifies under rule 2, and you should say
which tendency in a comment.

## Right-Sizing Mechanical Guards

When a review or a bug reveals a greppable invariant the test suite missed:

1. **Prefer tightening an existing assertion** over adding a new test file. Widen a
   regex that already documents the rule.
2. **Pin the smallest falsifiable unit** — a token, enum value, path, or heading
   that would have failed on the regressing change. Not a whole skill body.
3. **Never snapshot prose or pin incidental wording.** A test that fails on a
   rewording teaches authors to avoid improving the file.
4. **If judging the failure needs a model, it is not a test.** Non-deterministic
   prose behaviour belongs in a manual run with recorded evidence, never in the
   suite.

Corollary: **never edit a test to make the suite green.** A string a test pins that
you want to remove is a finding to resolve deliberately — update the pin *and*
record why in the test — not an obstacle to route around. A suite that pins buggy
behaviour will pass while the skill is broken.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Vague process steps | Make each step a concrete action with clear output |
| Too many iron laws | Reserve for truly non-negotiable rules (max 1 per skill) |
| Missing integration section | Always document which skills call or pair with this one |
| Monolithic SKILL.md | Extract techniques into reference docs at >150 lines |
| No "When NOT to use" section | Add off-ramps so the skill scales to actual complexity |
| Prose that fails the admission rules | Delete it — see *Prose Admission Rules* above |
| Executed path that assumes cwd is the skill dir | Paths in `bash` fences run from the project root; name the canonical `.agents/skills/...` path (`tests/test-skill-references.sh` enforces this) |
