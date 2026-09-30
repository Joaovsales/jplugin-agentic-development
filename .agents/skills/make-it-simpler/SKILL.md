---
name: make-it-simpler
description: "One behavior-preserving simplification a day, sized to one review and shipped as a pull request. Ranks the tree with scripts/signals.py (a rule stated in many files, citations that no longer resolve, always-loaded prose over budget, docs contradicting their scripts, prose a test already enforces, orphaned references, oversized scripts), deep-reviews the top candidates, classifies each minor or significant, then grills the operator on one pick (interactive) or files and builds within a three-slice cap (--unattended, the simplify routine). Use when a skill, doc or script has grown bulky, one rule lives in several files, or the harness wants its daily trim. Triggers on: 'make it simpler', 'simplify this', 'one home per rule', 'this is too long', 'trim'."
argument-hint: "[#N | registry id | <path> | <focus text>] [--unattended | --prepare]"
disable-model-invocation: false
harness: universal
---

# /make-it-simpler — One simplification a day

## Overview

Finds the harness-shaped bulk ordinary review misses — one rule in many files,
dead citations, always-loaded prose over budget — and turns one piece of it into
a behavior-preserving pull request. Discovery is cheap signals first
(`scripts/signals.py`, defined in `references/lens.md`), then a deep review of
the top few. Every spec it writes carries the five practices of
`references/safe-moves.md`. It never replaces `/tidy` (rot) or
`/sweep --routine architect` (design debt, whose open `tech-debt` tasks are an
input here), and it never builds a *significant* change.

## The Process

### Read the argument

First match wins:

| `<arg>` | Mode |
|---|---|
| `#N` or a registry id | that task. On a `routine/simplify/` branch it is unattended lane step 1; anywhere else it is interactive and grilled — `.agents/skills/wrap-up-session/references/routines.md` § *Unattended detection* decides |
| a tracked path prefix | interactive, candidates narrowed to it (`rank --path`) |
| any other text | interactive; the text is the focus the top 3 are chosen against (how `/go` passes a goal) |
| nothing | interactive over the whole tree |

`--unattended` is the scheduled entry (§ *Unattended*); `--prepare` runs its
steps a–b only, interactively, and the operator commits the index rows.

### Rank, review, classify, size

```bash
python3 .agents/skills/make-it-simpler/scripts/signals.py rank [--path <p>]...
```

A non-zero exit stops the run loudly before anything is filed. Deep-review the
top candidates: read each file, confirm or drop every **cue** (`lens.md`), and
estimate the lines saved and the callers touched.

- **Significant** when the change meets the bar in `/system-design-planning` § *When to Use / When Not*; otherwise **minor**. The bar is cited, never restated.
- **Size** against `.agents/skills/slice/references/sizing.md`. An unattended build is at most 3 slices and one area — one skill with its `references/`, or one script with its tests.

### Offer the top 3

Each candidate shown carries its signal, a `file:line` evidence quote, the
estimated lines saved, the callers touched, and minor/significant. The operator
picks one or declines: **none today writes nothing** — no task, no spec, no branch.

A pick is filed and claimed (§ *Unattended* step b's commands, then
`task-registry claim <ref> --apply --approve`). A significant pick is handed to
`/plan`, or to `/system-design-planning` when it crosses its bar, and this skill
stops. A minor pick goes to `/grilling` with four seeds, then the frontier:

1. Scope — what is in and what is out.
2. What stays byte-identical (outputs, exit codes, headings callers cite).
3. The minor behavior changes expected, or `none`.
4. The slice cap for this change.

### Write the spec and run the lane

Write `specs/simplify-<slug>.md`, the path derived from the task's slug; an
existing spec for it is reopened, not duplicated. The registry write always
precedes the spec write. Its § Decisions seeds the five `safe-moves.md`
practices as rows, in every spec this skill writes, beside the grilled answers.

Before the first edit, record the **before-proof**: the affected-test command
plus `bash tests/test-citations.sh`, command and result. Then run lane steps
2–5 (`task-registry lanes simplify`); lane step 5 is the one home of what the PR
body carries. `Simplified:` lists lines before→after per file and the
always-loaded delta.

### Unattended

a. Rank, deep review, classify and size (§ *Rank, review, classify, size*) over the whole tree.
b. File. For each confirmed candidate run `task-registry show <derived-id>` first and skip a `done` or `cancelled` id — `upsert` would reopen it. Then:
   ```bash
   python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
     --derive-id simplify --source <path> --fold-title --title '<signal> in <path>' \
     --kind task --label simplify --evidence '<file:line> — <quote>' --criterion '<checkable>' --apply
   ```
   Minor and within the cap files `--kind task`; significant or over the cap files `--kind decision` (its `design-decision` label hands it to the `plan` routine). Only the `simplify` label is ever passed.
c. Spine 1–3 (`.agents/skills/wrap-up-session/references/routines.md` § *The shared spine*): `select --routine simplify`, `claim`, branch `routine/simplify/<n>-<slug>`. The `tasks/todo.md` index rows step b wrote are the branch's first commit.
d. Lane step 1 is `/make-it-simpler <ref>`: § *Scope stop*, then § *Write the spec and run the lane*, ending in a ready PR.

The run has three ends, and the clone is clean after each (`git status --porcelain` empty):

- **Ready PR** — a task was selected and built.
- **Record PR** — decisions were filed but nothing was selected: a docs-only PR of the index rows on `routine/simplify/<YYYYMMDD>-record`, `Refs #N` per filed issue.
- **Silent exit 0** — nothing filed and nothing selected: no output, no branch.

An unreachable tracker prints the registry's `local-pending` lines and opens no branch.

### Scope stop

At lane step 1, before any edit, re-check the claimed task at `HEAD`. When it is
significant, over the cap, or no longer reproduces: exit non-zero, open no PR,
leave the claim in place, and print one line naming the task, the reason and
the remedy — `scope stop: #N — <reason> — relabel design-decision, or close it`.

### Overrides

This skill is the third named exception to the fresh-session rule in
`AGENTS.md` § *Workflow: PRD → Plan → Build → Wrap Up* — a planning session
never builds. Like `/yolo` Phase A, it owns these overrides, and only these:

| Step | Override |
|---|---|
| `/plan` Step 1 — Interview | the spec this skill wrote carries § Decisions; `/plan` prints `DECISIONS CARRIED` and asks nothing unattended. An interactive run was already grilled |
| `/plan` Step 6 — Hand over | no build prompt is printed; `/build` runs in place, in this session |
| `/build` pre-flight — filing | no `/slice --file`: the `simplify` task is the tracked unit, the slices stay plan-block rows, and slice headers are not claimed |

## Integration

- **Called by**: the `simplify` routine (lane step 1), `/go` (the `simplify` lane), the operator.
- **Calls**: `scripts/signals.py`, `/task-registry`, `/grilling`, `/plan`, `/build`, `/quality-gate`, `/wrap-up-session`.
- **Pairs with**: `/tidy` — the lens excludes its nine checks; `/sweep --routine architect` — its `tech-debt` tasks are candidates too.

## Key Principles

- One simplification, one review, one pull request.
- Behavior-preserving by proof: the same commands before and after; every minor change declared.
- A significant change is never built unattended.
- The registry first, the spec second — a crash between resumes, never duplicates.
