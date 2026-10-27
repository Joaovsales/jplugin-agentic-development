# Spec: Close the gaps the Ceiling tier left open

> Follows PR #53, which shipped the Ceiling tier. This spec covers three things
> #53 named but did not finish, a test-harness hole found while verifying them,
> and a pre-existing escalation-ladder no-op the same analysis exposed. It is
> deliberately narrow: the Ceiling tier itself, its rationale, and its
> `CLAUDE.md` vocabulary are #53's and are not restated here.

## Behavior

`Ceiling` means "omit the `model` override so the sub-agent inherits the session
model". #53 established the tier and applied it to three review roles. Five
things remained.

### 1. `software-design-expert-review` joins Ceiling

The decision this reverses was **#55's, not #53's** (`git log -S"Reviewer tier, not
Ceiling"` → `a798ce0`). #55 shipped two PRs after Ceiling already existed and wrote
*"`model: sonnet` — Reviewer tier, not Ceiling"* deliberately, with the tier
available; `tests/test-model-tiers.sh` then asserted the pin via `PINNED_AGENTS`.
So this is a reversal of an informed choice, not the completion of an unfinished
one — which is a higher bar.

**This spec overrides that decision.** An APOSD structural audit is correctness
work: the defects it finds are the expensive kind, and a design flaw caught late
costs far more than the token difference.

**The cost is not a flat token difference, and that is the honest counterargument.**
Unlike the other three Ceiling roles — each dispatched once per run — this agent is
dispatched *per changed file* at ≥5 files, and its own skill discourages batching
("Batching files therefore trades corroboration for tool calls"). So Ceiling
multiplies top-tier spend by the file count, not by one. A 20-file PR on an Opus
session means ~20 Opus dispatches for design review alone against 4 for everything
else combined. Whether that is worth it is a spend judgment, not a correctness one,
and it is the delta most worth dropping if the answer is no.

`PINNED_AGENTS` keeps a subject — `context-document-optimizer` — so the mirror
guard #53 added does not go vacuous. That guard protects a
real observed regression: the `.agents/` → `.claude/` parity copy is a plain `cp`
from a tree that is model-agnostic by contract, so it silently drops a
Claude-only `model:` line, and parity tests cannot catch it because the `cp` is
what made the two files identical.

### 2. `critic` gains a planner floor

Plain `ceiling` inherits in every direction **including down**. On a Builder- or
Scout-tier session the adversarial gate of last resort ran below planner tier —
a silent downgrade of the one reviewer whose whole job is catching what the others
missed.

Resolution becomes `*ceiling (planner floor)*`: omit the override at planner tier
or above, pass the planner alias below it.

The floor is a **dispatch rule, not frontmatter.** A `model: opus` pin would
satisfy the floor on a Sonnet session but *cap* the agent on any session stronger
than Opus — the same defect Ceiling exists to remove. Nothing mechanically
enforces the floor; the test pins the rule's presence and the absence of a pin,
which is as far as a static guard reaches. This limit is stated rather than
hidden.

### 3. Concrete model IDs leave the routing tables

Four OpenRouter IDs lived in `CLAUDE.md`, `/build`'s table (both trees), and
`PI_SETUP.md`. Three copies of a release-sensitive fact is three chances to go
stale, and the two tables are the copies nobody updates.

`PI_SETUP.md` § Sub-Agent Routing becomes the named single source. Both tables
carry tiers only.

It also corrects a #53 rule that was simply wrong: `CLAUDE.md` said *"leave
ceiling-tier agents out of `agentOverrides` so they inherit"*. On Pi, omitting an
agent falls through to `subagents.defaultModel` — a fixed builder-tier model — so
omission there **downgrades** rather than inherits. Ceiling-by-omission is a
Claude Code property. Pi expresses the same intent with the literal
`"model": "inherit"` in `agentOverrides` — the Pi spelling of "pass nothing",
resolved by `pi-subagents` 0.82.1 and later to the parent session model — and
`critic` keeps a concrete planner-tier pin because a directive cannot make a floor
conditional.

This was found only because a review challenged it; the first version of this
branch deleted those four Pi entries and would have had every Pi user's code
reviewed by the model family that wrote it.

### 4. `assert_not_contains` no longer passes vacuously

Absence-of-needle is trivially true of the empty string, so any `grep`/`sed`
extraction that matched nothing reported `ok` — turning a load-bearing check into
a silent pass. `assert_contains` needs no such guard (an empty haystack cannot
contain a non-empty needle), which is why the hole was one-sided and easy to miss.

The guard goes in the primitive rather than in each caller, because "remember to
check your extraction first" is the discipline whose absence causes the bug.

Two helpers follow from the same work: `assert_file_matches` /
`assert_file_not_matches` for anchored patterns like `^model:` that
`assert_file_contains` cannot express (`grep -qF` is literal-only), and
`assert_prose_contains`, which collapses whitespace so a prose assertion depends
on the words rather than on where the markdown hard-wrap happens to fall.

## Inputs

Read from disk on current `master` (`7c3dc74`), not assumed:

- `CLAUDE.md` — Agents table (10 rows), Model Routing (5 tiers incl. `Ceiling`),
  and the dispatch Rules block.
- `.claude/agents/` — `code-reviewer`, `security-reviewer`, `critic` already
  unpinned by #53; `software-design-expert-review` still `model: sonnet`.
- `tests/test-model-tiers.sh` — 105 lines, `CEILING_AGENTS` (3) and
  `PINNED_AGENTS` (1).
- `.agents/skills/build/SKILL.md` — 8-row table with 8 concrete IDs; ladder and
  circuit breaker naming IDs.
- `.agents/skills/{quality-gate,software-design-expert-review}/SKILL.md` — the two
  design-reviewer dispatch sites.
- `PI_SETUP.md` — concrete IDs plus an `agentOverrides` example pinning all four
  review roles; zero mentions of `ceiling`.
- `tests/lib.sh` — 5 assertion helpers, none regex, none whitespace-normalizing.

## Outputs

| Path | Change |
|------|--------|
| `CLAUDE.md` | design reviewer → `*ceiling*`; `critic` → `*ceiling (planner floor)*`; a generalized `### Floors` section covering both floor-carrying roles; Pi column dropped, pointer added; Ceiling row covers design |
| `.claude/agents/software-design-expert-review.md` | delete the `model:` line |
| `.agents/skills/build/SKILL.md` + `.claude/` copy | Tier column replaces Model ID column; ladder and circuit breaker name tiers; debugger attempts 3–4 → `ceiling (builder floor)`, plus the no-collapsed-rung invariant |
| `.agents/skills/{quality-gate,software-design-expert-review}/SKILL.md` + copies | dispatch at Ceiling, no `model` |
| `PI_SETUP.md` | named single source; Ceiling rows; the three plain-Ceiling Pi entries carry `"model": "inherit"`, `critic` keeps a concrete pin, with why omission downgrades on Pi |
| `tests/lib.sh` | empty-haystack guard; `assert_file_matches`, `assert_file_not_matches`, `assert_prose_contains` |
| `tests/test-model-tiers.sh` | `CEILING_AGENTS` gains the design reviewer; `PINNED_AGENTS` → `context-document-optimizer`; sections 6–13 added; §1–3 collapsed onto the new helpers; §11 pins the Pi `inherit` directive, the `critic` counter-pin, and an absence sweep for the directive under `.agents/` |

### 5. Debugger attempts 3–4 gain a builder floor

Deferred once as out of scope, then pulled in on review. `/build`'s regression
ladder is 2 attempts at builder tier → 2 at reviewer tier → circuit breaker. On
Claude Code **Reviewer and Builder both resolve to `sonnet`**, because there is
no alias between them, so the middle rung re-ran the exact model that had just
failed twice: three documented rungs, two real ones, and the first genuine
escalation arriving four attempts later than the ladder claims.

Resolution becomes `ceiling (builder floor)` — the same notation `critic`
already uses, rather than a second mechanism. A flat `opus` would fix Claude
Code and reintroduce the cap this whole spec removes on any stronger session.

`/build` also gains the invariant behind it: steps 1 and 2 must never resolve to
the same model. The row alone reads as an arbitrary choice and gets simplified
back; the rule explains why it cannot be.

### Unchanged, deliberately

- `code-reviewer`, `security-reviewer` get no floor. Only `critic` needs one.

## Edge Cases

- **A Haiku session.** `code-reviewer`, `security-reviewer`, and the design
  reviewer run on Haiku. Accepted: Ceiling means the session's choice governs, and
  a user on Haiku chose cheap. `critic` is the exception, by floor.
- **Someone re-pins a Ceiling role.** `tests/test-model-tiers.sh` fails, in both
  the agent file and the routing tables. Verified by probing each.
- **The floor is unenforceable.** Stated in `CLAUDE.md` and in this spec.
- **Pi cannot express a floor declaratively.** So `critic` is pinned to the planner
  model unconditionally on Pi — the floor is satisfied at all times rather than
  conditionally. Documented in `PI_SETUP.md`. Ceiling itself is expressible there
  (`"model": "inherit"`), so the asymmetry is the *floor* alone: a directive
  resolves the session model, never a minimum.
- **Markdown reflow.** Prose assertions use `assert_prose_contains`, so rewrapping
  a paragraph does not break the suite.

## Acceptance Criteria

- [x] All four review roles resolve to a Ceiling variant in `CLAUDE.md` and `/build`
- [x] `.claude/agents/` pins no model for any of the four
- [x] The six non-Ceiling personas keep their pins (guards a blanket strip)
- [x] `critic`'s floor is stated as a dispatch rule, and the test fails if the rule is deleted
- [x] No concrete provider model ID remains in `CLAUDE.md` or either `/build` copy
- [x] `PI_SETUP.md` claims single-source ownership and explains Ceiling
- [x] `PI_SETUP.md`'s `agentOverrides` no longer contradicts `CLAUDE.md`
- [x] No skill routes the design reviewer to a concrete model
- [x] `assert_not_contains` fails on an empty haystack, with no sibling test broken
- [x] `tests/test-skill-parity.sh` green over every edited skill
- [x] critic's floor is stated at every site that dispatches critic, not only in `CLAUDE.md`
- [x] Pi's three plain-Ceiling roles carry `"model": "inherit"` and `critic` keeps a concrete planner-tier pin; the test fails if a directive is replaced, an entry is deleted, or the directive leaks into a harness-neutral tree
- [x] `CLAUDE.md`/`.claude/agents/` and the Codex policy express Ceiling their own way and are unchanged by the Pi directive: no `model:` pin in the Claude Code tree, `inherit_model = true` in `config/agent-policy.toml`
- [x] Debugger attempts 3–4 resolve to `ceiling (builder floor)` in `CLAUDE.md` and both `/build` copies, and the test fails if the rung collapses back onto builder tier
- [x] `tests/test-model-tiers.sh` §1–3 use the shared helpers rather than hand-rolled `grep` plus raw counter arithmetic
- [x] Seven mutations that previously stayed green now fail (2–10 assertions each)
- [x] `bash tests/run.sh` green

## Non-Goals

- No change to the Ceiling tier's definition or rationale — #53 owns those.
- No floors beyond `critic` and the debugger's escalation rung.
- No change to the ladder's *shape* — still 2 + 2 + circuit breaker. Only what
  the second pair resolves to changes.
