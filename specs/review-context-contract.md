---
implementation_paths:
  - CLAUDE.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .claude/skills/wrap-up-session/SKILL.md
  - .agents/skills/quality-gate/SKILL.md
  - .claude/skills/quality-gate/SKILL.md
  - .agents/skills/auto-improve/SKILL.md
  - .claude/skills/auto-improve/SKILL.md
  - .agents/skills/software-design-expert-review/SKILL.md
  - .claude/skills/software-design-expert-review/SKILL.md
  - .agents/agents/code-reviewer.md
  - .agents/agents/critic.md
  - .agents/agents/security-reviewer.md
  - .agents/agents/software-design-expert-review.md
  - .claude/agents/code-reviewer.md
  - .claude/agents/critic.md
  - .claude/agents/security-reviewer.md
  - .claude/agents/software-design-expert-review.md
  - tests/test-review-context.sh
---

# Spec: Review Context Contract

> Reviewer sub-agents receive scope and code. They do not receive intent. This
> spec gives them a dispatch contract as explicit as the one implementers already
> have, and closes the two Finding-Model gaps that the missing intent was hiding.

## Behavior

### The defect

A reviewer dispatched by `/wrap-up-session`, `/quality-gate`, or
`/software-design-expert-review` receives context through four channels:

| Channel | Carries | Specified where |
|---------|---------|-----------------|
| Persona file (`.claude/agents/<name>.md`) | role, red flags, finding axes, read-only constraint | the file itself |
| Dispatch prompt | whatever the orchestrator improvises | **only** `software-design-expert-review/SKILL.md:45` |
| Ambient project files | `CLAUDE.md`, `.claude/project.md` | harness auto-load |
| The repo | anything the agent chooses to read | **only** `security-reviewer.md:18` |

`/build` already holds implementers to a contract — *"Delegation prompt must
include: the exact task description, the relevant spec section, paths to related
source files"* (`build/SKILL.md:132`), plus role-filtered slices of
`tasks/project-context.md`. Reviewers have no equivalent. The builder therefore
knows what the code was *for*; the reviewer sees only what it *is*.

Two consequences. Both are reasoned from the mechanism, not measured here — this
repo has never carried a real `TODO(shortcut):` marker or emitted an `[AMBIGUITY]`
line, so items 4 and 5 have had no opportunity to fire and are a bet on downstream
projects. Item 2 is different: it is a gap in the shipped instructions, checkable
by reading them.

1. **Deliberate decisions get re-litigated.** The repo produces two explicit
   deferral records — `[AMBIGUITY]` lines (`.claude/project.md` § *Ambiguity
   Protocol*) and `TODO(shortcut):` markers (§ *Code Economy*, ledgered at
   `wrap-up-session` Step 3.7). Neither reaches a reviewer, so a shortcut whose
   limit and upgrade path are already written down comes back as a finding.
2. **Acceptance criteria go unchecked.** Only Pass 4 is told to read the specs and
   every AC (`wrap-up-session/SKILL.md:203`), and that instruction sits in the
   skill, not in the dispatch payload — so a dispatched Pass 4 receives it only if
   the orchestrator remembers to copy it. Passes 1–3 never see a spec at all.

### The fix, in four parts

**1. One canonical contract, four pointers.**
`CLAUDE.md` gains § *Review Dispatch Contract* listing what every reviewer
dispatch must carry. Each dispatch site states its site-specific payload and
points at that section.

Canonical over per-site copies because this repo has already paid for the
alternative: PR #61 removed four concrete model IDs that had been duplicated
across three files precisely because *"the two tables are the copies nobody
updates."* A seven-item list copied into four skills is the same failure with more
surface.

The contract, in full:

| Item | Why the reviewer cannot supply it | Absent-vs-empty |
|------|-----------------------------------|-----------------|
| Diff for `<base>..HEAD` — by path when > 500 lines, per *Large-Artifact Handoff* | it can derive this, but not which base | — |
| **Every spec relevant to the session** — each spec's path **and** its own AC list verbatim | nothing in the diff names the spec, and one session can touch several | `no spec — <reason>` |
| The `tasks/todo.md` entries completed this run | tells apart "not implemented" from "next task" | — |
| `[AMBIGUITY]` lines emitted this run | a documented decision reads as a defect | `deferrals: none` |
| `TODO(shortcut):` markers touching changed files | same | `deferrals: none` |
| Boundary: issues **introduced** by this session; pre-existing patterns out of scope | today this is stated to the orchestrator only | — |
| Output format: the four axes, with `evidence` at 75+ | a persona can drift from the gate that consumes it | — |

Every list must distinguish **empty** from **absent**. A reviewer given no
deferral list cannot tell "nothing was deferred" from "nobody told me", and the
conservative reading of the ambiguous case is to re-flag everything — which is the
noise this spec exists to remove. Same hazard class as the vacuous
`assert_not_contains` closed in #61.

**2. Intent is shared; conclusions are not.**

The two authorities disagree, and the disagreement is load-bearing here. Cognition
argues for *"share context, and share full agent traces, not just individual
messages"*, because *"actions carry implicit decisions"* and agents that cannot see
each other's assumptions produce conflicting ones. Anthropic's context-engineering
guidance argues the opposite for sub-agents: keep the detailed context isolated and
return a distilled summary.

For reviewers, this repo has already picked a side and written it down:
`CLAUDE.md` § *Independence Accounting* — *"Two lenses reasoned inside one context
are two perspectives, not two witnesses: they share the same priors and the same
blind spots."* Handing a reviewer the builder's reasoning imports exactly those
priors, and the promotion rule then counts a downstream echo as corroboration.

So the contract carries a **split**, stated in `CLAUDE.md`:

- **Share intent** — spec, ACs, task text, constraints, documented deferrals.
  These are facts about what was asked for.
- **Withhold conclusions** — the builder's account of why the code is correct, and
  any other reviewer's findings. These are judgements about whether the ask was met,
  and that judgement is the reviewer's own product.

**3. Anchor 75 gets a verification path.**

The `75` anchor already says the finding's *"correctness turns on a caller, config,
or runtime value outside the reviewed scope."* Nothing then tells the reviewer to
go read it — so a finding parks at 75 and, under the Apply Gate, is reported but
never applied even when a single `grep` would settle it.

Two rules, both in `CLAUDE.md` § *Finding Model*:

- A finding at `75` must **name** the specific caller, config key, or runtime value
  its correctness depends on. "Depends on the caller" without naming one is a `50`.
- The reviewer should read that dependency and resolve the finding: promote to `100`
  with the second `evidence` line, or drop it. A finding held at `75` must say what
  stopped the check (outside the repo, requires runtime, budget exhausted).

**Verification-promotion is not agreement-promotion, and Independence Accounting
does not constrain it.** Agreement promotes on *witnesses*, so it needs independent
contexts; verification promotes on *evidence*, so one context reading one more line
is sufficient. Conflating them would either ban a legitimate promotion or license
an illegitimate one.

This is also the mechanism the industry converged on: diff-only reviewers are the
dominant false-positive source, and following the call chain before emitting is
what separates a confirmed defect from a pattern match.

**4. Every reviewer persona declares its intake.**

Each of the four review personas gains a `## Context Intake` section with three
lines: what you will be given, what to fetch yourself, what is out of scope. Today
only `security-reviewer` says any of it (`security-reviewer.md:18`), and it says
only the first.

This is the Anthropic multi-agent requirement applied per-persona — a sub-agent
needs *"an objective, an output format, guidance on the tools and sources to use,
and clear task boundaries."* Objective and output format are already in every
persona. Sources and boundaries are in none.

### Adjacent defect, found while writing this spec

`auto-improve/SKILL.md:69` routes the design reviewer with a `| sonnet |` column
cell. That is a Ceiling role pinned to an alias — the exact regression #61's
section 8 exists to prevent. It survived because that guard matches
`model: <alias>` and this is a bare table cell, so the guard has a hole one
formatting choice wide.

Two lines to fix (the cell, and a widened assertion). Included because the guard
shipped hours ago and leaving a known hole in it is worse than the scope cost;
tagged separately so it can be dropped without touching the four items above.

## Inputs

Read from disk on `origin/master` @ `23f0d7d` (PR #61 merged; #62 and the Codex
adapter landed after), not assumed:

- `CLAUDE.md` — § *Finding Model* (L73), confidence anchors (L93), § *Independence
  Accounting* (L116), § *Review Gate Taxonomy* (L55).
- `.agents/skills/build/SKILL.md:132` — the implementer delegation contract this
  mirrors.
- `.agents/skills/wrap-up-session/SKILL.md` — Step 4 (L122), *Dispatch Disclosure*
  (L129), *Parallel Code Review* (L431). No payload specified at any of them.
- `.agents/skills/quality-gate/SKILL.md:201` — Phase 3 dispatch. No payload.
- `.agents/skills/software-design-expert-review/SKILL.md:45` — the only site that
  specifies a payload (diff, paths, format instruction).
- `.claude/agents/{code-reviewer,critic,security-reviewer,software-design-expert-review}.md`
  plus the `.agents/agents/` canonicals — 8 files, no intake section in any.
- `.agents/skills/auto-improve/SKILL.md:69` — the adjacent pin.
- `tests/test-agents.sh` §3 — pins all four axes in **both** trees per persona.
- `tests/test-model-tiers.sh` §8 — the `model: <alias>` guard with the hole.
- `tests/test-skill-parity.sh` — byte-identical `.agents/skills` → `.claude/skills`.

The Codex adapter renders from `.agents/` at install time (`scripts/render-codex.py`),
so there is no third tree to mirror into.

## Outputs

| Path | Change |
|------|--------|
| `CLAUDE.md` | § *Review Dispatch Contract* (the 7-item table, the intent/conclusions split); § *Finding Model* gains the anchor-75 naming rule, the verification path, and the verification-vs-agreement distinction |
| `.agents/skills/wrap-up-session/SKILL.md` + `.claude/` copy | Step 4 and *Parallel Code Review* carry the payload and point at the contract |
| `.agents/skills/quality-gate/SKILL.md` + `.claude/` copy | Phase 3 dispatch carries the payload and points at the contract |
| `.agents/skills/software-design-expert-review/SKILL.md` + `.claude/` copy | Phase 2's existing `Pass:` list extended to the full contract |
| `.agents/skills/auto-improve/SKILL.md` + `.claude/` copy | design-review charter unpinned to *ceiling* |
| `.agents/agents/*.md` + `.claude/agents/*.md` (4 personas × 2 trees) | `## Context Intake` section |
| `tests/test-review-context.sh` | new — pins the contract at every site, the intake sections, and the anchor-75 rules |
| `tests/test-model-tiers.sh` | §8 widened to catch a Ceiling role pinned in a table cell |

## Edge Cases

- **No spec this run** (a bug fix with no `specs/` file). The payload says
  `no spec — <reason>` rather than omitting the line, so the reviewer knows the
  absence is deliberate.
- **No deferrals.** `deferrals: none`, never a missing line. See the absent-vs-empty
  column above.
- **Diff too large to inline.** *Large-Artifact Handoff* already answers this:
  persist to a file, pass the path plus the last N lines, and say it was truncated.
  The contract cites the convention rather than restating a line count.
- **Inline (undispatched) review.** The contract is about what crosses a dispatch
  boundary. An inline run already has all of it in context; *Dispatch Disclosure*
  continues to govern what its agreement is worth.
- **A reviewer that cannot verify an anchor-75 dependency** (needs runtime, or the
  caller is outside the repo). It holds at `75` and states what stopped it. The
  finding is never dropped for being unverifiable.
- **Persona frontmatter.** #62 fixed YAML that silently deregistered three personas;
  edits here are body-only, and `tests/test-agents.sh` §4 still parses every block.
- **Contract text drifting from the sites that cite it.** The new test greps each
  site for the pointer, so deleting the section fails the suite rather than leaving
  four dangling references.

## Acceptance Criteria

- [x] `CLAUDE.md` has a § *Review Dispatch Contract* enumerating all seven items
- [x] It states the intent-shared / conclusions-withheld split, and why sharing
      conclusions would corrupt Independence Accounting
- [x] All four reviewer dispatch sites cite the contract by section name
- [x] Each site states the absent-vs-empty rule for spec and deferrals
- [x] `CLAUDE.md` § *Finding Model* requires a finding at `75` to name its
      dependency, and an unnamed dependency reads as `50`
- [x] It states the verification path (read the dependency → promote to `100` with
      evidence, or drop, or hold and say what stopped it)
- [x] It states that verification-promotion is not agreement-promotion and is not
      constrained by Independence Accounting
- [x] All four review personas carry a `## Context Intake` section in **both** trees
      (8 files), and `tests/test-agents.sh` stays green
- [x] `auto-improve` no longer pins the design reviewer to an alias
- [x] `tests/test-model-tiers.sh` §8 fails when a Ceiling role is pinned in a table
      cell, not only via `model:`
- [x] `tests/test-review-context.sh` fails when any one of: the contract section is
      deleted, a dispatch site's pointer is removed, a persona's intake section is
      removed, or the anchor-75 rule is deleted — each probed and recorded

- [x] `tests/test-skill-parity.sh` green over every edited skill
- [x] No persona caps a severity with an `autofix_class` value, and every persona
      carries a never-out-of-scope clause covering the never-on-the-chopping-block list
- [x] The anchor-75 text agrees with the Apply Gate about what `75` does
- [x] Both trees of `wrap-up-session` cite the contract at **both** of their dispatch
      sites, verified by count rather than presence
- [x] The alias guard catches a bold, capitalised, or suffixed alias and an
      unlisted review charter — validated against 8 evasion fixtures
- [x] `**Given to you**`, the contract pointer, and the boundary heading are each
      pinned per persona per tree, with the boundary needle anchored so
      `**Never out of scope**` cannot satisfy it
- [x] `bash tests/run.sh`: **1250 assertions, 16 of 17 files green**. The one red
      file, `tests/test-codex-install.sh`, fails identically on pristine
      `origin/master` @ `23f0d7d` and is recorded at
      `tasks/solutions/bugs/codex-session-start-hook-emits-nothing.md`. Per-file:
      `test-review-context` 88 (new), `test-model-tiers` 95 (was 149 before §8b
      stopped looping per file), `test-agents` 162, `test-skill-parity` 42.

## Non-Goals

- No change to the four axes, the anchor definitions, or the Apply Gate thresholds.
  Anchor `75` keeps its meaning; only what a reviewer must do about it is new.
- No change to Independence Accounting. This spec bounds it, it does not weaken it.
- No mechanical enforcement of what a dispatch prompt actually contained at runtime.
  The guard is static, like the tier floors: it pins the instruction, not the call.
- No change to `/build`'s implementer contract — it is the model being copied.
- No new reviewer, lens, or gate. Four dispatch sites in, four out.

## Sources

- Anthropic, *How we built our multi-agent research system* — a sub-agent needs an
  objective, an output format, guidance on tools and sources, and clear task
  boundaries; vague descriptions produce duplicated work and coverage gaps.
- Anthropic, *Effective context engineering for AI agents* — just-in-time context
  via lightweight identifiers; hybrid preload; distilled returns.
- Cognition, *Don't build multi-agents* — share full traces; actions carry implicit
  decisions. Adopted for intent, deliberately not for conclusions.
- Industry comparisons of diff-only versus repository-aware reviewers — diff-only
  review is the dominant false-positive source; call-chain verification is the fix.

## Mutation probes

Run after committing, so the restore step (`git checkout -- .`) could not eat the
work under test — the failure mode this project already recorded once.

Counts are **assertions failed**, and a mutation applied to both trees fails twice
because every loop here iterates `.agents` and `.claude`. The first table was wrong
about three of five rows for exactly that reason; review caught it, and the rows
below were re-measured against the hardened guards rather than adjusted on paper.

| Mutation | Guard | Assertions failed |
|----------|-------|-------------------|
| Delete § *Review Dispatch Contract* wholesale | `test-review-context` §1–3 | 11 |
| Drop the contract citation from the parallel-dispatch site (both trees) | §6 count | 2 |
| Rename `critic`'s `## Context Intake` heading (both trees) | §7 | 2 |
| Delete the `**Given to you**` paragraph from one persona (both trees) | §7 | 6 |
| Delete `security-reviewer`'s boundary paragraph (both trees) | §7 | 2 |
| Delete the anchor-75 naming rule | §4 | 2 |
| Re-pin `auto-improve`'s design reviewer as `**Sonnet**` | `test-model-tiers` §8b | 1 |

The last four rows are the ones that matter: each was **green** before review, and
each is a guard that existed and did not bite. The bold-and-capitalised alias, the
substring collision between `Out of scope` and `Never out of scope`, the entirely
unpinned `Given to you`, and a per-file citation needle standing in for a per-site
AC — four different ways to report success while measuring nothing.

## Implementation Paths

- `CLAUDE.md` — the canonical Review Dispatch Contract, its seven items, and the
  empty-versus-absent rule.
- `.agents/skills/wrap-up-session/SKILL.md` — the Review Payload assembled for
  the four review passes, and the Dispatch Disclosure that decides what their
  agreement is worth.
- `.agents/skills/quality-gate/SKILL.md` — the Phase 3 design-review dispatch.
- `.agents/skills/auto-improve/SKILL.md` — the repo-survey dispatch, the one
  documented exception to items 2, 3 and 6.
- `tests/test-review-context.sh` — pins each payload item individually, so a
  table emptied of its rows fails rather than passing on the heading alone.
- `.claude/skills/**` — byte-identical compatibility mirrors.
