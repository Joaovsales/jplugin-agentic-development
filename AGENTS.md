# jplugin-agentic-development — Agent Instructions

<!-- jplugin-agentic-development:begin -->
## Session Start Checklist

1. Note the learning-store counts in the session banner. When a task touches a known area, grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) — never bulk-load the store. Consult `tasks/concepts.md` for project terms you do not recognise and use its vocabulary when naming things.
2. Check `tasks/todo.md` for in-progress work.
3. Run `/memory-maintain` — it self-gates and only does work every 5 sessions or when overdue.

## Workflow: PRD → Plan → Build → Wrap Up

Interactive work starts with `/go <goal>`: it picks one lane from the shared lane catalogue (`task-registry lanes`), prints a `[ROUTE]` line, and runs the steps below through the skills that own them.

1. **PRD** (greenfield only) — `/prd` writes `specs/prd-<name>.md`, `tasks/backlog.md`, `tasks/project-context.md`.
2. **Specify** — every non-trivial feature gets `specs/<feature>.md` (Behavior / Inputs / Outputs / Edge Cases / Decisions / Acceptance Criteria / Implementation Paths) through `/plan`, or `/system-design-planning` when the change crosses a component boundary, changes a persisted data model, or changes an external contract — its `/grilling` interview is mandatory at that bar, minus what is already settled. Optional precursors `/grill-me` (a stateless interview, nothing written) and `/brainstorm` (divergent exploration; its spec carries § Decisions) settle decisions that carry forward: `/plan` prints `DECISIONS CARRIED: <n> from <spec path | conversation>` and asks only the `open` rows and the gaps.
3. **Slice (hard gate)** — the planner invokes `/slice`, which sizes the spec into session-sized slices, writes § Build Order and the `## Plan:` block in `tasks/todo.md` (`[ ] TDD: [Test Name] -> [Impl Detail]` rows under `### Slice n/N` headings) and prints the build prompt. The planning session ends with `Spec and plan are ready to be built. Start a fresh session with this prompt:` — it never builds and never files. Change requests are applied in place: edit the spec, re-run `/slice`. `/auto-push` (behind its own `y`) and `/yolo` (unattended) are the two named exceptions that build in the planning session.
4. **Build (fresh session)** — `/build` runs the plan autonomously in the session the build prompt starts. Pre-flight files the slices through `/slice … --file --approve` — the build prompt is the authorization the planning session did not have; `slice.py ready` names the slices whose blockers are done, and disjoint ready slices dispatch in parallel, each agent editing only its slice's Surface. Each task: failing test → minimal implementation → refactor → `[x]`. Every slice closes with the affected-test command, a surface check and a `> Handover:` blockquote under its heading — what landed, what the next slice must not re-derive. `/quality-gate` on the changed files when the tasks are done; every acceptance criterion validated; no prompts between tasks. The full suite runs twice a session — `/build`'s baseline and `/wrap-up-session` Step 6 — both through `.agents/skills/build/scripts/cached-suite.sh`, which reuses a green run of the same command on the same working tree and allows one suite at a time; every other checkpoint runs the affected-test command. A project declares both below the end marker as `Full suite: <command>` and `Affected tests: <command with {base}>`; with neither, the skills use the runner they discover and the test files covering the changed paths.
5. **Wrap up** — after a correction, capture the root cause in `tasks/solutions/` (`/debug` or `/learn`); at session end run `/wrap-up-session` to sync learnings, run tests, and push.

## Review Gate Taxonomy

```
Layer 1 — Per-task in /build       spec compliance check (inline) + tests pass
Layer 2 — Post-build quality-gate  structural quality · AI anti-patterns · APOSD design
Layer 3 — Pre-push in /wrap-up     quality receipt check (re-enter the gate on a stale diff), full suite, closure loop
```

Every finding any layer emits carries the four axes of the *Finding Model* — `severity`, `confidence`, `autofix_class`, `owner` — and is auto-applied only when `gated_auto` at `confidence >= 75`; the emission format, anchors, gates and Independence Accounting are `.agents/references/finding-model.md`. Every reviewer dispatch carries the seven items of `.agents/references/review-dispatch-contract.md` § *The seven items*, stating `deferrals: none` and `no spec — <reason>` when an item is empty, and shares intent while withholding conclusions.

## Core Principles

**Never Guess — Verify.** Read before editing. Check that files exist. Validate from actual content.

**Code Graph First.** Prefer the per-project code graph (`graphify-out/graph.json`) over blind grep/read sweeps: `graphify query "<question>"` to explore, `graphify explain "<symbol>"` for one node, `graphify path "A" "B"` for how two things connect. Optional — a missing `graphify` or graph is not an error, fall back to normal search. A stale graph is worse than none: `graphify hook install` re-indexes on commit and checkout.

**Clean Code** — functions ≤20 LOC and ≤3 parameters, one abstraction level, meaningful names, DRY and KISS — is the standard `/quality-gate` Phase 1 checks.

**APOSD Design.** Hide information behind simple interfaces. Pull complexity downward — callers never learn internal state machines, lock types or schemas. Prefer deep modules over shallow ones. Prefer general-purpose over special-case when it costs no complexity. Define errors out of existence rather than handling them.

**SOLID** — single responsibility, open/closed via strategy or registry, Liskov, small interfaces, injected dependencies — is the standard `/quality-gate` Phase 1 checks.

**Observability Discipline.** Recurring jobs (cron, smoke tests, health checks) report failure only: success is silent (exit 0, no log line); failure is loud (structured error, actionable context, non-zero exit).

**Minimal Impact.** Touch only what the task needs. No unsolicited refactors, no proactive documentation.

**No Silent Failures.** Explicit errors only. No `except: pass`. No fallback values that hide a broken assumption.

**File & Git Hygiene.** Prefer editing existing files. Never skip git hooks. Atomic, descriptive commits.

## Quality Gate

Before marking any task complete, confirm:
- All relevant tests pass, and new code has ≥80% test coverage
- Every user-facing acceptance criterion has an e2e walkthrough in `tasks/e2e-log.md` (`/verify-evidence --scope e2e`)
- No linting or type errors
- Code passes the Clean Code and SOLID review, and introduces no security vulnerability

## Key Directories

```
.agents/skills/            → Canonical skills (harness-neutral)
.agents/agents/            → Sub-agent personas (canonical; .claude/agents/ = Claude Code copy)
.agents/references/        → Protocol references: finding model, review dispatch contract, model routing
.agents/hooks/             → Lifecycle hook scripts, run by the Claude Code plugin
specs/                     → Feature specifications
tasks/todo.md              → Active task index
tasks/backlog.md           → Ordered work items (from /prd)
tasks/project-context.md   → Compressed agent briefing (auto-generated)
tasks/solutions/           → Typed learning store: one doc per learning, grep-first retrieval (schema in its README.md)
tasks/history.md           → Session narrative log (what happened, not learnings)
tasks/concepts.md          → Concept glossary: project vocabulary (bootstrapped by /memory-maintain, accreted by /learn)
tasks/checkpoint.md        → Session snapshots
```

## Agents

One focused task per sub-agent. Canonical personas live in `.agents/agents/` and never pin a `model:`; `.claude/agents/` is the Claude Code copy and may pin built-in aliases. Which tier each agent runs on — Planner `opus`, Builder and Reviewer `sonnet`, Scout `haiku`, and *Ceiling* (`code-reviewer`, `security-reviewer`, `software-design-expert-review`, `critic` with a planner floor), which inherits the session model — is `.agents/references/model-routing.md`. On Claude Code pass `model` explicitly for the Planner, Builder, Reviewer and Scout tiers and pass **nothing** for Ceiling agents; on Pi never pass per-call model params, `subagents.agentOverrides` resolves them.

## Task Tracking

`tasks/todo.md` is an **index**, not the detailed source of truth: one row per task — status box, title, stable ID, provider link, one-line summary, optional dependency marker. Acceptance criteria, discussion and evidence live in the external ticket or the linked spec, read one task at a time through `/task-registry show <task-id>`.

The configuration contract is `docs/task-tracking.md`, or wherever a `Task tracking instructions: <path>` line below the end marker of this file points; start from `.agents/skills/task-registry/templates/task-tracking.md`. A pointer whose target is missing is refused, never read as "no configuration". Provider resolution — an explicit `provider =`, else GitHub when a GitHub remote and an authenticated `gh` both exist, else local Markdown — and the search order are `.agents/skills/task-registry/references/configuration.md` § *Discovery and selection*.

**No skill talks to a tracker directly.** `/plan`, `/build`, `/verify-evidence`, `/quality-gate` and `/wrap-up-session` reach the tracker only through `/task-registry`. External task creation and status changes require explicit authorization unless the project's configuration enables them.

## Code Economy

A generation-time gate that runs before you write code — the cheapest line to review is the one never written. Walk the hierarchy top to bottom and stop at the first rung that applies:

1. **Necessity (YAGNI)** — skip speculative abstractions, one-setting knobs, features no AC asks for.
2. **Existing code** — a helper, type or pattern already in this repo; re-implementing what lives a few files over is the commonest slop.
3. **Standard library** — before a hand-rolled equivalent.
4. **Native platform** — the OS, browser or runtime primitive (`<input type="date">` over a date-picker dependency).
5. **Existing dependency** — before adding a new one; never add a dependency for what 1–4 cover.
6. **One line** — if a correct one-liner exists, write it.
7. **Minimal viable code** — only then the least code that satisfies the AC.

Understand first: trace the real flow through every file the change touches before picking a rung — the smallest change in the wrong place is a second bug. Fix the root cause, not the symptom: check every caller of the function you touch, because one guard in the shared function beats one per caller. Tiebreak on correctness: at equal line count take the option that handles the edge cases. Never on the chopping block — security, accessibility, trust-boundary validation, error handling that prevents data loss, and anything the user explicitly asked for. Mark a deliberate minimal solution with a `TODO(shortcut):` comment naming the limit and the upgrade path; `/quality-gate` preserves the marker.

## Surgical Changes

Every code-modifying turn passes three tests. **Trace** — every changed line traces to the current task or request; revert a hunk you cannot point at a sentence for. **Style match** — follow the surrounding file's naming, formatting, error handling and comment density even where you would write it differently; style drift is a separate PR. **Orphan rule** — remove only the imports, variables and functions *your* change made unused; mention pre-existing dead code in the summary and move on. Explicit refactor or cleanup tasks are exempt.

## Ambiguity Protocol

When a sub-agent or `/build` hits **genuine semantic ambiguity** — a question whose answer changes the implementation, not a style choice or something one more file answers — it picks one option, proceeds, and emits a single parseable line:

```
[AMBIGUITY] <one-sentence description> | options: A) <option> B) <option> [C) ...] | picked: <letter> | reason: <one sentence>
```

`/build` collects every line and surfaces the batch to the user before `/quality-gate`. Use sparingly; when unsure whether a question qualifies, do not emit and note the assumption in the turn summary instead.

## Large-Artifact Handoff

Hand a large artifact (logs, command output, generated files, long diffs) to a sub-agent or the next context the same way every time: truncate with a pointer. Persist the full artifact to a file (`tasks/<name>-<sha>.log`, gitignored if transient), pass only the last 500 lines plus the path, and say the truncation happened. Bound what enters a context window at the source instead of compacting it afterwards.

## Skills

Skills are discovered from `.agents/skills/*/SKILL.md` frontmatter — the README skills table is the one human catalog. On Claude Code the skills are installed as the `jplugin` plugin, so a `/name` in this file is typed `/jplugin:name` and appears to the Skill tool as `jplugin:name`; Pi and Codex invoke `/name` directly.
<!-- jplugin-agentic-development:end -->

## Project-Specific Rules

> Team-shared rules for this repository. `/sync` replaces only the block above; everything
> below the end marker is yours. Personal overrides go in `CLAUDE.local.md` (Claude Code,
> gitignored) or `~/.pi/agent/AGENTS.md` (Pi).

### Task Tracking

Task tracking instructions: docs/task-tracking.md

### Test Commands

Full suite: bash tests/run.sh
Affected tests: bash tests/affected.sh --run {base}

### Code Graph

This shell-and-markdown repository has no code graph: `graphify` indexes code extensions
only, so do not install its hook here — it reports "nothing to rebuild" on every commit.

## Deployment Targets (placeholder — run /setup-deployment to populate)

> This template repository has no deployment targets. The heading above is deliberately
> **not** the literal `## Deployment Targets`, so `/verify-deployment` and the session
> banner skip this repository silently. Downstream projects run `/setup-deployment`,
> which writes a real `## Deployment Targets` section below the end marker (matched by
> `^## Deployment Targets[[:space:]]*$`); the routing-table schema is in
> `.claude/deployments/README.md` § Routing Table Schema.
