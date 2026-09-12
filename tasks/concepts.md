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

- **bulk-read gate** — the `PreToolUse` / `tool_call` hook that denies any single read putting more than `BULK_READ_MIN_LINES` (350) lines of one file into a model's context; it closes the expensive door and never rewrites the call. One Python script on Claude Code and Codex, a TypeScript mirror on Pi.
- **bulk-read handoff** — the rule the gate enforces: over the threshold, either dispatch `bulk-reader` with a question or read only the range an edit needs. Named in `CLAUDE.md` § Model Routing and one line each in `/plan`, `/build`, `/debug`, `/sweep`.
- **bulk-reader** — the Scout-tier persona that answers one question about a large file in bullets (`file:line` anchors on request); it never edits and never reasons about architecture, so its answer is context for a builder, not an edit anchor.
- **canonical tree** — `.agents/`, the source of truth for skills and agent personas; `.claude/` holds the byte-identical copy. Edits land canonical-first, then are copied.
- **circuit breaker** — the `/build`/`/yolo` failure escalation: repeated task failures trigger the `/refresh` backstop, then planner-tier review, then a loop stop — never a silent retry spiral.
- **claim label** — the tracker label (`in-progress` by default) a routine writes before branching; its *presence* is what stops two runs of the same routine picking one issue, so a claim label the tracker never created fails silently.
- **consumer routine** — a category routine (`plan`, `fix`, `improve`, deferred `build`) that selects one open issue by label and ships a change for it; contrast **producer routine**.
- **contract routine** — one of the six names `CONTRACT_ROUTINES` allows: four consumers (`plan`, `fix`, `improve`, `build`) and two producers (`janitor`, `architect`). Adding one is a deliberate edit to the contract, never a configuration key; reconfiguring an existing one is configuration.
- **cut** — one phase of a staged deletion, sized so it ships as a single revertable commit. Cuts are ordered so each one's survivors still compile against the next; the boundary is what a `git revert` must restore, not what a module diagram suggests.
- **deferred routine** — a contract routine specified but not runnable yet (`build`, behind #97/#98). It carries a skill chain so `workflow` can report it as deferred rather than as unknown — a different fact, and one that should not send a correctly labelled issue back to triage.
- **dispatch disclosure** — the required line in review output stating whether passes ran as separately dispatched agents or inline, naming the corroboration lost when inline.
- **downstream** — a project that installed this template via `install.sh` and receives updates through `/sync`; this repo is the upstream template.
- **harness** — an agent runtime the workflow supports (Claude Code, Pi); `harness: universal` prose must run identically on both.
- **heavy pass** — `/memory-maintain`'s every-5-sessions consolidation (Phases 1–4); contrast **light pass**, the bounded per-session work.
- **needs_review** — frontmatter flag marking a store document with inferred or missing required fields; resolved by `/memory-maintain` Phase 1.
- **parity** — the byte-identical requirement between the canonical tree and its `.claude/` copy, enforced by `tests/test-skill-parity.sh`.
- **producer routine** — a routine (`janitor`, `architect`) run through `/sweep` that reads the backlog, runs one engine over the whole tree, and files verified findings as issues; it never edits product code. Listed in `PRODUCER_ROUTINES` and refused by `select`/`claim`.
- **run stamp** — the `YYYYMMDD` number in a producer routine's branch (`routine/janitor/20260907-sweep`); occupies the slot where a consumer branch carries the issue number.
- **selector** — the set of provider labels a routine claims issues by, in `[routines.selectors]`. Disjoint across routines, so exactly one routine owns any issue.
- **shortcut** — a deliberate minimal implementation marked `TODO(shortcut):` with its limitation and upgrade path stated.
- **skill chain** — the ordered skills a routine runs once selection has chosen its issue, in `[routines.skills]`. Transcribed from the routine contract's step 4 plus the shared spine's step 5, which is why every chain ends at `/wrap-up-session`.
- **syncable root** — a directory `/sync` overwrites wholesale in a downstream project (`.agents/skills/`, `.claude/skills/`, and the other roots `sync/SKILL.md` lists). Project-local content placed under one is destroyed on the next sync, and a `SKILL.md` may not name a path outside them.
- **track** — one of the store's two document kinds, selected by `problem_type`: bug track (`symptoms`/`root_cause`/`resolution`) or knowledge track (`applies_when`).
