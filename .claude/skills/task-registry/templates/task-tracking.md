# Task tracking

> Copy this file to `docs/task-tracking.md` in your project and edit the block
> below. Discovery finds it there automatically; to keep it elsewhere, add a line
> `Task tracking instructions: <path>` to `AGENTS.md`, `CLAUDE.md`, or
> `.claude/project.md`.
>
> Read by `/task-registry`. Everything is optional — a project with no
> configuration at all gets the local Markdown provider and works offline.

```ini
[tracker]
; github | jira | local. Omit the key entirely to auto-select:
; GitHub when a GitHub remote and an authenticated `gh` both exist, else local.
; Jira is never selected implicitly.
provider = github

; GitHub: owner/name. Omitted means "ask gh for the current repo".
repository = my-org/my-repo

; Jira: the project key. May also come from JIRA_PROJECT.
; project = REG

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

; ---------------------------------------------------------------------------
; Where `in_progress` and `blocked` come from. They are NEVER inferred from
; GitHub's open/closed state, because GitHub does not have them. Supported
; sources: `label:<name>`, `assignee`, and (Jira) the native workflow state.
; A `field:<name>` source names a GitHub Projects field this adapter cannot read
; through gh; it is reported as a limitation rather than silently ignored.
[status]
; in_progress = label:in-progress
; blocked = label:blocked

; ---------------------------------------------------------------------------
; Jira vocabulary. Defaults shown; override only what your site differs on.
[jira.issuetype]
Bug = bug
Story = feature
Task = task
Sub-task = task
Epic = epic
Spike = research

[jira.priority]
Highest = high
High = high
Medium = medium
Low = low
Lowest = low
```

## Credentials

Never in this file. The Jira provider reads them from the environment:

```bash
export JIRA_BASE_URL=https://your-site.atlassian.net
export JIRA_EMAIL=you@example.com
export JIRA_API_TOKEN=...        # https://id.atlassian.com/manage/api-tokens
export JIRA_PROJECT=REG          # optional; `project =` above wins
```

GitHub uses whatever `gh auth status` reports. No token is read from this file.
