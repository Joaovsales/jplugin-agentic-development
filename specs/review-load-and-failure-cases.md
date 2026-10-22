---
implementation_paths:
  - AGENTS.md
  - .agents/references/finding-model.md
  - .agents/references/review-dispatch-contract.md
  - .agents/agents/code-reviewer.md
  - .agents/agents/critic.md
  - .agents/agents/security-reviewer.md
  - .agents/agents/software-design-expert-review.md
  - .claude/agents/code-reviewer.md
  - .claude/agents/critic.md
  - .claude/agents/security-reviewer.md
  - .claude/agents/software-design-expert-review.md
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/software-design-expert-review/SKILL.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/tidy/SKILL.md
  - .claude-plugin/plugin.json
  - tests/test-agents.sh
  - tests/test-review-context.sh
  - tests/test-doc-conventions.sh
  - tests/fixtures/review-eval/**
---

# Spec: Review load and failure cases

Five review ideas adapted from ponytail (`DietrichGebert/ponytail`, MIT —
`skills/ponytail-review`, `skills/ponytail-audit`, `skills/ponytail-debt`),
restated in this harness's own words and fitted to the four-axis Finding Model.
The ponytail plugin itself is not installed.

## Summary

Reviews in this harness state the load they judged against, give every finding
a concrete failure case, and read well for a human without losing the four-axis
line the Apply Gate parses. The function-size rule becomes "split by job", the
two shortcut-marker rules become one, and shortcut debt can be listed on demand.
An A/B against ponytail's reviewer checks the result on seeded bugs.

## Behavior

**Expected load.** Every review states the load it judged against before it
reports anything: `Load assumed: <who and how many run this> (source: <path | none found>)`.
The reviewer looks for it in this order: the spec's § Edge Cases and § Decisions,
the `[NON-FUNCTIONAL]` section of `tasks/project-context.md`, then the README and
the deploy or routine config. If it finds none, it assumes one operator and one
process, and says so. The load then drives a scale checklist: check-then-write
races, the same work done by every process or session, state or lists that only
grow, one query or call per item, O(n²) on input that can be large, and
per-process state that has to be shared. A scale finding is valid only when the
assumed load reaches it.

**A failure case for every finding.** Beside `evidence:` (*where* the defect is),
every finding carries `failure:` (*what goes wrong*). For a correctness, security
or scale finding that is the input or situation and the wrong result it produces.
For a design or lean finding it is the concrete change or read the defect makes
harder. A finding with no `failure:` line is capped at confidence `50`, the same
way a finding with no `evidence:` line is.

**A human layer on top of the four axes — presentation only.** A review opens
with `What this change does:` in two or three sentences, plus the `Load assumed:`
line. Findings are numbered across all severities, so a person reading the
output, or a later turn, can refer to one by number. Each finding's description
ends with what happens if it is skipped. The review closes with `Verdict:`,
`Lean: -<N> lines possible` when lean findings exist, and `Not checked:`
naming what mattered but could not be read or run. The four-axis line stays the
first line of every finding, so the parsers and the Apply Gate are unchanged.

The layer adds no human-in-the-loop step. Nothing waits for an answer, nothing
asks "which should I fix?", and `/build` still runs with no prompts between
tasks. What gets applied, reported or escalated is decided exactly as today: by
the Apply Gate (`gated_auto` at confidence `75` or higher, never for a fix that moves a module boundary) and by the `owner`
axis. `Verdict:` restates a decision that already exists and never makes a new
one. In `/quality-gate` it is the receipt verdict `receipt.py` derives (GO / HOLD
/ STOP). In a dispatched persona it is a summary for the orchestrator, naming
the `MUST-FIX` numbers; the orchestrator's gate decides, not the persona.

**Banned content.** The reviewer personas drop the Strengths section, the
persona self-description and the free-form Recommendations list. They emit no
"consider…", no style taste and no vague worry: no `failure:` case, no finding.
`NITPICK` stays in the enum for objective cosmetic defects (an unused import, a
comment that contradicts the code).

**Split by job, never by line count.** The Clean Code rule in `AGENTS.md` and
`/quality-gate` Phase 1.2 no longer says "functions ≤20 LOC → split". It says:
split a function that does several unrelated jobs, by job; never split by line
count, and never into helpers that exist only to make a function shorter. A long
parameter list signals a shallow interface: the fix is the interface, not the
call site.

**One shortcut rule.** A `TODO(shortcut):` marker that names its limit is a
decision, not a finding, unless either (a) the assumed load already crosses the
limit it names — or the code's real limit, when that is narrower than the one
named — or (b) the shortcut opens a hole on the never-on-the-chopping-block
list (security, accessibility, trust-boundary validation, error handling that
prevents data loss). In either case the shortcut itself is the finding, citing the
marker and saying what it failed to account for. The rule's one home is
`finding-model.md` § *Deferrals*; personas and the dispatch contract cite it
instead of restating it.

**Shortcut debt on demand.** `/wrap-up-session` § *Shortcut ledger* stays the one
home of the ledger's command and format. Its pattern also matches `/*` and `<!--`
comment prefixes. `/tidy --check shortcuts` runs that same ledger on demand and
reports `no-trigger` markers as Tier 1.

## Inputs

- The diff (or tree, for `/sweep` and `/tidy`) under review, plus the dispatch
  payload `review-dispatch-contract.md` already defines.
- The load sources named under *Expected load*. They are read by the reviewer;
  they are not a new dispatch item.
- `TODO(shortcut):` markers in the tree.

## Outputs

- Reviewer and `/quality-gate` output in the human-and-agent format above.
- `/quality-gate` Phase 3 renamed `Security and Load`. It records
  `{"phase": 3, "lens": "security-scan+load", ...}` in the receipt.
- A new receipt policy hash, because `finding-model.md`,
  `review-dispatch-contract.md` and the gate's `SKILL.md` all change. Receipts
  minted before this change go stale once, as designed.
- `/tidy` report rows for check `shortcuts`.
- A Mode B `/eval` report comparing three reviewers on seeded-bug diffs.

## Edge Cases

- **No load source anywhere** → `Load assumed: one operator, one process (source: none found)`.
  Scale findings that need more load than that are not emitted.
- **This harness repository** → the load is several concurrent sessions sharing
  one clone (`tasks/solutions/`, the parallel-sessions learning). Races on shared
  registers such as `tasks/todo.md` are in scope.
- **Repo-survey dispatch** (`/sweep --routine architect`) → there is no "change",
  so the opener is `What this tree does:`; everything else is unchanged.
- **Finding with `evidence:` but no `failure:`** → capped at `50`, reported, never
  auto-applied, never dropped.
- **Design finding** → `failure:` names the change that costs more because of the
  defect (e.g. "adding a provider means editing A, B and C"). It is never left
  empty because "design has no input".
- **Marker whose limit the load already crosses** → the shortcut itself is the
  finding, severity by impact.
- **Marker that opens a security hole** → the finding is `MUST-FIX` whatever the
  marker says.
- **A `TODO(shortcut):` mentioned in prose without a comment prefix** (this
  spec, `AGENTS.md`) → not a ledger row.
- **A descendant project with a pinned older reviewer** → a finding with no
  `failure:` line reads as `50`. That is the existing degrade path, not a new error.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | Every existing quality receipt goes stale, because the policy hash covers `finding-model.md`, the dispatch contract and the gate's `SKILL.md` | H | L | expected and one-off; the next `/quality-gate` run mints a fresh receipt | 1 |
| R2 | A descendant still on an older reviewer emits no `failure:` line, so all its findings drop to `50` and none auto-apply | M | M | the existing degrade path; `/sync` carries the new personas downstream | 2 |
| R3 | `/wrap-up-session` is at its 300-line budget, so widening the ledger pattern could break `tests/test-instruction-budget.sh` | M | L | edit the pattern in place; the slice verify runs the budget test | 6 |
| R4 | Fixture names reveal the eval and candidates game it | L | M | neutral names, checked by the slice-7 verify | 7 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Add an expected-load step and scale checklist? | Yes: every reviewer states `Load assumed:` and checks the six scale patterns against it | user | biggest gap found against ponytail; the gate had no scale lens |
| 2 | Require a concrete failure case? | Yes: a `failure:` line beside `evidence:`; missing caps at `50` | user | the anchors prove a line was read, not that it fails |
| 3 | Human-friendly output? | A human layer (opener, numbering, skip consequence, Verdict / Lean / Not checked) on top of unchanged four-axis lines | user | readable for humans, still parseable for the Apply Gate |
| 4 | Ban filler? | Drop Strengths, persona prose and Recommendations; no "consider", taste or vague worries | user | noise that the finding model cannot gate |
| 5 | Function-size rule? | Split by job, never by line count, never into shorten-only helpers; a long parameter list signals a shallow interface, fixed at the interface | user | APOSD-aligned; the 20-LOC rule pushed toward shallow helpers |
| 6 | Debt reporting? | Keep `/wrap-up-session` § *Shortcut ledger* as home (it already scans the whole repo and tags `no-trigger`); widen the pattern and expose it as `/tidy --check shortcuts` | user | the earlier gap claim was wrong; the real delta is on-demand access |
| 7 | Shortcut rule? | Decision unless the load crosses its limit **or** it opens a never-cut hole; one home in `finding-model.md` § *Deferrals* | user | merges ponytail's load clause with this harness's security clause |
| 8 | Where does the scale check live in `/quality-gate`? | Inside Phase 3, renamed `Security and Load`; no new phase number | assumed | phases 1–4 are pinned in `receipt.py` and tests; both lenses ask "what breaks in production" |
| 9 | Does load become an eighth dispatch item? | No: the reviewer reads it from the repo ("fetch yourself") | assumed | "the seven items" is cited widely; load is discoverable from the tree |
| 10 | Keep the `NITPICK` severity? | Yes, for objective cosmetic defects only | assumed | the enum is pinned in `receipt.py`, every persona and the tests |
| 11 | Copy ponytail text verbatim? | No: restate in house style, cite the source in this spec and in a provenance line in `finding-model.md` | assumed | MIT requires the notice only for substantial copies; restating avoids a vendored licence file |
| 12 | `/tidy` tier for a `no-trigger` marker? | Tier 1 (report with remedy), never filed | assumed | adding a trigger needs judgment about the limit; filing one task per marker is noise |
| 13 | How is the A/B graded? | Against an answer key of seeded defects (recall, false positives), plus a blinded Ceiling judge on readability; variants on pushed branches per `/eval` Mode B | assumed | an answer key is mechanical; the judge only grades what the key cannot |
| 14 | Should `/quality-gate` gain a bug-hunting (`code-reviewer`) phase? | Out of scope; recorded as a follow-up | assumed | nothing in the main flow dispatches `code-reviewer` today; adding a phase changes the receipt contract |
| 15 | Does the human layer change who decides on findings? | No: presentation only. No new prompt or approval step; the Apply Gate, the `owner` axis and `receipt.py`'s verdict decide exactly as before, and `Verdict:` only restates them | user | readable for humans too, without adding a human in the loop |

## Acceptance Criteria

- AC1: `finding-model.md` § *Emission format* shows a `failure:` line under
  `evidence:`, and § *Gates* states that a finding with no `failure:` is capped
  at `50`. `tests/test-review-context.sh` pins both. `.claude-plugin/plugin.json`
  bumps its minor version.
- AC2: `finding-model.md` § *Deferrals* states the combined shortcut rule with both
  exceptions named. `review-dispatch-contract.md` item 5, `critic.md`,
  `security-reviewer.md` and the `software-design-expert-review` agent and skill
  cite it instead of restating it, in both agent trees. A test asserts the
  "load already crosses" clause appears in exactly one file under
  `.agents/references/` and `.agents/agents/`.
- AC3: `finding-model.md` § *Expected load* defines the `Load assumed:` line, the
  lookup order, the no-source default and the six scale patterns. `critic.md`,
  `security-reviewer.md` and `software-design-expert-review.md` reference it in
  both trees, and the skill's dispatch instruction asks for `failure:`. Both
  are pinned in `tests/test-agents.sh`.
- AC4: `code-reviewer.md` (both trees, still byte-identical) cites § *Deferrals* and
  § *Expected load*. It has no `## Strengths`, no "elite" or "master craftsman"
  persona prose and no `## Recommendations`. Its output template shows
  `What this change does:`, `Load assumed:`, numbered findings with `failure:`,
  and closing `Verdict:`, `Lean:` and `Not checked:` lines. Its `Verdict:` is described as a summary for the orchestrator,
  and the file contains no instruction to ask the user which finding to fix. It bans "consider",
  style taste and vague worries. `tests/test-agents.sh` asserts the absences
  and the presences.
- AC5: `/quality-gate` `## Phase 3 — Security and Load` runs the scale checklist
  against `Load assumed:` and records lens `security-scan+load`. Its § Output
  opens with `What this change does:` and `Load assumed:`, numbers the
  `Reported, not applied` findings with their `failure:` lines, and ends with
  `Lean:` and `Not checked:`. `tests/test-doc-conventions.sh` pins the heading,
  the lens and the output lines, and that the `Verdict:` line is the receipt verdict.
  `tests/test-quality-receipt.sh` stays green.
- AC6: `AGENTS.md` § Core Principles and `/quality-gate` Phase 1.2 contain "split by
  job" and "never by line count", and no longer contain "≤20 LOC" or ">20 LOC".
  `AGENTS.md` stays within the `tests/test-instruction-budget.sh` byte budget.
- AC7: `/wrap-up-session` § *Shortcut ledger* matches `/*` and `<!--` prefixes with
  no added lines (the file sits at its 300-line budget). `/tidy` lists check
  `shortcuts`, which cites that section and reports `no-trigger` markers as
  Tier 1. `tests/test-doc-conventions.sh` pins the check name and the citation.
- AC8: `tests/fixtures/review-eval/` holds four seeded diffs (a check-then-write race,
  an N+1 call, a time-zone off-by-one, and one harmless line that looks
  suspicious) with an answer key. The fixture names give no hint that they are
  an eval.
- AC9: A Mode B `/eval` run (N ≥ 2 per arm) compares the current `code-reviewer`, the
  updated one, and `ponytail-review` on recall, false positives, readability
  (blinded judge) and cost. The report path is in the PR body.

## Implementation Paths

- `.agents/references/finding-model.md` — the one home for `failure:`, § *Expected load* and § *Deferrals*
- `.agents/references/review-dispatch-contract.md` — item 5 cites § *Deferrals*
- `.agents/agents/*.md`, `.claude/agents/*.md` — the four review personas: human layer, bans, citations
- `.agents/skills/software-design-expert-review/SKILL.md` — its dispatch instruction asks for `failure:`
- `.agents/skills/quality-gate/SKILL.md` — Phase 1.2 rule, Phase 3 load lens, § Output
- `AGENTS.md` — Clean Code principle (managed block, so `/sync` carries it downstream)
- `.agents/skills/wrap-up-session/SKILL.md` — § *Shortcut ledger* pattern
- `.agents/skills/tidy/SKILL.md` — check `shortcuts`
- `.claude-plugin/plugin.json` — payload version bump
- `tests/test-agents.sh`, `tests/test-review-context.sh`, `tests/test-doc-conventions.sh` — pins
- `tests/fixtures/review-eval/**` — seeded diffs and answer key for the A/B

## Build Order

Sizing: 8 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 2 and 3 (systems: the `.agents/agents/` and `.claude/agents/` copies must change together or the parity test goes red between slices); slices 5 and 6 (systems: one source file plus the test file that pins it).

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Failure line | `failure:` in the emission format with its confidence cap, and the version bump | `.agents/references/finding-model.md`, `tests/test-review-context.sh`, `.claude-plugin/plugin.json` | — | 1 | `bash tests/test-review-context.sh` | 3 files · 3 systems · 1 AC |
| 2 | Deferrals and load home | § *Deferrals* and § *Expected load*, cited by the dispatch contract and three personas | `.agents/references/finding-model.md`, `.agents/references/review-dispatch-contract.md`, `.agents/agents/critic.md`, `.agents/agents/security-reviewer.md`, `.agents/agents/software-design-expert-review.md`, `.claude/agents/critic.md`, `.claude/agents/security-reviewer.md`, `.claude/agents/software-design-expert-review.md`, `.agents/skills/software-design-expert-review/SKILL.md`, `tests/test-agents.sh` | 1 | 2, 3 | `bash tests/test-agents.sh && bash tests/test-review-context.sh` | 10 files · 4 systems · 2 ACs |
| 3 | Code reviewer rewrite | the human layer and the bans in `code-reviewer` | `.agents/agents/code-reviewer.md`, `.claude/agents/code-reviewer.md`, `tests/test-agents.sh` | 2 | 4 | `bash tests/test-agents.sh` | 3 files · 3 systems · 1 AC |
| 4 | Gate load lens | Phase 3 `Security and Load` and the human-layer § Output | `.agents/skills/quality-gate/SKILL.md`, `tests/test-doc-conventions.sh` | 2 | 5 | `bash tests/test-doc-conventions.sh && bash tests/test-quality-receipt.sh` | 2 files · 2 systems · 1 AC |
| 5 | Split by job | the function-size rule in `AGENTS.md` and Phase 1.2 | `AGENTS.md`, `.agents/skills/quality-gate/SKILL.md`, `tests/test-doc-conventions.sh` | 4 | 6 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh && bash tests/test-sync-managed-block.sh` | 3 files · 3 systems · 1 AC |
| 6 | Shortcut ledger on demand | the wider ledger pattern and `/tidy --check shortcuts` | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/tidy/SKILL.md`, `tests/test-doc-conventions.sh` | 5 | 7 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh` | 3 files · 3 systems · 1 AC |
| 7 | Seeded review fixtures | four seeded diffs and their answer key | `tests/fixtures/review-eval/**` | — | 8 | `ls tests/fixtures/review-eval` | 5 files · 1 system · 1 AC |
| 8 | Reviewer A/B | the Mode B `/eval` report, linked from the PR body | `tests/fixtures/review-eval/**` | 3, 7 | 9 | manual: `/eval` Mode B, report path in the PR body | 0 files · 0 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/review-load-and-failure-cases.md`.
Plan: `## Plan: Review load and failure cases` in `tasks/todo.md`, 8 slices, ready set <1, 7>.
Files: AGENTS.md, .agents/references/finding-model.md, .agents/references/review-dispatch-contract.md, .agents/agents/code-reviewer.md, .agents/agents/critic.md, .agents/agents/security-reviewer.md, .agents/agents/software-design-expert-review.md, .claude/agents/code-reviewer.md, .claude/agents/critic.md, .claude/agents/security-reviewer.md, .claude/agents/software-design-expert-review.md, .agents/skills/quality-gate/SKILL.md, .agents/skills/software-design-expert-review/SKILL.md, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/tidy/SKILL.md, .claude-plugin/plugin.json, tests/test-agents.sh, tests/test-review-context.sh, tests/test-doc-conventions.sh, tests/fixtures/review-eval/**.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: scale lives inside Phase 3, no new phase number (D8); load is read by the reviewer, not an eighth dispatch item (D9); keep `NITPICK` (D10); restate ponytail in house style, no verbatim copy (D11); `no-trigger` is Tier 1, never filed (D12); grade the A/B against the answer key first, judge only readability (D13); no `code-reviewer` phase in the gate (D14); the human layer is presentation only, no new prompt or approval step, `Verdict:` restates the Apply Gate and receipt (D15); `/wrap-up-session` stays at 300 lines; keep `.agents/agents/` and `.claude/agents/` byte-identical.
```
