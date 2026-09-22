# Concepts — Project Glossary

> Project-specific vocabulary: entities, named processes, and status terms whose
> meaning is **local to this project**. Accretes as a side effect of `/learn`,
> never as a separate chore; pruned by `/memory-maintain` — a term with a
> standard industry meaning does not belong here. Entry format: one bullet per
> term, alphabetical within its section: `- **term** — definition.`
>
> Sweep: done 2026-08-13

## Harness vocabulary
- **build prompt** — the fenced message a planning session ends with (`Spec and plan are ready to be built. Start a fresh session with this prompt:`): the spec path, the plan block, the ready set and the constraints a fresh `/build` session needs; written by `/slice` into the spec's § Build Order, which is its durable copy.
- **ceiling** — model-tier resolution meaning "omit the model override so the sub-agent inherits the session model"; not a model name. Reserved for the highest-stakes review roles.
- **drift** — divergence between a downstream project and this template (caught by the session-start drift check), or between a vendored skill and its pinned upstream revision in `.github/upstreams.json` (`scripts/check-upstream-drift.py`).
- **gate** — a hard checkpoint that blocks progress until its condition holds (plan confirmation, quality gate, evidence gate). A review reports; a gate stops.
- **handover** — the `> Handover:` blockquote `/build` writes under a slice's heading when the slice closes: what landed (`<short-sha>..<short-sha>`), what the next slice must not re-derive, optionally the surface report and one open question; passed verbatim into the delegation prompt of every slice blocked by it, and collected into the PR's `## Handovers` section.
- **ready set** — the slices whose `Blocked by` slices are all `[x]`, printed by `slice.py ready` with each one's surface and every intersecting pair; disjoint ready slices dispatch in parallel, an intersecting pair without a blocker is serialized in table order.
- **register** — a single append-oriented markdown file under `tasks/` recording one kind of thing (todo, history, checkpoint, this glossary).
- **slice** — one session-sized row of a spec's § Build Order (`# | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size`), under the ceiling in `slice/references/sizing.md`; in `tasks/todo.md` a `### Slice n/N — <name>` heading whose `- [ ]` header row is the registry's task and whose indented `[ ] TDD:` rows are the work.
- **store** — the typed learning store at `tasks/solutions/`: one document per learning, YAML frontmatter, grep-first retrieval. Replaces the retired monolithic `tasks/memory.md`.
- **surface** — the `implementation_paths` globs a slice may edit, declared in its Build Order row; an agent that must touch a file outside it reports `[SURFACE] +<path> | reason: …` and continues, and `slice.py check` reports `undeclared:` and `untouched:` paths when the slice closes.
- **tier** — a model-routing band (Ceiling / Planner / Builder / Reviewer / Scout), or an adoption phase in a multi-mechanism spec (Tier 1–3).


## Project vocabulary

- **canonical tree** — `.agents/`, the source of truth for skills and agent personas. Since #156 it is the only skill tree: no `.claude/skills/` copy exists, and Claude Code loads it as the `jplugin` plugin. `.claude/agents/` is still a Claude Code copy of `.agents/agents/`.
- **circuit breaker** — the `/build`/`/yolo` failure escalation: repeated task failures trigger the `/refresh` backstop, then planner-tier review, then a loop stop — never a silent retry spiral.
- **claim label** — the tracker label (`in-progress` by default) a routine writes before branching; its *presence* is what stops two runs of the same routine picking one issue, so a claim label the tracker never created fails silently.
- **consumer routine** — a category routine (`plan`, `fix`, `improve`, deferred `build`) that selects one open issue by label and ships a change for it; contrast **producer routine**.
- **contract routine** — one of the seven names `CONTRACT_ROUTINES` allows: four consumers (`plan`, `fix`, `improve`, `build`) and three producers (`janitor`, `architect`, `tidy`). Adding one is a deliberate edit to the contract, never a configuration key; reconfiguring an existing one is configuration.
- **cut** — one phase of a staged deletion, sized so it ships as a single revertable commit. Cuts are ordered so each one's survivors still compile against the next; the boundary is what a `git revert` must restore, not what a module diagram suggests.
- **deferred routine** — a contract routine specified but not runnable yet (`build`, behind #97/#98). It carries a skill chain so `workflow` can report it as deferred rather than as unknown — a different fact, and one that should not send a correctly labelled issue back to triage.
- **dispatch disclosure** — the required line in review output stating whether passes ran as separately dispatched agents or inline, naming the corroboration lost when inline.
- **downstream** — a project that installed this template via `install.sh` and receives updates through `/sync`; this repo is the upstream template.
- **front door** — a user-only skill (`disable-model-invocation: true`) whose whole body is one invocation of a primitive the model may load on its own; `/grill-me` is the front door to `/grilling`. Typed by the user, never self-invoked.
- **frontier** — the subset of open design-tree questions whose prerequisites are already settled and can be asked now (`/grilling`, `/brainstorm` Step 3); a round asks the whole frontier at once, and an empty frontier ends the interview.
- **harness** — an agent runtime the workflow supports (Claude Code, Pi); `harness: universal` prose must run identically on both.
- **heavy pass** — `/memory-maintain`'s every-5-sessions consolidation (Phases 1–4); contrast **light pass**, the bounded per-session work.
- **needs_review** — frontmatter flag marking a store document with inferred or missing required fields; resolved by `/memory-maintain` Phase 1.
- **parity** — (historical) the byte-identical requirement between `.agents/skills/` and its `.claude/skills/` copy, enforced by `tests/test-skill-parity.sh`; both retired with #156. Survives only for agent personas (`.agents/agents/` vs `.claude/agents/`).
- **producer routine** — a routine (`janitor`, `architect` through `/sweep`; `tidy` through its own skill) that reads the backlog, runs one engine over the whole tree, and files verified findings as issues; it never edits product code (`tidy` commits Tier 0 repairs to harness surfaces only). Listed in `PRODUCER_ROUTINES` and refused by `select`/`claim`.
- **round** — one `/grilling` turn: every frontier question numbered with a `❓` and a `➡️` recommended answer, answered together by the user; the opt-out line collapses a round to one question per turn.
- **run stamp** — the `YYYYMMDD` number in a producer routine's branch (`routine/janitor/20260907-sweep`); occupies the slot where a consumer branch carries the issue number.
- **selector** — the set of provider labels a routine claims issues by, in `[routines.selectors]`. Disjoint across routines, so exactly one routine owns any issue.
- **shortcut** — a deliberate minimal implementation marked `TODO(shortcut):` with its limitation and upgrade path stated.
- **skill chain** — the ordered skills a routine runs once selection has chosen its issue, in `[routines.skills]`. Transcribed from the routine contract's step 4 plus the shared spine's step 5, which is why every chain ends at `/wrap-up-session`.
- **syncable root** — a directory `/sync` overwrites wholesale in a downstream project (`.agents/skills/` and the other roots `sync/SKILL.md` lists; `.claude/skills/` is a RETIRED root, scanned for deletion and never checked out). Project-local content placed under one is destroyed on the next sync, and a `SKILL.md` may not name a path outside them.
- **track** — one of the store's two document kinds, selected by `problem_type`: bug track (`symptoms`/`root_cause`/`resolution`) or knowledge track (`applies_when`).
