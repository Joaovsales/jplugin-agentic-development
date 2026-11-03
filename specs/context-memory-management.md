# Spec: Context & Memory Management Hardening (P1–P5)

> Derived from June-2026 research on long-running agent harnesses (Anthropic
> "Effective harnesses for long-running agents", Mastra "Observational Memory",
> "Self-Compacting LM Agents"). Closes the workflow's in-task context-control gap
> while tightening its already-strong long-term memory loop.

## Background & Constraints (read first)

- **Skills are dual-located.** Every skill exists in `.agents/skills/<name>/SKILL.md`
  (canonical, harness-neutral) **and** `.claude/skills/<name>/SKILL.md` (the copy
  Claude Code executes). Both are syncable. **Every skill change and every new skill
  in this spec must be applied to both locations**, kept byte-identical except where
  a file is intentionally Claude-Code-only.
- **A skill/hook cannot read the live token count.** The ~75% threshold is owned by
  Claude Code's *native auto-compact* (configured via `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  in `.claude/settings.json`). Our job is to make that event *safe* (P1) and to keep
  context low *between* compactions via semantic checkpoints (P2). We do **not** build
  a token gauge.
- **Hook I/O contract.** Claude Code passes hook input as JSON on stdin. Follow the
  existing `pre-push-guard.sh` pattern: parse with `jq`, fall back gracefully when
  `jq` is absent. The `SessionStart` hook receives a `source` field
  (`startup|resume|compact|clear`); `PreCompact` receives `trigger` (`auto|manual`).
- **No test framework exists.** Introduce a zero-dependency bash test harness under
  `tests/` (mock JSON on stdin, assert on emitted output and written files).

---

## Behavior

### P1 — PreCompact safety-net hook
Before Claude Code compacts context (auto at ~75% or manual `/compact`), a new
`PreCompact` hook flushes live working state to disk so nothing critical is lost to a
lossy summary. On the *next* turn after a compaction, the `SessionStart` hook —
invoked by Claude Code with `source=compact` — re-orients the agent from disk instead
of printing the full first-run banner.

- **Flush (PreCompact):** append/update `tasks/checkpoint.md` with: timestamp, current
  git branch + `git status --short`, in-progress (`[~]`) and pending (`[ ]`) items
  from `tasks/todo.md`, and the active spec path if discoverable. Failure-only
  observability: silent on success (exit 0), never blocks compaction.
- **Restore (SessionStart, source=compact):** print a compact "RESUMING AFTER
  COMPACTION" block that points at `tasks/checkpoint.md`, the active `[~]` task, and
  `tasks/memory.md` — skipping the heavy skills banner / drift check that only matter
  on a true `startup`.

### P2 — Task-boundary checkpointing in /build
`/build` writes a checkpoint at each **semantic boundary** (after a task flips to
`[x]`), so the working state on disk is always current and a compaction or reset loses
at most one task of context. This is the primary, model-aligned mechanism ("compaction
is a decision, not a threshold"); the P1 hook + native auto-compact are the backstop.

- After Step 3 (Mark Complete) of each task, update `tasks/checkpoint.md` (reuse the
  P1 flush routine; do not duplicate logic).
- No user prompt, no commit — silent state write only.

### P3 — /refresh context-reset skill
A new `/refresh` skill formalizes Anthropic's full-context-reset pattern: snapshot to
`tasks/checkpoint.md`, then hand off a minimal resume instruction so a fresh context
rebuilds cleanly from disk (checkpoint + memory + todo). `/build`'s architectural
circuit breaker auto-invokes `/refresh` before escalating; otherwise it is run
manually. Framed as a **backstop** (modern models rarely need it).

### P4 — Continuous memory decay (Reflector-lite) in /memory-maintain
Split `/memory-maintain` cadence: the cheap `tasks/lessons.md` dedup+decay pass runs
**every session**; the heavy archive/promote pass keeps its every-5-sessions gate.
Mirrors Mastra's Observer (compress) / Reflector (merge duplicates, drop low-priority)
split without adding infrastructure.

### P5 — Generalized large-artifact truncation convention
Promote the one-off "truncate logs to last 500 lines" rule from `verify-deployment`
into a shared, named convention in `AGENTS.md` ("Large-Artifact Handoff"),
and reference it from `/build` sub-agent delegation. Any large artifact handed to a
sub-agent is truncated-with-pointer: last-N lines + full copy persisted to a path.

---

## Inputs
- **P1:** PreCompact hook JSON on stdin (`trigger`); SessionStart hook JSON (`source`).
- **P2:** `tasks/todo.md` task-completion transitions during a `/build` run.
- **P3:** Manual `/refresh` invocation, or `/build` circuit-breaker trip.
- **P4:** `tasks/lessons.md` (may be absent), `tasks/memory.md` session count.
- **P5:** Sub-agent delegation prompts in `/build`; build/deploy logs.

## Outputs
- **P1:** `.agents/hooks/pre-compact.sh`; `PreCompact` entry in the plugin's `hooks/hooks.json`;
  `source=compact` branch in `session-start.sh`; updated `tasks/checkpoint.md` on compact.
- **P2:** checkpoint write after each completed `/build` task (edit to `build/SKILL.md` ×2).
- **P3:** `refresh/SKILL.md` in both skill locations; circuit-breaker edit in `build/SKILL.md` ×2; `/refresh` row in the `README.md` skills table.
- **P4:** revised `memory-maintain/SKILL.md` ×2 (per-session lessons pass + gated heavy pass).
- **P5:** "Large-Artifact Handoff" section in `AGENTS.md`; references in `build/SKILL.md` ×2; `verify-deployment` points at the shared convention.
- **All:** `tests/` harness + passing test scripts.

## Edge Cases
- `jq` unavailable → hooks fall back (raw-stdin / skip source-detection), still exit 0.
- `tasks/checkpoint.md` missing → create it; never error.
- `tasks/todo.md` missing/empty during PreCompact → flush git state only, no crash.
- `tasks/lessons.md` absent (current repo state) → P4 lessons pass is a silent no-op.
- PreCompact must **never** block or delay compaction — any internal error exits 0.
- SessionStart `source` field missing (older CLI) → default to `startup` (full banner) — no behavior regression.
- New skill must not collide with `.claude/commands/` legacy basenames (none named `refresh` today; verify).
- Bug to fix in scope: `checkpoint/SKILL.md` "How to Resume" references `.claude/memory.md` (stale) — correct to `tasks/memory.md`; same stale path in `build/SKILL.md` Pre-Flight step 3.

## Acceptance Criteria
- [ ] P1: `pre-compact.sh`, given mock PreCompact stdin, writes a `tasks/checkpoint.md` containing the timestamp, git branch, and current `[~]`/`[ ]` todo items; exits 0.
- [ ] P1: `pre-compact.sh` exits 0 and writes git-only state when `tasks/todo.md` is absent (no crash).
- [ ] P1: the plugin's `hooks/hooks.json` is valid JSON and registers the `PreCompact` hook → `bash "${CLAUDE_PLUGIN_ROOT}/.agents/hooks/pre-compact.sh"`.
- [ ] P1: `session-start.sh` with `source=compact` on stdin prints the "RESUMING AFTER COMPACTION" block and skips the banner; with `source=startup` (or absent) it prints the banner.
- [ ] P2: `build/SKILL.md` (both locations) instructs a silent checkpoint write after each task is marked `[x]`, reusing the P1 flush routine.
- [ ] P3: `/refresh` skill exists in both locations with snapshot → handoff steps; `/build` circuit breaker auto-invokes `/refresh` before escalating; `/refresh` appears in the `README.md` skills table.
- [ ] P4: `memory-maintain/SKILL.md` (both locations) runs the lessons dedup/decay pass every session and gates the heavy archive/promote pass at every-5; a no-lessons-file run is a silent no-op.
- [ ] P5: `AGENTS.md` has a "Large-Artifact Handoff" convention; `build/SKILL.md` and `verify-deployment/SKILL.md` reference it instead of restating the 500-line rule ad hoc.
- [ ] Stale `.claude/memory.md` references in `checkpoint/SKILL.md` and `build/SKILL.md` corrected to `tasks/memory.md`.
- [ ] `tests/` harness runs all test scripts with a single command and reports pass/fail; every new hook has a test; suite is green.
- [ ] `.agents/skills/` and `.claude/skills/` copies of every touched/new skill are in sync.

## Files Likely Involved
- `.agents/hooks/pre-compact.sh` — NEW (P1 flush).
- `.agents/hooks/session-start.sh` — `source=compact` restore branch (P1).
- `hooks/hooks.json` — register `PreCompact` (P1).
- `.agents/skills/build/SKILL.md` + `.claude/skills/build/SKILL.md` — task-boundary checkpoint (P2), circuit-breaker /refresh (P3), large-artifact ref (P5), stale-path fix.
- `.agents/skills/refresh/SKILL.md` + `.claude/skills/refresh/SKILL.md` — NEW (P3).
- `.agents/skills/memory-maintain/SKILL.md` + `.claude/skills/memory-maintain/SKILL.md` — per-session lessons pass (P4).
- `.agents/skills/checkpoint/SKILL.md` + `.claude/skills/checkpoint/SKILL.md` — stale-path fix; shared flush format (P1/P2).
- `AGENTS.md` — Large-Artifact Handoff convention (P5).
- `.claude/skills/verify-deployment/SKILL.md` — point at shared convention (P5).
- `CLAUDE.md` — add `/refresh` to skills index (P3). NOTE: template-managed; edit is intentional template content.
- `tests/` — NEW zero-dep bash harness + test scripts.
