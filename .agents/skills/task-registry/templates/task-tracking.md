# Task tracking

> Copy this file to `docs/task-tracking.md` in your project and edit the block
> below. Discovery finds it there automatically; to keep it elsewhere, add a line
> `Task tracking instructions: <path>` to `.claude/project.md` (Claude Code) or
> `AGENTS.md` (Pi) — never to `CLAUDE.md`, which `/sync` overwrites.
>
> Read by `/task-registry`. Everything is optional — without configuration,
> selection still prefers GitHub when a GitHub remote and an authenticated `gh`
> both exist, then falls back to local Markdown.

```ini
[tracker]
; github | local. Omit the key entirely to auto-select:
; GitHub when a GitHub remote and an authenticated `gh` both exist, else local.
; No tracker is ever selected implicitly beyond those two.
provider = github

; GitHub: owner/name. Omitted means "ask gh for the current repo".
repository = my-org/my-repo

; Paths. Defaults shown.
index = tasks/todo.md
backlog = tasks/backlog.md
spec_dir = specs
local_detail_dir = tasks/details

; native | metadata | auto. `auto` uses the provider's native links when it has
; them and falls back to task metadata when it does not, reporting which.
dependency_strategy = auto

; true  — `--apply` alone is not enough; external writes also need `--approve`
; false — `--apply` is sufficient, but ONLY when the operator also exports
;         TASK_REGISTRY_TRUSTED_CONFIG=1. This is a floor: a file in the
;         repository may raise the requirement and can never lower it alone.
require_write_approval = true

; Ordinary sync NEVER creates a label. Set true only if you want the registry to
; add missing mapped labels to the tracker's vocabulary.
allow_label_creation = false

; degrade — an unreachable provider still reconciles the local half (default)
; fail    — any unreachable provider fails the run
offline_reads = degrade

; Free text, shown in the migration report. Describes how this project wants
; legacy plans handled: manual | grouped | per-spec | none.
migration_policy = manual

; The heading that marks a plan block finished, so its still-open rows are
; classified `stale` rather than `active` during migration. Defaults to this
; harness's own convention.
closed_plan_marker = Session Summary

; ---------------------------------------------------------------------------
; Label -> kind. Provider vocabulary on the left, canonical kind on the right.
; This is a READING of the project's labels. It never renames or replaces one.
; Canonical kinds: epic, feature, bug, decision, research, operational, task.
[labels.kind]
bug = bug
enhancement = feature
design-decision = decision
; Do NOT map a label to `task` here. This section is read in BOTH directions:
; the GitHub provider reverse-looks-up kind -> first matching label to decide
; what to stamp on an issue it publishes, and `task` is the default kind. A
; `tech-debt = task` entry therefore labels every published task `tech-debt`.
; The routine precedence chain does not need these entries -- selection reads
; [routines.selectors] below, never this map.
; `question` is ambiguous between decision and research, so it maps only if you
; say which one you mean:
; question = research

; Queue label -> priority. A row with no queue label has priority unset — which
; is a distinct state from "low".
[labels.priority]
now = high
next = medium

; ---------------------------------------------------------------------------
; Scheduled routines. A routine selects issues by ONE label axis, runs a named
; step list, and ends at a pull request a human reviews. See
; .agents/skills/wrap-up-session/references/routines.md for the full contract.
[routines]
; Written before a routine creates its branch; an issue already carrying it is
; skipped as in-flight. Disjoint selectors stop two DIFFERENT routines claiming
; one issue — only this stops two runs of the SAME routine overlapping.
claim_label = in-progress

; First match wins, so an issue with two kind labels resolves deterministically.
; These are provider LABEL names (the left-hand keys of [labels.kind] above),
; not canonical kinds. Every label ranked here must be selected by exactly one
; routine below, and every label a routine selects must be ranked here — the two
; sets are checked against each other and a mismatch is refused.
kind_precedence = bug, design-decision, tech-debt, enhancement, documentation

; Routine -> the labels it selects. Declared entries REPLACE this default rather
; than layering over it, so renaming your vocabulary does not leave the English
; defaults behind as a shadow selector set.
;
; `now`/`next` are deliberately absent: priority orders candidates WITHIN a
; routine's pool and never selects a routine. Selecting on both axes gave two
; routines a claim on the same issue in a third of all cases.
;
; `build` is also absent — it is deferred, and a selector for a routine nobody
; runs would let a deferred capability fail a live check.
[routines.selectors]
plan = design-decision
fix = bug, tech-debt
improve = enhancement, documentation

; Routine -> the ordered skills it runs, once selection has told it WHICH issue.
; Like [routines.selectors] and unlike [labels.kind], declared entries REPLACE
; the shipped map wholesale rather than merging per key: a project that reorders
; one chain and silently inherits three others cannot see, in its own file, which
; chains it actually chose. So if you declare this section, declare a chain for
; every routine you select with — a routine left with a selector and no chain is
; refused, naming it.
;
; Three rules, all checked at load rather than at step 4 with the claim label
; already written:
;   * every skill named must exist in .agents/skills/ or .claude/skills/
;   * every chain must END at /wrap-up-session — it is the review gate, and a
;     chain that runs it anywhere but last can still ship work after it
;   * the routine names are the contract's four; inventing one is a deliberate
;     edit to CONTRACT_ROUTINES, not a configuration key
;
; Defaults shown, transcribed from the routine contract at
; .agents/skills/wrap-up-session/references/routines.md. `plan` omits /build
; and /quality-gate on purpose: it produces a spec and no implementation, so
; requiring them would write a `skip:` row on every single run.
[routines.skills]
plan = /plan, /wrap-up-session
fix = /debug, /build, /quality-gate, /wrap-up-session
improve = /plan, /build, /quality-gate, /wrap-up-session
build = /build, /quality-gate, /wrap-up-session

; ---------------------------------------------------------------------------
; Where `in_progress` and `blocked` come from. They are NEVER inferred from
; GitHub's open/closed state, because GitHub does not have them. Supported
; sources: `label:<name>` and `assignee`.
; A `field:<name>` source names a GitHub Projects field this adapter cannot read
; through gh; it is reported as a limitation rather than silently ignored.
[status]
; in_progress = label:in-progress
; blocked = label:blocked

```

## Credentials

Never in this file, and no shipped provider needs one here. GitHub uses whatever
`gh auth status` reports; the local Markdown store has no credential at all. A
tracker added later reads its own from the environment, never from this file.

## Naming conventions

Adapt these examples to the repository's existing issue corpus:

- Title: `<PLAN-ID>: <lowercase deliverable phrase>`; use a work-type prefix
  such as `E2E:` or `Unit tests:` when verification is the deliverable, and a
  plain sentence when there is no parent plan.
- Never publish raw plan text. The `->` implementation clause belongs in the
  issue body, not its title.
- Labels: choose exactly one `area/*`, one priority tier, and one kind when the
  repository maps those vocabularies. Keep verification-work labels consistent
  with the repository's established convention.
