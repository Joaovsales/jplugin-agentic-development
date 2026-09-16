# Concepts — Project Glossary

> Project-specific vocabulary: entities, named processes, and status terms whose
> meaning is **local to this project**. Accretes as a side effect of `/learn`,
> never as a separate chore; pruned by `/memory-maintain` — a term with a
> standard industry meaning does not belong here. Entry format: one bullet per
> term, alphabetical within its section: `- **term** — definition.`
>
> Sweep: done 2026-08-13

## Harness vocabulary

- **ceiling** — model-tier resolution meaning "omit the model override so the sub-agent inherits the session model"; not a model name. Reserved for the highest-stakes review roles.
- **drift** — divergence between the two skill trees (`.agents/` canonical vs `.claude/` copy) or between a downstream project and this template; caught by the parity tests and the session-start drift check.
- **gate** — a hard checkpoint that blocks progress until its condition holds (plan confirmation, quality gate, evidence gate). A review reports; a gate stops.
- **register** — a single append-oriented markdown file under `tasks/` recording one kind of thing (todo, history, checkpoint, this glossary).
- **store** — the typed learning store at `tasks/solutions/`: one document per learning, YAML frontmatter, grep-first retrieval. Replaces the retired monolithic `tasks/memory.md`.
- **tier** — a model-routing band (Ceiling / Planner / Builder / Reviewer / Scout), or an adoption phase in a multi-mechanism spec (Tier 1–3).

## Project vocabulary

- **canonical tree** — `.agents/`, the source of truth for skills and agent personas; `.claude/` holds the byte-identical copy. Edits land canonical-first, then are copied.
- **circuit breaker** — the `/build`/`/yolo` failure escalation: repeated task failures trigger the `/refresh` backstop, then planner-tier review, then a loop stop — never a silent retry spiral.
- **claim label** — the tracker label (`in-progress` by default) a routine writes before branching; its *presence* is what stops two runs of the same routine picking one issue, so a claim label the tracker never created fails silently.
- **consumer routine** — a category routine (`plan`, `fix`, `improve`, deferred `build`) that selects one open issue by label and ships a change for it; contrast **producer routine**.
- **contract routine** — a lane whose file sets `routine:` (`consumer` or `producer`): four consumers (`plan`, `fix`, `improve`, `build`) and three producers (`janitor`, `architect`, `tidy`). `CONTRACT_ROUTINES` is the catalogue's `routines` view. Adding one is a new lane file, never a configuration key; reconfiguring an existing one's chain is configuration (`[routines.skills]`).
- **cut** — one phase of a staged deletion, sized so it ships as a single revertable commit. Cuts are ordered so each one's survivors still compile against the next; the boundary is what a `git revert` must restore, not what a module diagram suggests.
- **deferred routine** — a contract routine specified but not runnable yet (`build`, behind #97/#98). It carries a skill chain so `workflow` can report it as deferred rather than as unknown — a different fact, and one that should not send a correctly labelled issue back to triage.
- **dispatch disclosure** — the required line in review output stating whether passes ran as separately dispatched agents or inline, naming the corroboration lost when inline.
- **downstream** — a project that installed this template via `install.sh` and receives updates through `/sync`; this repo is the upstream template.
- **harness** — an agent runtime the workflow supports (Claude Code, Pi); `harness: universal` prose must run identically on both.
- **heavy pass** — `/memory-maintain`'s every-5-sessions consolidation (Phases 1–4); contrast **light pass**, the bounded per-session work.
- **lane** — one markdown file under `.agents/skills/task-registry/lanes/`, named for the lane: frontmatter both routers read (`routine`, `selects`, `cues`, `ends`, `deferred`), numbered steps `/go` records and the registry derives a chain from, and a *Reply* section. Twelve ship: the seven contract routines plus `investigate`, `refactor`, `perf`, `babysit`, `none`. A lane with `cues:` is reachable from a goal; one with `routine:` is reachable from a label; `fix`, `improve` and `plan` are both.
- **lane block** — the `## Lane: <lane> — <goal>` record `/go` appends to `tasks/todo.md`: plain numbered steps, never checkbox rows, so `/build` does not dispatch it as a task; a skipped step keeps its line with ` — skip: <reason>` appended.
- **lane catalogue** — the shipped set of lane files, read once by `registry/lanes.py` (`catalogue()`) and printed by `task-registry lanes`. Every routine constant the registry used to hardcode (`CONTRACT_ROUTINES`, `PRODUCER_ROUTINES`, `DEFERRED_ROUTINES`, `DEFAULT_SELECTORS`, `DEFAULT_ROUTINE_SKILLS`) is now a view of it, resolved lazily so `import registry.config` reads no lane file. Three pinned mirrors remain: the routine table in `routines.md`, `routine_branch.CONTRACT_ROUTINES`, and the template's `[routines.skills]` block.
- **needs_review** — frontmatter flag marking a store document with inferred or missing required fields; resolved by `/memory-maintain` Phase 1.
- **parity** — the byte-identical requirement between the canonical tree and its `.claude/` copy, enforced by `tests/test-skill-parity.sh`.
- **producer routine** — a routine (`janitor`, `architect` through `/sweep`; `tidy` through its own skill) that reads the backlog, runs one engine over the whole tree, and files verified findings as issues; it never edits product code (`tidy` commits Tier 0 repairs to harness surfaces only). Listed in `PRODUCER_ROUTINES` and refused by `select`/`claim`.
- **run stamp** — the `YYYYMMDD` number in a producer routine's branch (`routine/janitor/20260907-sweep`); occupies the slot where a consumer branch carries the issue number.
- **selector** — the set of provider labels a routine claims issues by, in `[routines.selectors]`. Disjoint across routines, so exactly one routine owns any issue.
- **shortcut** — a deliberate minimal implementation marked `TODO(shortcut):` with its limitation and upgrade path stated.
- **skill chain** — the ordered skills a lane runs, derived from its steps: a step that opens with a backticked skill is a skill step unless it ends ` — optional`. For a consumer routine a project may replace it in `[routines.skills]`; `task-registry lanes` and `workflow` both print the effective chain. Every routine lane's chain ends at `/wrap-up-session`; an interactive-only lane's need not.
- **syncable root** — a directory `/sync` overwrites wholesale in a downstream project (`.agents/skills/`, `.claude/skills/`, and the other roots `sync/SKILL.md` lists). Project-local content placed under one is destroyed on the next sync, and a `SKILL.md` may not name a path outside them.
- **track** — one of the store's two document kinds, selected by `problem_type`: bug track (`symptoms`/`root_cause`/`resolution`) or knowledge track (`applies_when`).
