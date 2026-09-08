# Pi Project-Specific Rules

> **Pi harness only.** Claude Code uses `.claude/project.md` for project-specific rules.
> `CLAUDE.md` (shared rules, workflow, principles) is loaded automatically by both harnesses — this file adds on top of it.
> Safe to edit — `/sync` never touches this file.

---

## Project-Specific Rules

> Add project-specific rules for Pi here.
> Examples: tech-stack conventions, architectural constraints, domain glossary, service URLs.

### Task Tracking

Task tracking instructions: docs/task-tracking.md

The Claude Code copy of this declaration is in `.claude/project.md`. Both harnesses
need their own, because neither reads the other's project file — and the pointer
cannot live in `CLAUDE.md`, which `/sync` overwrites wholesale with a template that
cannot ship a `docs/` target (#82).

### Code Economy

A **generation-time** gate that runs *before* you write code — the preventive
counterpart to the post-hoc `/quality-gate` passes.
Apply to every code-writing turn. The cheapest line to review is the one never written.

**Decision hierarchy** — walk top to bottom; stop at the first that applies:

1. **Necessity (YAGNI)** — does this need to exist at all? Skip speculative
   abstractions, config knobs with one setting, and features no AC asks for.
2. **Existing code** — does a helper, util, type, or pattern already in this repo
   do it? Reuse it. Re-implementing what lives a few files over is the most common
   source of slop.
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
picking a level. The smallest change in the wrong place is a second bug.

**Root cause over symptom** — check every caller of the function you touch. One
guard in the shared function is a smaller diff than one per caller, and patching
only the path the ticket names leaves sibling callers broken.

**Tiebreak on correctness** — two options, same line count? Take the one that
handles edge cases. Economy means less code, not a flimsier algorithm.

**Never-on-the-chopping-block** (these override the hierarchy — economy never
justifies cutting them; see `CLAUDE.md` § *No Silent Failures*): security,
accessibility, trust-boundary input validation, error handling that prevents
data loss, and anything the user explicitly requested.

**Intentional shortcuts** — when you deliberately pick a minimal solution with a
known limitation, mark it with a `TODO(shortcut):` comment stating the limit and
the upgrade path. `/quality-gate` Phase 2 preserves `TODO/FIXME`, so the marker
survives cleanup.

### Code Graph

Explore via the per-project code graph before broad grep/read sweeps:
`graphify query "<question>"` (also `explain`, `path`; graph at `graphify-out/graph.json`).
Optional — fall back to normal search when it is absent. See `CLAUDE.md` § *Code Graph First*.
