# Project-Specific Configuration

> **Claude Code only.** Imported by `CLAUDE.md` via `@` syntax. Safe to edit — `/sync` never touches this file.
> Pi equivalent: `AGENTS.md` at the project root.
>
> This is where team-shared, project-specific rules, deployment targets, and
> conventions live. `CLAUDE.md` is template-managed and overwritten by `/sync`,
> so anything project-specific goes here instead.
>
> For personal, un-shared overrides (your own shortcuts, local paths,
> experiments), use `CLAUDE.local.md` instead — it's gitignored.

---

## Deployment Targets (placeholder — run /setup-deployment to populate)

> ⚠ **THIS TEMPLATE REPO HAS NO ACTIVE DEPLOYMENT TARGETS.** The heading above
> is intentionally **not** the literal `## Deployment Targets` so that
> `/verify-deployment` and `session-start.sh` treat this repo as having no
> Deployment Targets and skip silently.
>
> Downstream projects run `/setup-deployment`, which replaces this placeholder
> with a real `## Deployment Targets` section (matched by the exact-match regex
> `^## Deployment Targets[[:space:]]*$`).
>
> For the routing-table schema (columns, config block, worked example), see
> `.claude/deployments/README.md` § Routing Table Schema.

A real configured project would have a section like this (indented code block
shown below — not active in this template):

        ## Deployment Targets

        > Populated by /setup-deployment. Read by /verify-deployment.
        > Delete this section to disable deployment verification for this project.

        | Service | Runbook                          | Triggers on branch | Project ID    |
        |---------|----------------------------------|--------------------|---------------|
        | Railway | .claude/deployments/railway.md   | main               | my-api-prod   |
        | Vercel  | .claude/deployments/vercel.md    | main               | acme/marketing |

        **Config:**
        - Max fix iterations: 3
        - Build timeout: 15m
        - Preferred status source: github-checks

---

## Project-Specific Rules

> Add any team-shared rules that should apply only to this project.
> Examples: tech-stack conventions, architectural constraints, domain glossary,
> external service credentials policy.

### Task Tracking

Task tracking instructions: docs/task-tracking.md

The declaration lives here rather than in `CLAUDE.md` on purpose. `CLAUDE.md` is
template-managed and `/sync` overwrites it wholesale, while `docs/` is outside
every syncable root — so a pointer there would ship to every downstream project
naming a file the template can never deliver, which the loader now refuses
outright (#82). `.claude/project.md` is never synced, so the pointer and its
target stay together. Pi reads the same line from `AGENTS.md`.

### Code Economy

A **generation-time** gate that runs *before* you write code — the preventive
counterpart to the post-hoc `/quality-gate` passes.
Apply to every code-writing turn (main thread and sub-agents). The cheapest line
to review is the one never written.

**Decision hierarchy** — walk top to bottom; stop at the first that applies:

1. **Necessity (YAGNI)** — does this need to exist at all? Skip speculative
   abstractions, config knobs with one setting, and features no AC asks for.
2. **Existing code** — does a helper, util, type, or pattern already in this repo
   do it? Reuse it. Re-implementing what lives a few files over is the most common
   source of slop; `/quality-gate` Phase 1.1 catches it after the fact, this rung
   prevents it.
3. **Standard library** — does the language's stdlib already provide it? Prefer
   it over a hand-rolled equivalent.
4. **Native platform** — does the OS/browser/runtime provide it? (e.g.
   `<input type="date">` over a date-picker dependency.)
5. **Existing dependency** — is it already installed? Reuse it before adding a
   new one. **Do not add a dependency for what 1–4 already cover.**
6. **One line** — if a correct one-liner exists, write the one-liner.
7. **Minimal viable code** — only then write the least code that satisfies the AC.

**Understand first, then walk the hierarchy** — it shortens the solution, never
the reading. Trace the real flow through every file the change touches before
picking a level. The smallest change in the wrong place is not economy, it is a
second bug.

**Root cause over symptom** — a bug report names a symptom. Before editing, check
every caller of the function you are about to touch: one guard in the shared
function is a smaller diff than one guard per caller, and patching only the path
the ticket names leaves sibling callers broken. The economical fix *is* the
root-cause fix.

**Tiebreak on correctness** — when two options cost the same number of lines, take
the one that handles edge cases. Economy means less code, not a flimsier algorithm.

**Never-on-the-chopping-block** (these override the hierarchy — economy never
justifies cutting them; see `CLAUDE.md` § *No Silent Failures* and `/security-scan`):
security, accessibility, trust-boundary input validation, error handling that
prevents data loss, and anything the user explicitly requested.

**Intentional shortcuts** — when you deliberately pick a minimal solution with a
known limitation, mark it with a `TODO(shortcut):` comment stating the limit and
the upgrade path. `/quality-gate` Phase 2 preserves `TODO/FIXME`, so the marker
survives cleanup.

### Surgical Changes

Tightens `CLAUDE.md` § *Minimal Impact* with three operational tests. Apply to every
code-modifying turn (main thread and sub-agents).

1. **Trace test** — every changed line must trace directly to the current task or
   user request. If you cannot point to the sentence in the spec / todo / user
   message that motivates a hunk, revert it.
2. **Style match** — match the surrounding file's existing style (naming,
   formatting, error handling, comment density) even if you would write it
   differently in a greenfield. Style drift is a separate PR.
3. **Orphan rule** — remove only the imports, variables, and functions that
   *your* changes made unused. Do not delete pre-existing dead code; if you
   notice it, mention it in the turn summary and move on.

These rules do **not** override explicit refactor or cleanup tasks. They apply
when the task is a feature, fix, or targeted change.

### Ambiguity Protocol

When a sub-agent (or the main thread during `/build`) encounters **genuine
semantic ambiguity** — not a stylistic choice, not a missing import, but a
question whose answer changes the implementation — it must surface the
question rather than silently picking.

**Emission format** (single line, parseable by the orchestrator):

```
[AMBIGUITY] <one-sentence description> | options: A) <option> B) <option> [C) ...] | picked: <letter> | reason: <one sentence>
```

Rules:
- The agent **picks one option and proceeds** (don't block on a question).
- The orchestrator collects every `[AMBIGUITY]` line emitted during the run
  and surfaces them as a single batch to the user at the end of `/build`,
  before `/quality-gate` runs.
- Use sparingly. Stylistic preferences, naming bikesheds, and questions
  answered by reading one more file do **not** qualify. Examples that do:
  - "Spec says 'export users' — entire table or only active users?"
  - "Validation failure: throw vs. return `Result<Err>`? Codebase has both."
  - "AC mentions retry — exponential backoff or fixed interval?"

If unsure whether something qualifies, default to **not** emitting and noting
the assumption in the turn summary instead.


### Large-Artifact Handoff

When handing a large artifact (build/deploy logs, command output, generated
files, long diffs) to a sub-agent or the next context, **truncate with a
pointer** instead of inlining the whole thing:

1. Persist the full artifact to a file (e.g. `tasks/<name>-<sha>.log`, gitignored
   if transient).
2. Pass only the **last N lines** (default 500) plus the file path in the prompt.
3. State the truncation explicitly so the reader knows more exists on disk.

This is the prevention-side counterpart to context compaction: bound what enters
a context window at the source rather than compressing it after the fact. Skills
that move bulk text (`/verify-deployment`, `/build` delegation) reference this
convention rather than restating an ad-hoc line limit.
