# Spec: Compound Engineering Mechanism Adoption

> Source analysis: `EveryInc/compound-engineering-plugin` @ `249f68c` (2026-08-04, MIT).
> Adopts seven mechanisms into this harness. Ideas and protocols only — no code,
> prose, or file is copied verbatim from the source repo.

## Behavior

Seven independent mechanisms from the compound-engineering plugin are folded into
this workflow. They divide into three groups by cost and risk:

| Tier | Mechanisms | Why grouped |
|------|-----------|-------------|
| **Tier 1 — Foundations** | M5 model-tier resolution, M6 skill prose admission rules, M7 mechanical skill guards | No behavioral risk to running loops. M7's guards protect every later edit, so it lands first. |
| **Tier 2 — Review epistemics** | M1 independence accounting, M2 four-axis findings | Changes how reviews report and what they auto-apply. M2 depends on M1 (confidence promotion is only licensed by independence). |
| **Tier 3 — Knowledge compounding** | M3 typed learning store + migration, M4 accreting concept glossary | Replaces the monolithic knowledge store, ships a migration tool for existing projects, and cuts the whole harness over. The largest tier by blast radius. |

### M1 — Independence accounting

Corroboration between review findings counts **only** when the findings came from
separately dispatched contexts. Two lenses reasoned inside one context are two
perspectives, not two witnesses. A run that could not dispatch still reports its
findings, but must state the corroboration it lost instead of promoting on it.

Today `/wrap-up-session` Step 4 runs four review passes **sequentially in the main
context** on the universal path, and as four parallel agents only under "Claude Code
Enhancements". Both paths feed the identical severity-enforcement table. An inline
run is therefore indistinguishable from a real panel in the output.

### M2 — Four-axis findings

A finding currently carries one axis: `MUST-FIX` / `SHOULD-FIX` / `NITPICK`. Split
into four orthogonal fields:

| Field | Answers | Values |
|-------|---------|--------|
| `severity` | how urgent | `MUST-FIX` / `SHOULD-FIX` / `NITPICK` (unchanged) |
| `confidence` | how sure | discrete anchors `50` / `75` / `100`, each tied to a behavioral criterion |
| `autofix_class` | what shape the fix is | `gated_auto` / `manual` / `advisory` |
| `owner` | who acts | `agent` / `human` / `release` |

Gates:
- Any finding at `confidence` 75 or 100 **must** carry `evidence` — the verbatim
  motivating line with `file:line`. Missing evidence demotes it to 50.
- Independent corroboration promotes confidence by exactly one anchor. Same-context
  agreement never promotes (M1).
- On disagreement between reviewers, synthesis takes the **more conservative**
  `autofix_class`. It never widens.
- `/quality-gate` and `/wrap-up-session` auto-apply a finding only when it is
  `gated_auto` **and** `confidence >= 75`. Everything else is reported.

### M3 — Typed learning store (full migration)

`tasks/memory.md` is **retired**. Its five sections are split by kind, because they
were never the same kind of thing:

| Current section | Kind | Destination |
|-----------------|------|-------------|
| `## Architecture Decisions` (table) | learning, knowledge track | `tasks/solutions/<category>/<slug>.md` |
| `## Patterns & Lessons` (`### Title` + Context/Pattern/Evidence) | learning, knowledge track | `tasks/solutions/<category>/<slug>.md` |
| `## Session History` — `- Pattern:` bullets | learning that leaked into the log | `tasks/solutions/<category>/<slug>.md` |
| `## Session History` — entry bodies | narrative log, not a learning | `tasks/history.md` |
| `## Project Context` | project identity, not a learning | `tasks/project-context.md` |

`tasks/lessons.md` and `tasks/bugs.md` are likewise retired into the store:
lessons become knowledge-track documents, bug-register rows become bug-track
documents.

The store's shape:

```
tasks/solutions/<category>/<slug>.md
```

with typed YAML frontmatter and two tracks selected by `problem_type`:

- **bug track** — requires `symptoms`, `root_cause`, `resolution`
- **knowledge track** — requires `applies_when`

Both tracks require `title`, `date`, `problem_type`, `module`, `tags`. The date
lives in frontmatter, **never in the filename** — filenames are stable slugs so
cross-links do not rot.

Retrieval is grep-first on frontmatter, so a session loads only the documents
relevant to what it is doing. This is the point of the whole change: today
`session-start.sh` dumps all of `tasks/memory.md` into context on every session,
and that cost grows monotonically with the project's age.

Before writing, `/learn` scores overlap against existing documents across five
dimensions (problem, root cause, solution, files touched, prevention rule):

| Score | Dimensions matched | Action |
|-------|-------------------|--------|
| High | 4–5 | Update the existing document. Do not create a second one. |
| Moderate | 2–3 | Create the new document and cross-link both. |
| Low | 0–1 | Create the new document. |

Grounding rule: a claim about how code behaves must be verified against the tree
and cited as `file:line`, or softened and attributed. Cite PR numbers, not bare
commit SHAs — rebase and squash merges rewrite SHAs.

### M3-MIG — Standalone migration script

Existing projects that already carry the old store must be able to convert without
an agent session. `scripts/migrate-learning-store.py` is a standalone, idempotent,
dry-run-by-default converter.

**Interface**

```
migrate-learning-store.py [--apply] [--force] [--repo <path>] [--report <path>]
```

| Flag | Effect |
|------|--------|
| *(none)* | Dry run. Prints the full plan — every document it would write, every file it would archive, every unmappable entry — and writes nothing. |
| `--apply` | Performs the migration. |
| `--force` | Proceed despite a dirty git tree (default: refuse, so `git checkout` is always an escape hatch). |
| `--repo` | Target repository root. Defaults to `git rev-parse --show-toplevel`, then the working directory. |
| `--report` | Write the report to a file as well as stdout. |

**Inputs** — all optional. A missing input is a normal state, not an error; this
repo has no `tasks/lessons.md` at all, and `project-template/` has no
`tasks/memory.md`.

**Source-schema tolerance.** `tasks/bugs.md` exists in the wild with at least two
different column sets: this repo's 8-column form (`ID | Date | Description | Root
Cause | Fix | Files | Status | Regression Test`) and `project-template/`'s
5-column form (`ID | Date | Description | Status | Notes`). The script reads the
header row to map columns by name and does not assume a fixed arity. An unknown
column is carried into the document body rather than dropped.

**Unmappable content** is migrated, not skipped. Any document with an inferred or
absent required field is stamped `needs_review: true` and listed in the report.
Free-form `lessons.md` prose and 5-column bug rows (no root cause, no fix) are the
expected sources of this flag. Nothing is lost, and nothing silently claims to be
complete. `/memory-maintain` later sweeps the flagged documents.

**Safety model**

- Dry run is the default. Writing requires `--apply`.
- Originals are **moved** to `tasks/archive/<UTC-timestamp>/`, never deleted.
- Refuses to run on a dirty git tree without `--force`.
- Idempotent: a second run on a migrated tree detects the completed migration and
  exits 0 having done nothing, saying so.
- If `tasks/project-context.md` already exists — `/prd` generates it — the script
  does **not** overwrite. It writes `tasks/project-context.migrated.md` and reports
  the conflict for a human to reconcile.
- Slugs are ASCII kebab-case derived from the title; a collision gets a numeric
  suffix rather than overwriting a sibling.
- Dates come from the source (bug row `Date`, session-history heading), else the
  source file's last-commit date, else today — and the fallback used is recorded.
- Exit non-zero on any failure, with the failing source named.

### M4 — Accreting concept glossary

`tasks/concepts.md` holds project-specific vocabulary: entities, named processes,
and status terms whose meaning is local to the project. It accretes as a **side
effect** of `/learn`, never as a separate chore, and is pruned by
`/memory-maintain`. It is a glossary — not a spec, not a catch-all.

### M5 — Model-tier resolution

Two defects in the current routing rules:

1. `CLAUDE.md` and `/build`'s Model Routing table pin `code-reviewer`,
   `security-reviewer`, `critic`, and `software-design-expert-review` to `sonnet`,
   and `CLAUDE.md` mandates *"pass `model` explicitly on every Agent tool call"*.
   A session running Opus therefore gets Sonnet reviewers — the rule downgrades
   review quality for the users who paid for the better model.
2. The Pi column hardcodes concrete model IDs (`moonshotai/kimi-k3`,
   `qwen/qwen3-coder-next`, `z-ai/glm-4.7`, `deepseek/deepseek-v4-flash`), so the
   table goes stale on every model release.

Fix: add a **`ceiling`** resolution to the existing four-tier table, meaning
*omit the model override and inherit the session model*. The three highest-stakes
review roles resolve to `ceiling`. Where a harness cannot select a model per agent,
`ceiling` is also the correct fallback — a working review on the parent model beats
a failed dispatch on an unrecognized model name.

Tier names stay as they are (Planner / Builder / Reviewer / Scout). Only the
resolution rule changes.

### M6 — Skill prose admission rules

`/writing-skills` gains an admission test for every line of skill prose. A line
earns its place only if it:

- states a **falsifiable constraint**, or
- counters a **known default tendency** of the model, or
- supplies domain knowledge that **materially changes a decision**.

Explicitly inadmissible: vague effort language ("be thorough", "produce
high-quality work") as a standalone instruction; motivational rationale appended to
a directive that already stands on its own; an instruction repeated anywhere other
than a demonstrated drift point where placement changes whether it fires.

`/receive-review` gains the matching triage protocol for applying feedback to a
skill:

1. **Classify** each item `Change` / `Verify` / `Consider`. Do not edit for
   `Verify` or `Consider`.
2. **Locate the owning layer** — activation contract, outcome spine, runtime
   protocol, placement, deterministic enforcement, or shared rule.
3. **Fix at the smallest mechanism** in that layer. Prose only when it *is* the
   smallest mechanism.
4. **Reconcile** — reread the block and remove what the change made redundant or
   contradictory.

### M7 — Mechanical skill guards

Deterministic invariants about skill content move into the existing zero-dependency
bash test harness. Non-deterministic prose *behavior* stays out of tests — it is
evidence gathered by running the skill, never a test assertion.

New guards:

| Guard | Catches |
|-------|---------|
| Reference integrity | A skill mentions `references/x.md` or `scripts/y.sh` that does not exist inside that skill's directory |
| Self-containment | A skill references a path outside its own directory (sibling skill, absolute path, installed-plugin path) |
| Frontmatter validity | Missing `name`/`description`, `name` not matching the directory, over-long description |
| Banned constructs | Load-time shell pre-resolution in skill bodies |

Right-sizing rule for all future guards: prefer tightening an existing assertion
over adding a new file; pin the **smallest falsifiable unit** (a token, enum, path,
or heading) that would have failed on the regressing change; never snapshot whole
skill bodies or pin incidental wording.

## Inputs

- The seven mechanisms above, as analyzed from the source repo.
- Current harness state: 28 canonical skills in `.agents/skills/`, 10 agents in
  `.agents/agents/`, 11 bash test files in `tests/`.
- Real content shapes the migration must consume, read from disk rather than
  assumed: `tasks/memory.md` (5 heterogeneous sections, one session-history entry
  with two `- Pattern:` bullets leaked into it), `tasks/bugs.md` (8-column here,
  5-column in `project-template/`), no `tasks/lessons.md` in this repo,
  no `tasks/memory.md` in `project-template/`.
- Scoping decisions taken before writing:
  - one spec, three tiers (matches `specs/superpowers-practices-adoption.md`)
  - M3 is a **full migration** with a standalone script, not additive
  - `memory.md` is split by kind and retired; session history and project context
    are not learnings and get their own files
  - unmappable content migrates with `needs_review: true` rather than being skipped
  - `/quality-gate` keeps auto-applying, gated on `autofix_class` + `confidence`

## Outputs

### New files

| Path | Purpose |
|------|---------|
| `tasks/solutions/README.md` | Frontmatter schema, enums, category map, two-track rules |
| `tasks/solutions/.gitkeep` | Keeps the empty store in git |
| `tasks/history.md` | Session narrative log, migrated out of `memory.md` |
| `tasks/concepts.md` | Seeded project glossary |
| `scripts/migrate-learning-store.py` | Standalone migration tool |
| `tests/test-skill-references.sh` | Reference-integrity + self-containment guards |
| `tests/test-skill-frontmatter.sh` | Frontmatter validity guard |
| `tests/test-model-tiers.sh` | Asserts `ceiling` roles carry no pinned model |
| `tests/test-solutions-schema.sh` | Validates any store document against the schema |
| `tests/test-migrate-learning-store.sh` | Fixture-driven migration tests |
| `project-template/tasks/solutions/README.md` | Downstream seed |
| `project-template/tasks/concepts.md` | Downstream seed |
| `project-template/tasks/history.md` | Downstream seed |

### Retired files

Moved to `tasks/archive/<UTC-timestamp>/` by the migration, in this repo and in
every downstream project that runs it:

- `tasks/memory.md`
- `tasks/lessons.md` (absent here; present in `project-template/` and downstream)
- `tasks/bugs.md`

### Modified files

| Path | Change |
|------|--------|
| `CLAUDE.md` | `ceiling` tier + resolution rule; Independence Accounting subsection; Review Gate Taxonomy note; Session Start Checklist no longer reads `memory.md`; Key Directories replaces `memory.md`/`lessons.md`/`bugs.md` rows with `solutions/`, `history.md`, `concepts.md` |
| `README.md` | Store description and directory listing |
| `install.sh` | Seeds the new task files instead of `lessons.md` / `bugs.md` |
| `.agents/hooks/session-start.sh` | Reports store counts in one line; stops dumping `memory.md` and `lessons.md` |
| `.agents/hooks/pre-compact.sh` | Flushes to the new destinations |
| `.agents/skills/learn/SKILL.md` | Writes typed documents; overlap scoring; grounding rule; concept capture |
| `.agents/skills/memory-maintain/SKILL.md` | Sweeps `tasks/solutions/`; sweeps `needs_review` documents; prunes `tasks/concepts.md` |
| `.agents/skills/debug/SKILL.md` | Bug register becomes bug-track documents |
| `.agents/skills/wrap-up-session/SKILL.md` | Four-axis findings; enforcement; independence disclosure; tier-based models; new store paths |
| `.agents/skills/quality-gate/SKILL.md` | Four-axis findings; evidence gate; gated auto-apply; independence disclosure |
| `.agents/skills/{auto-improve,brainstorm,build,checkpoint,prd,refresh,sync,start-qa}/SKILL.md` | Path references updated to the new store |
| `.agents/skills/writing-skills/SKILL.md` | Prose admission rules; guard right-sizing rule |
| `.agents/skills/receive-review/SKILL.md` | Change/Verify/Consider triage; owning-layer protocol |
| `.agents/skills/plan/SKILL.md` | Model Routing note points at the `ceiling` rule |
| `.agents/skills/debug/templates/bug-report-template.md` | Emits store frontmatter |
| `.agents/agents/{code-reviewer,critic,security-reviewer,software-design-expert-review}.md` | Emit the four finding fields with the evidence gate |
| `.claude/agents/` (same four) | Same, plus remove the `sonnet` pin from `ceiling` roles |
| `tests/test-doc-conventions.sh` | **Invert** the existing assertion that `/build` and `/checkpoint` reference `tasks/memory.md` — it must now assert they do *not*; add banned-construct assertions |
| `.claude/skills/**` | Byte-identical copies of every `.agents/skills/` edit |

**Blast radius, measured not estimated**: 11 canonical skills reference
`tasks/memory.md` (22 files across both trees), 6 reference `tasks/lessons.md`, 5
reference `tasks/bugs.md`, plus both hooks, `CLAUDE.md`, `README.md`, `install.sh`,
and one existing test assertion that must be inverted.

## Edge Cases

### Migration

- **A source file is absent.** Normal state. Skip it silently; do not create an
  empty document or fail. This repo has no `tasks/lessons.md`.
- **`tasks/bugs.md` uses an unknown column set.** Map by header name, not position.
  Carry unrecognized columns into the document body. Never drop a column silently.
- **A bug row has no root cause or fix** (5-column template schema). Migrate on the
  bug track with those fields empty and `needs_review: true`. Report it.
- **`tasks/lessons.md` is free-form prose with no entry delimiter.** Split on
  headings when present, else on blank-line-separated blocks; one document per
  block, `needs_review: true`. A single unsplittable file becomes one document.
- **Patterns leaked into `## Session History`.** The real 2026-07-08 entry contains
  two `- Pattern:` bullets. Extract each as its own knowledge-track document *and*
  leave the narrative bullet in `tasks/history.md`, cross-linked. Duplication
  between a log and a learning is correct; the log is a record of what happened.
- **`tasks/project-context.md` already exists** (from `/prd`). Do not overwrite.
  Write `tasks/project-context.migrated.md`, report the conflict, exit 0.
- **The migration is run twice.** Detect the completed state, do nothing, exit 0,
  and say why. Never produce duplicate documents.
- **The git tree is dirty.** Refuse without `--force`, so `git checkout` remains an
  escape hatch.
- **Not a git repository.** `--repo` or the working directory is the root; the
  dirty-tree check is skipped with a note, not an error.
- **Two entries slug to the same filename.** Numeric suffix. Never overwrite.
- **An entry has no date anywhere.** Fall back to the source file's last-commit
  date, then today, and record which fallback was used in the document.
- **A downstream project has diverged `memory.md` sections.** Unrecognized `##`
  sections are copied verbatim into `tasks/archive/` and named in the report as
  unmigrated. The script does not guess at a destination.

### Review epistemics

- **A reviewer emits the old single-axis format.** Treat a finding with no
  `confidence` as anchor 50 and `autofix_class: manual` — reported, never
  auto-applied. No reviewer output is discarded.
- **Confidence 100 with no `file:line` evidence.** Demote to 50; keep the finding.
- **Inline degrade on a harness with no subagents.** Reviews still run and findings
  still apply, but no promotion occurs and the run states which corroboration was
  unavailable. This is the correct floor, not a failure.

### Guards

- **A stale worktree exists under `.claude/worktrees/`.** It contains full copies of
  both skill trees. Every new guard must exclude it, or it double-scans and reports
  phantom violations. (One such worktree is present today.)
- **Reference-integrity false positive on a teaching example.** A skill quoting a
  broken path as an anti-pattern must fence it; the guard skips fenced blocks when
  scanning for escaping references. Anti-pattern examples outside fences are a
  finding, not an exemption.

### Store

- **Overlap scored High but the existing document is wrong.** Update the existing
  document rather than adding a contradicting sibling; note the correction in it.
- **`tasks/solutions/` does not exist.** `/learn` creates it on first write.
- **A learning has no verifiable code claim.** Write it on the knowledge track with
  claims attributed to the session rather than stated as fact.
- **`tasks/concepts.md` grows into a catch-all.** `/memory-maintain` prunes any
  entry that is not project-specific vocabulary. A term with a standard industry
  meaning does not belong there.
- **`/sync` reaches a project that has not migrated.** `/sync` overwrites
  `CLAUDE.md` and the skills, so a project can end up with new skills and an old
  store. The synced `CLAUDE.md` must therefore name the migration script, and
  `/sync` must detect an unmigrated store and tell the user to run it.

## Acceptance Criteria

### Tier 1 — Foundations

- [ ] `tests/test-skill-references.sh` exists, runs under `tests/run.sh`, excludes
      `.claude/worktrees/`, and fails on a deliberately introduced dangling
      `references/` path
- [ ] The same test fails on a deliberately introduced cross-skill or absolute path
- [ ] `tests/test-skill-frontmatter.sh` asserts every skill in both trees has
      `name` + `description`, and that `name` matches its directory
- [ ] `tests/test-doc-conventions.sh` gained a banned-construct assertion for
      load-time shell pre-resolution
- [ ] Every existing skill passes all new guards, or a real violation is fixed
      (violations get fixed, never allowlisted, unless a written reason is recorded)
- [ ] `CLAUDE.md` Model Routing defines `ceiling` as "omit the override, inherit the
      session model" and names it as the cross-harness fallback
- [ ] `code-reviewer`, `security-reviewer`, and `critic` resolve to `ceiling` in
      `CLAUDE.md` and `/build`'s tables
- [ ] `.claude/agents/` no longer pins a model for those three roles
- [ ] `tests/test-model-tiers.sh` fails if a `ceiling` role regains a pinned model
- [ ] `CLAUDE.md`'s "pass `model` explicitly on every Agent tool call" is reworded
      so it cannot be read as requiring an override for `ceiling` roles
- [ ] `/writing-skills` carries the three-part prose admission test, the three
      inadmissible categories, and the guard right-sizing rule
- [ ] `/receive-review` carries Change/Verify/Consider plus the four-step
      owning-layer protocol
- [ ] `tests/run.sh` is green

### Tier 2 — Review epistemics

- [ ] `CLAUDE.md` has an Independence Accounting subsection stating that
      corroboration requires separately dispatched contexts
- [ ] `/wrap-up-session` Step 4 states, in its output, whether the four passes ran
      as dispatched agents or inline, and names the lost corroboration when inline
- [ ] `/quality-gate` states the same for Phase 3
- [ ] Neither skill promotes a finding on same-context agreement
- [ ] Both skills define all four finding axes with the behavioral criterion for
      each confidence anchor
- [ ] Both skills require `file:line` evidence at anchor 75+ and demote on absence
- [ ] Both skills auto-apply only `gated_auto` findings at anchor 75+
- [ ] Both skills take the more conservative `autofix_class` on reviewer
      disagreement and never widen
- [ ] A finding arriving with no `confidence` is treated as 50 / `manual`
- [ ] The four review agent definitions emit all four fields in both trees
- [ ] `/yolo`, `/auto-push`, and `/auto-improve` still run unattended end to end
      with no new prompts
- [ ] `tests/run.sh` is green

### Tier 3.1 — Store schema and migration script

- [ ] `tasks/solutions/README.md` defines the frontmatter schema, both tracks with
      their required fields, the `problem_type` enum, the category map, and
      `needs_review`
- [ ] `tests/test-solutions-schema.sh` fails on a document with an unknown
      `problem_type`, a missing track-required field, or a date in the filename
- [ ] `scripts/migrate-learning-store.py` runs on this repo in dry-run mode and
      prints a plan naming every document it would write
- [ ] The script converts all five `memory.md` section kinds to their correct
      destinations, including extracting the two `- Pattern:` bullets currently
      leaked into the 2026-07-08 session-history entry
- [ ] The script maps `bugs.md` columns by header name and handles both the
      8-column and 5-column schemas from fixtures
- [ ] The script stamps `needs_review: true` on every document with an inferred or
      missing required field, and lists each in the report
- [ ] The script writes nothing without `--apply`
- [ ] The script archives originals to `tasks/archive/<UTC-timestamp>/` and deletes
      nothing
- [ ] The script refuses a dirty git tree without `--force`
- [ ] A second run detects the completed migration, changes nothing, and exits 0
- [ ] The script does not overwrite an existing `tasks/project-context.md`; it
      writes `.migrated.md` and reports the conflict
- [ ] The script exits non-zero on failure, naming the failing source
- [ ] `tests/test-migrate-learning-store.sh` covers: absent inputs, both bug
      schemas, free-form lessons, slug collision, missing date, re-run idempotency,
      dirty-tree refusal, `project-context.md` conflict, unrecognized `##` section
- [ ] The script resolves its interpreter by probing `python3`, `python`, `py`

### Tier 3.2 — Cut the harness over

- [ ] This repo's own store is migrated with `--apply`, and `tasks/archive/`
      holds the originals
- [ ] `tests/test-doc-conventions.sh`'s `tasks/memory.md` assertion is **inverted**
      and passes
- [ ] No file outside `tasks/archive/` and `specs/` references `tasks/memory.md`,
      `tasks/lessons.md`, or `tasks/bugs.md` — verified by grep across both trees,
      hooks, `CLAUDE.md`, `README.md`, and `install.sh`
- [ ] `session-start.sh` reports store counts in one line, dumps no document
      bodies, and its banner does not grow by more than one line
- [ ] `pre-compact.sh` flushes to the new destinations
- [ ] `CLAUDE.md`'s Session Start Checklist and Key Directories describe the new
      store
- [ ] `/learn` writes `tasks/solutions/<category>/<slug>.md` with the date in
      frontmatter, scores overlap across the five dimensions, updates rather than
      duplicates at High, and carries the grounding rule
- [ ] `/debug` and its bug-report template write bug-track documents
- [ ] `/memory-maintain` sweeps the store for stale, contradicted, and
      `needs_review` documents
- [ ] `/sync` detects an unmigrated store and instructs the user to run the script
- [ ] `install.sh` and `project-template/` seed the new files and no longer seed
      `lessons.md` or `bugs.md`
- [ ] `tests/run.sh` is green

### Tier 3.3 — Concept glossary

- [ ] `tasks/concepts.md` exists, seeded with the vocabulary this harness already
      uses (tier, gate, register, drift, ceiling, store)
- [ ] `/learn` adds a concept entry when a learning surfaces project-specific
      vocabulary, with no separate prompt
- [ ] `/memory-maintain` prunes non-project-specific entries
- [ ] `CLAUDE.md` Key Directories lists `tasks/concepts.md`
- [ ] `project-template/` carries the glossary seed
- [ ] `tests/run.sh` is green

## Non-Goals

- **No rewriting of migrated content.** The script converts structure and stamps
  metadata. It does not improve prose, infer root causes from the codebase, or
  merge near-duplicates. `needs_review: true` plus `/memory-maintain` is how quality
  gets fixed, on a later deliberate pass.
- No cross-model peer review, model identity receipts, or detached job
  infrastructure. The one idea kept from that area is free and already covered by
  M1: never claim independent corroboration from a model whose identity was only
  requested.
- No plugin/marketplace packaging, and no multi-harness converter. This repo stays
  two harnesses maintained by byte-identical copies plus `/sync`.
- No collapse of `.agents/agents/` into skill-local personas. The source repo ships
  zero standalone agents on purpose, but Claude Code's typed dispatch is more
  ergonomic here. Deliberate divergence, revisit separately.
- No word-count or leanness target for existing skills. M6 governs new and revised
  prose; it is not a licence to sweep the corpus.
- No cleanup of the stale `.claude/worktrees/` checkout. The guards exclude it;
  removing it is separate work.

## Out of Scope — candidates for a follow-up spec

Two mechanisms from the same analysis are deliberately **not** in this spec:

- **Subagents write to disk, return a path.** A subagent asked to return long prose
  inline intermittently returns a summary instead, and the original is unrecoverable
  from the orchestrator side. Complements the existing
  `AGENTS.md` § *Large-Artifact Handoff*, which covers only the inbound
  direction.
- **Settled-decision provenance.** Annotate decisions the user examined at the
  `/plan` gate so `/quality-gate` and `critic` augment rather than re-litigate them,
  with the rule that an unexamined assertion is a directive and gets exactly one
  challenge. Pairs with the existing `[AMBIGUITY]` protocol, which covers only the
  agent's own forced picks.

## Assumptions Taken

Stated rather than asked, because each has a clearly better answer in this repo:

1. **The migration script is Python 3**, at `scripts/migrate-learning-store.py`
   beside `bootstrap-worktree.sh`, resolving its interpreter by probing `python3`,
   `python`, `py`. Python already ships in two skills
   (`html-presentation/scripts/generate-presentation.py`,
   `visual-recap/scripts/visual-render.py`), so it is an established dependency, and
   parsing three markdown formats in bash would be worse engineering than the
   dependency is a cost.
2. **Guards extend the existing bash harness** — `tests/test-*.sh` sourcing
   `tests/lib.sh`, zero external dependencies. Adding a Node/TS test layer buys
   nothing here.
3. **The store lives at `tasks/solutions/`** and the glossary at
   `tasks/concepts.md`, matching the existing `tasks/` register convention in
   `AGENTS.md` § Key Directories rather than the source repo's root `CONCEPTS.md`
   and `docs/solutions/`.
4. **Shared rules go in the `AGENTS.md` managed block**, which `/sync` propagates
   and every harness reads (Claude Code through the `CLAUDE.md` pointer). Skill
   mechanics go in the relevant `SKILL.md`. Text below the block's end marker is
   the project's own — `/sync` never rewrites it, so a rule placed there would
   not reach downstream projects.
5. **Confidence anchors are 50 / 75 / 100** with 75 as the actionable threshold,
   matching the source repo's calibration rather than inventing a new scale.
6. **Archive, never delete.** The migration moves originals aside; a human decides
   whether to remove `tasks/archive/`.

## Files Likely Involved

- `scripts/migrate-learning-store.py` — the migration tool
- `AGENTS.md`, `README.md`, `install.sh` — store description, checklist, seeds
- `.agents/hooks/{session-start.sh,pre-compact.sh}` — stop reading the monolith
- `.agents/skills/{learn,memory-maintain,debug,quality-gate,wrap-up-session,writing-skills,receive-review,build,plan,auto-improve,brainstorm,checkpoint,prd,refresh,sync,start-qa}/SKILL.md`
- `.claude/skills/**` — byte-identical copies (parity-tested)
- `.agents/agents/{code-reviewer,critic,security-reviewer,software-design-expert-review}.md` + `.claude/agents/` copies
- `tests/{run.sh,lib.sh,test-doc-conventions.sh}` + five new guard scripts
- `tasks/{solutions/README.md,history.md,concepts.md}` — new artifacts
- `project-template/tasks/` — downstream seeds
