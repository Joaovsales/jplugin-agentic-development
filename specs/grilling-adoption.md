---
implementation_paths:
  - .agents/skills/grilling/**
  - .agents/skills/grill-me/**
  - .agents/skills/brainstorm/**
  - .agents/skills/writing-skills/SKILL.md
  - .github/upstreams.json
  - THIRD_PARTY_NOTICES.md
  - CLAUDE.md
  - README.md
  - .claude/hooks/session-start.sh
  - tests/test-grilling-adoption.sh
  - tests/test-skill-invocation-chain.sh
---

# Spec: Grilling Adoption

Adopts Matt Pocock's `grilling` interview primitive and `domain-modeling`
discipline from [mattpocock/skills](https://github.com/mattpocock/skills) into
this workflow. `/brainstorm` runs the interview and writes vocabulary and
architecture decisions inline; a new `/grill-me` front door runs the same
interview with no repository and no files. Comparison that motivated the change:
<https://claude.ai/artifact/PzYdNXTghPx5tLSbTbGrsL>.

## Decisions (interview, 2026-09-21)

| Question | Decision | Consequence |
|----------|----------|-------------|
| Default cadence in `/brainstorm` Step 3 | Frontier rounds | The "one question at a time" principle is retired; the one-line opt-out is documented instead |
| Provenance of the adapted text | Vendor and register | `LICENSE.mattpocock` in each new skill dir, a `THIRD_PARTY_NOTICES.md` section, an `.github/upstreams.json` source pinned at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` |
| `disable-model-invocation` on `/grill-me` | `true`, matching upstream | The writing-skills guide gains a documented exception; AC 11 verifies the harness still fires a typed `/grill-me` |
| `/plan` Step 1 through `/grilling` | Not in this change | #106 rewrites `/plan` Steps 1 to 3 in flight; a follow-up task is filed after confirmation |
| Skill tree layout (re-baseline, 2026-09-21, after #156 merged) | One canonical tree | `.claude/skills/` is a retired root and `tests/test-skill-parity.sh` is gone, so no copy is written and the parity criterion becomes the frontmatter, references and plugin-manifest tests. Claude Code loads `.agents/skills/` through the `jplugin` plugin, so a user types `/jplugin:grill-me`; skill bodies stay namespace-free. `/verify` is `/verify-evidence` |
| Round format restated in `/brainstorm` Step 3 (wrap-up review, 2026-09-21) | Kept, as a marked `TODO(shortcut)` in the brainstorm frontmatter | A session that fails to load `/grilling` still asks in rounds, at the cost that the primitive is optional and the load has no reply-level tell; `/eval` Mode A measured 5/6 on 2026-09-21. OPEN for the maintainer: whether AC 13 gets a floor (the wrap-up critic proposed at least 5/6) and whether Step 3 shrinks to a pointer once the chain holds without the restatement |

## Behavior

**`/grilling` (model-invoked primitive).** Interviews the user until a shared
understanding is reached. The subject is a design tree: every decision branches
into the decisions that hang off it. Work proceeds in rounds. A round is the
whole frontier, meaning every question whose prerequisites are already settled,
numbered, each carrying the agent's recommended answer on its own line:

```
❓ **Q1** - **<title>**: <body, may include multiple choices>

➡️ <recommended answer>

---

❓ **Q2** - ...
```

Facts are the agent's job: a frontier question that needs something the
environment can settle dispatches a Scout-tier sub-agent (Model Routing table in
`CLAUDE.md`; Pi uses `scout`) and only the questions downstream of that lookup
wait. Decisions are the user's: each is put to them and the agent waits. The
session ends when the frontier is empty. The agent does not act on the outcome
until the user confirms the understanding is shared. A user who prefers the
sequential rhythm adds `When grilling, ask one question at a time.` to
`CLAUDE.local.md` (Claude Code) or `~/.pi/agent/AGENTS.md` (Pi).

**`/grill-me` (user-invoked front door).** Runs `/grilling` on the argument and
nothing else. It writes no files: no spec, no glossary entry, no store document,
no `tasks/todo.md` row. It needs no repository, and the subject does not have to
be software. When the subject is a feature in a repository, it points the user
at `/brainstorm`. It carries `disable-model-invocation: true`, so the agent never
fires it on its own.

**`/brainstorm` Step 3 (rewritten).** Invokes `/grilling` with the problem
statement as the root of the tree and the four stock questions (problem and
beneficiary, constraints, definition of done, prior art) as the seed frontier.
Multiple-choice bodies remain preferred. While the interview runs, the domain
layer in `references/domain-modeling.md` is active:

- **Challenge against the glossary.** A term that conflicts with an entry in
  `tasks/concepts.md` is called out before the round continues.
- **Sharpen fuzzy language.** A vague or overloaded term gets a proposed
  canonical term as a frontier question.
- **Concrete scenarios.** Relationships between concepts are stress-tested with
  invented edge-case scenarios.
- **Cross-reference with code.** A claim about how the code behaves is checked
  against the tree and the contradiction surfaced with `file:line`.
- **Write the glossary inline.** A resolved project-specific term lands in
  `tasks/concepts.md` the moment it resolves, in the `/learn` § Capture New
  Concepts format (`- **term** — definition.`, alphabetical, refined in place,
  standard industry terms excluded, seed recreated if the file is absent). The
  glossary holds definitions only. Implementation detail, decisions, and
  spec-like prose never enter it.
- **Offer an architecture decision sparingly.** When a decision is hard to
  reverse, surprising without context, and the result of a real trade-off, all
  three at once, the agent offers to record it as a frontier question. On yes it
  writes `tasks/solutions/architecture/<slug>.md` on the knowledge track
  (`problem_type: architecture-decision`, `applies_when`, plus the shared
  required fields), with a body of at least one to three sentences stating
  context, decision and reason. Overlap is scored against existing documents
  per `/learn` § Score Overlap Before Writing before any file is created. When
  a gate fails, the agent says which one and writes nothing.

Steps 4 (options table), 4.5 (pre-mortem), 5, 7, 8 and 9 are unchanged; Step 6
(living-contract spec) gains only the vocabulary constraint. The hard gate, the
lightpanda research paragraph, and the absence of any `/tdd` reference are
preserved.

### `/brainstorm` stages after this change

| Step | Before | After | Change |
|------|--------|-------|--------|
| Hard gate | No `/plan`, `/build`, or code until the design is approved | Same | none |
| 1. Explore context | Read codebase, `specs/`, `tasks/todo.md`, `tasks/solutions/` frontmatter; lightpanda fallback | Same, plus read `tasks/concepts.md` so Step 3 can challenge terms against it | extended |
| 2. Offer visual aids | ASCII, Mermaid, component trees | Same | none |
| 3. Interview | Inline list of four stock questions, asked one at a time, multiple choice preferred | Invoke `/grilling`: the problem statement is the tree's root, the four stock questions are the seed frontier, rounds arrive in the `❓` / `➡️` format with a recommendation on every question, facts are looked up by a Scout-tier sub-agent, decisions are put to the user. The domain layer from `references/domain-modeling.md` runs inside the interview: challenge conflicting terms, sharpen vague ones, stress-test relationships with scenarios, cross-reference claims with code, write resolved terms to `tasks/concepts.md` immediately, offer a three-gate architecture decision as a frontier question. Step 3 ends when the frontier is empty and the user confirms shared understanding | **rewritten** |
| 4. Propose 2 to 3 approaches | Option A / B / C with approach, pros, cons, complexity, files affected, recommendation | Same. The settled decisions from Step 3 constrain the options rather than being re-asked | none |
| 4.5. Pre-mortem | 3 to 5 failure scenarios per approach; flag likely-and-high-impact | Same | none |
| 5. Present design sections | Architecture, data flow, error handling, testing, one at a time for complex features | Same | none |
| 6. Write the design spec | Living-contract spec at `specs/<feature>.md` | Same. Terms used in the spec are the canonical ones settled in Step 3 | extended |
| 7. Self-review the spec | Placeholders, contradictions, ambiguity, edge cases, testability | Same | none |
| 8. User approval | `y` to proceed | Same | none |
| 9. Hand off | Invoke `/plan` with the approved spec | Same | none |
| Key Principles | Includes "One question at a time" | That principle is replaced by "Rounds, not drips: ask the whole frontier, recommend on every question" and "Facts are the agent's job, decisions are the user's"; a "Glossary is a glossary" principle is added | **edited** |

Only Step 3 changes shape. Steps 1 and 6 gain a glossary read and a vocabulary
constraint respectively; everything else is untouched. The divergent half of
the skill (Steps 4 and 4.5) is the part upstream has no equivalent for and is
deliberately kept.

**`/writing-skills`.** The frontmatter note reads: `disable-model-invocation:
false` is the default and what the Skill tool requires for a skill another skill
invokes; `true` is reserved for user-only front doors that must never fire on
their own, with `/grill-me` as the example, and the harness in use must be
checked because a typed slash command may route through the Skill tool.

**Registration.** Both new skills appear in the `CLAUDE.md` skills table, the
`README.md` skills table, and the `SKILLS AVAILABLE` block of
`.claude/hooks/session-start.sh`. `README.md` § Sources credits
`mattpocock/skills`. `.github/upstreams.json` registers the source so the
scheduled drift checker reports upstream changes to the adapted files.

## Inputs

- `/grilling <subject>`: a plan, decision, or idea, or invocation from another
  skill with the surrounding task as the subject.
- `/grill-me <subject>`: the same, typed by the user only.
- `/brainstorm <feature idea>`: unchanged.
- Existing state read during a session: `tasks/concepts.md`,
  `tasks/solutions/` frontmatter, the codebase.

## Outputs

- `/grilling`, `/grill-me`: rounds of questions in the format above; no files.
- `/brainstorm`: Step 3 now emits `/grilling` rounds in the `❓` / `➡️` format
  instead of single questions, and glossary challenges inside those rounds.
  Files: the living-contract spec at `specs/<feature>.md` as before, plus zero
  or more `tasks/concepts.md` entries written mid-session and zero or more
  `tasks/solutions/architecture/<slug>.md` documents. See the stage table
  under Behavior for the full before and after.
- Repository: two new skill directories in the canonical tree, one new
  reference doc, one new test file, edits to the surfaces listed in the
  frontmatter.

## Edge Cases

- **The harness refuses a typed `/grill-me`** because of
  `disable-model-invocation: true`. The flag flips to `false`, the description
  is tightened to explicit "grill me" phrasing, the writing-skills note is
  adjusted, and an `[AMBIGUITY]` line records the flip. This is decided by
  AC 11's e2e walkthrough, never guessed.
- **A round contains two questions that turn out to depend on each other.** The
  frontier is the agent's judgement, not a computed graph. The user says so, the
  affected branch reopens, and the next round is recomputed. The skill states
  this limit.
- **A fact lookup is still running.** The rest of the frontier is asked; only
  questions downstream of the lookup wait.
- **`tasks/concepts.md` is absent.** The seed is recreated exactly as `/learn`
  § Capture New Concepts specifies; the rule is referenced, not duplicated.
- **A glossary write would carry implementation detail.** Refused. The glossary
  is a glossary and nothing else.
- **An architecture decision fails one of the three gates.** No document. The
  agent names the failed gate.
- **An architecture decision overlaps an existing document at 4 to 5
  dimensions.** The existing document is updated in place; no sibling is
  created.
- **Another skill invokes `/grilling` but the primitive does not load.** There is
  no tell in the reply: `/brainstorm` Step 3 carries the round format, so the
  output still looks right while the rules that live only in `/grilling` (the
  opt-out, the empty-frontier end, the confirmation gate) are silently absent.
  The detector is the transcript, a `Skill` load of `grilling`, graded by
  `.agents/skills/eval/scripts/grade-skill-loads.sh`. AC 13's triggerability
  eval measures it; a failing result is reported, and the chain assertion in
  `tests/test-skill-invocation-chain.sh` keeps the handoff written down.
- **Upstream moves past the pinned baseline.** The scheduled drift workflow
  reports it. That is the registration working, not a failure of this feature.
- **The e2e walkthrough for AC 12 runs in this template repository.** A real
  glossary term written during the walkthrough is reverted after the evidence
  is recorded, so the template's own glossary is not polluted by a sample.
- **Pi harness.** No per-call model parameter; `scout` fills the fact-finder
  role through `subagents.agentOverrides`.

## Acceptance Criteria

1. `.agents/skills/grilling/SKILL.md` exists with `name: grilling`,
   `disable-model-invocation: false`, `harness: universal`, and its body names the
   design tree, the frontier, rounds, the `❓` / `➡️` round format with a
   recommended answer on every question, the facts-versus-decisions split with
   Scout-tier fact finding, the empty-frontier end condition, the confirmation
   gate before acting, and the one-line opt-out sentence with both harnesses'
   override file locations.
2. `.agents/skills/grill-me/SKILL.md` exists with `name: grill-me`,
   `disable-model-invocation: true`, `harness: universal`, an `argument-hint`,
   and a body that invokes `/grilling`, states that it writes no files and needs
   no repository, and routes repository feature work to `/brainstorm`.
3. Both new skill directories carry `LICENSE.mattpocock` (MIT, Matt Pocock) in
   the one canonical tree; `tests/test-skill-frontmatter.sh`,
   `tests/test-skill-references.sh` and `tests/test-plugin-manifest.sh` pass
   (no `.claude/skills/` copy, no `jplugin:` literal in a skill body).
4. `/brainstorm` Step 3 invokes `/grilling` with frontier rounds as the default,
   keeps the multiple-choice preference, and no longer lists one question at a
   time as a key principle; Step 1 reads `tasks/concepts.md`; the Key Principles
   name rounds, the facts-versus-decisions split, and the glossary-only rule;
   Steps 4, 4.5, the hard gate, and the lightpanda paragraph are unchanged,
   Step 6 gains only the canonical-vocabulary constraint, and no `/tdd`
   reference exists.
5. `.agents/skills/brainstorm/references/domain-modeling.md` exists, is named
   from Step 3, and defines the glossary challenge, term sharpening, concrete
   scenarios, code cross-reference, inline `tasks/concepts.md` writes in the
   `/learn` entry format with the glossary-only rule, and the three-gate
   architecture-decision rule writing `tasks/solutions/architecture/<slug>.md`
   on the knowledge track, offered not assumed, overlap-scored per `/learn`.
6. `/writing-skills`' frontmatter note states the `false` default, the `true`
   exception for user-only front doors naming `/grill-me`, and the harness
   check.
7. `.github/upstreams.json` carries a source with `id` `mattpocock-skills`,
   `url` `https://github.com/mattpocock/skills.git`, `ref` `refs/heads/main`,
   `baseline` `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`, paths `LICENSE`,
   `skills/productivity/grilling/SKILL.md`,
   `skills/productivity/grill-me/SKILL.md`,
   `skills/engineering/domain-modeling/SKILL.md`, and `source_notice`
   `THIRD_PARTY_NOTICES.md`; `python3 scripts/check-upstream-drift.py` accepts
   the registry without a validation error (a drift report against a moved
   upstream is informational).
8. `THIRD_PARTY_NOTICES.md` has a section for the Matt Pocock skills linking the
   four upstream files at the pinned revision and quoting the MIT license text.
9. The `CLAUDE.md` skills table, the `README.md` skills table, and the
   `SKILLS AVAILABLE` block of `.claude/hooks/session-start.sh` each carry a
   `/grilling` row and a `/grill-me` row; `README.md` § Sources lists
   `mattpocock/skills`; `tests/test-session-start.sh` passes.
10. `tests/test-grilling-adoption.sh` pins criteria 1 to 9;
    `tests/test-skill-invocation-chain.sh` asserts `brainstorm` invokes
    `/grilling` and `grill-me` invokes `/grilling`; `bash tests/run.sh` is
    green.
11. Typing `/grill-me <idea>` in the Claude desktop harness (`/jplugin:grill-me`
    there, per the namespace sentence in `CLAUDE.md`) starts a round in
    the `❓` / `➡️` format and leaves `git status` unchanged; the walkthrough is
    recorded in `tasks/e2e-log.md`. A refusal is handled per Edge Cases and
    recorded the same way.
12. Running `/brainstorm` on a sample idea produces a first round in the
    `❓` / `➡️` format and writes one resolved term to `tasks/concepts.md`
    before the spec is written; the walkthrough is recorded in
    `tasks/e2e-log.md` and the sample term is reverted.
13. A `/eval` Mode A triggerability run of `grilling` from at least three
    organic brainstorm-shaped prompts is recorded in `tasks/e2e-log.md` with
    its hit rate; if the eval harness cannot run on this machine the entry says
    `UNVERIFIED` and why, and the criterion is never claimed as met.

## Out of Scope

- `/plan` Step 1, `/prd`, and `/system-design-planning` interviews. `/plan`
  conflicts with #106 in flight; the others follow once the primitive has an
  eval result. A follow-up task is filed through `/task-registry` after
  confirmation.
- Upstream's `CONTEXT.md` / `CONTEXT-MAP.md` file layout and ADR numbering. This
  repository's equivalents are `tasks/concepts.md` and the typed learning store.
- Upstream's `wayfinder`, `to-spec`, and `prototype` skills.

## Implementation Paths

- `.agents/skills/grilling/**` — the interview primitive and its license notice
- `.agents/skills/grill-me/**` — the stateless user-only front door and its
  license notice
- `.agents/skills/brainstorm/**` — Step 3 rewired to `/grilling`; the domain
  layer in `references/domain-modeling.md`
- `.agents/skills/writing-skills/SKILL.md` — the frontmatter note with the
  `true` exception
- `.github/upstreams.json` — the pinned upstream source the drift checker reads
- `THIRD_PARTY_NOTICES.md` — attribution and license text for the adapted files
- `CLAUDE.md` — skills table rows
- `README.md` — skills table rows and the Sources credit
- `.claude/hooks/session-start.sh` — `SKILLS AVAILABLE` banner rows
- `tests/test-grilling-adoption.sh` — pins criteria 1 to 9
- `tests/test-skill-invocation-chain.sh` — pins the two new `/grilling` handoffs
