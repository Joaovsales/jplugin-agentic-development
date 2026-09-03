---
implementation_paths:
  - .agents/skills/wrap-up-session/**
  - .claude/skills/wrap-up-session/**
  - .agents/skills/task-registry/**
  - .claude/skills/task-registry/**
  - .agents/skills/plan/SKILL.md
  - .claude/skills/plan/SKILL.md
  - .agents/skills/brainstorm/SKILL.md
  - .claude/skills/brainstorm/SKILL.md
  - specs/README.md
  - CLAUDE.md
  - tests/test-living-spec-reconciliation.sh
---

# Spec: Living Spec Reconciliation During Wrap-Up

## Behavior

Feature specifications are living contracts that describe the repository's
current, tested behavior. Git history preserves earlier intent; a reader should
not need to reconcile historical amendments or stale implementation plans to
learn what the code does now.

`/wrap-up-session` automatically reconciles existing relevant specs with the
session's completed code before its final review, test, commit, and push gates.
The code is accepted as the new behavior when the repository's deterministic
tests and existing quality gates pass. A spec update is committed atomically
with the code change it documents.

Path matching only generates candidates. For every candidate, wrap-up compares
the spec's behavioral claims with the complete session diff and the current
implementation. It updates only specs whose described behavior actually
changed. A shared file may therefore select several specs, and more than one
spec may be updated in the same session.

Reconciliation may update:

- Behavior
- Inputs
- Outputs
- Edge Cases
- Acceptance Criteria
- Implementation Paths

These sections state current facts and invariants. Acceptance criteria use
ordinary bullets, not task-status checkboxes. Stale rationale, prospective
language, and implementation plans are removed when they contradict current
behavior.

## Spec Path Metadata

Maintained specs declare their current implementation surface in YAML
frontmatter:

```yaml
---
implementation_paths:
  - .agents/skills/wrap-up-session/**
  - tests/test-wrap-up-session.sh
---
```

Paths follow these rules:

- They are repository-relative POSIX paths or glob patterns.
- They never use absolute paths or `..` traversal.
- Matching is case-sensitive against the whole path. `*` matches zero or more
  characters except `/`, `?` matches one character except `/`, and `**` matches
  zero or more characters including `/`. No other glob syntax is accepted.
- They describe the complete current implementation surface, not only files
  changed when the spec was created.
- They may name source, configuration, tests, or other files whose changes can
  alter or verify the specified behavior.
- Paths may overlap between specs; the mapping is many-to-many.
- A spec also carries a human-readable `## Implementation Paths` section that
  explains each path's role. Frontmatter is the matching contract; the section
  is explanatory.

New specs created by the workflow use this format. Existing specs migrate
lazily when reconciliation determines that they are affected.

Every new `## Plan:` block records its spec on a machine-readable line:

```markdown
> Spec: specs/<feature-name>.md
```

This line associates completed task entries with the current session spec. A
plan with no such line continues through legacy path discovery; wrap-up never
guesses a current spec from a similar filename.

## Inputs

Reconciliation receives one immutable snapshot of the session change set before
it edits any spec:

- committed changes in `<base-branch>...HEAD`
- staged changes
- unstaged changes
- added, modified, renamed, copied, and deleted repository-relative paths
- the current session spec associated with completed `tasks/todo.md` entries,
  when one exists
- completed task entries and their stated intent
- the current contents of candidate specs and their referenced implementation
  paths
- the current implementation and deterministic tests needed to resolve the
  behavioral effect of the diff

Spec edits produced by reconciliation are excluded from candidate discovery so
the step cannot recursively select itself. They remain part of the downstream
security, review, test, commit, and push change set.

## Candidate Discovery

Candidate discovery is deterministic and ordered:

1. Include the current session spec named by the completed plan, regardless of
   whether it already has path metadata.
2. For specs with `implementation_paths`, match the original session change set
   against those paths. A rename checks both the old and new path; deletion
   checks the old path.
3. For legacy specs without metadata, parse repository-relative paths from
   `## Files Likely Involved` as a compatibility fallback and apply the same
   matching rules.
4. Deduplicate candidates while retaining every reason each spec matched.

An invalid metadata path is an explicit error naming the spec and value. It is
never ignored or treated as no match.

## Semantic Reconciliation

For each candidate, wrap-up reads the relevant diff, the full affected code
flow, its callers, and the deterministic tests before assigning one outcome:

- `updated` — observable behavior or the current implementation surface changed;
  rewrite the affected contract sections and refresh path metadata.
- `unchanged` — the path changed but the spec's behavior and implementation
  surface remain accurate; leave the file byte-identical.
- `deferred` — the behavioral effect cannot be determined from repository
  evidence; leave the spec unchanged, create or update durable reconciliation
  work, and continue wrap-up.

The comparison is semantic rather than keyword-based. Formatting-only changes,
internal refactors with no contract or implementation-surface change, and edits
to a shared file unrelated to the spec produce `unchanged`.

For `updated`, the agent traces the complete current feature flow rather than
copying only paths from the current diff. It then replaces stale metadata with
the smallest accurate set of paths or globs covering the current surface. This
repairs old mappings when files move or new implementation paths appear.

The updated prose describes behavior directly. It must not mention the session,
the diff, the fact that an update occurred, or superseded behavior. That history
belongs in Git.

## Legacy Migration

When a legacy spec is `updated`, reconciliation:

1. adds valid `implementation_paths` frontmatter;
2. replaces `## Files Likely Involved` with `## Implementation Paths`;
3. rewrites prospective descriptions into current factual descriptions;
4. converts Acceptance Criteria checkboxes into ordinary bullets; and
5. leaves unrelated accurate content intact.

An `unchanged` legacy candidate is not rewritten merely to migrate its format.
This keeps wrap-up changes behavior-focused and lets migration happen
incrementally.

## Outputs

Wrap-up emits a bounded reconciliation summary:

```text
Spec reconciliation: 5 candidates, 2 updated, 2 unchanged, 1 deferred
Candidates: specs/feature-a.md, specs/feature-b.md, specs/feature-c.md, specs/feature-d.md, specs/feature-e.md
Updated:    specs/feature-a.md, specs/feature-b.md
Unchanged:  specs/feature-d.md, specs/feature-e.md
Deferred:   spec-reconciliation.specs-feature-c-md (tasks/details/spec-reconciliation.specs-feature-c-md.md)
```

Every category that has members is listed by path, `unchanged` included. Naming
what was compared and found accurate is the only trace the cheapest outcome
leaves: a reviewer who cannot see which specs were examined cannot tell a
deliberate `unchanged` from a comparison that never happened. Bound each line at
20 paths, then a count.

No candidate specs is a successful outcome and remains one line. An
all-unchanged result is also successful, and still names the specs compared, so
the cheapest outcome leaves a trace a reviewer can check. A deferred result names the durable task and includes actionable
evidence without preventing the PR.

All updated specs are included with the code in subsequent review payloads.
Where review currently expects one spec and one Acceptance Criteria list, it is
generalized to accept every relevant spec and its criteria. The review boundary
continues to cover only issues introduced by the session.

## Deferred Reconciliation Work

Uncertain behavioral effect is documentation debt, not a wrap-up blocker. For
each deferred spec, wrap-up uses `/task-registry` to create or update one
provider-neutral `research` task before proceeding. Workflow code never calls
GitHub or Jira directly.

The stable task ID is derived from the complete repository-relative spec path:
`spec-reconciliation.<normalized-spec-path>`. This gives each spec at most one
active reconciliation task. A repeated unresolved change updates the same task
with new evidence; if its earlier task was completed, the new uncertainty
reopens it. Re-running wrap-up over the same change set is idempotent.

The task records:

- the spec path;
- every changed path that selected it;
- the behavior question repository evidence could not resolve;
- the evidence inspected and what was missing;
- the branch and commit range when available; and
- acceptance criteria to determine current behavior, update the living spec and
  its path metadata, and add or correct deterministic coverage when the gap came
  from missing tests.

A durable task record and compact `tasks/todo.md` index row must exist before
wrap-up continues. When an external provider is configured and its existing
write policy permits unattended publication, the external issue is the task
record and the index links it. When approval is required or the provider is
unreachable, wrap-up does not pause or fail: it writes a local Markdown task,
links that from the index and PR, and reports that external publication is
pending. This preserves `/task-registry`'s dry-run and authorization guarantees
without maintaining two canonical task bodies.

The PR description lists every deferred reconciliation task. Reviewers therefore
see that the affected spec was deliberately left unchanged rather than silently
missed.

## Error Handling

- **Malformed frontmatter or unsafe path** — stop reconciliation and name the
  exact spec and value.
- **Referenced path no longer exists** — do not fail solely for absence; use
  rename/deletion evidence and current code tracing to refresh the mapping.
- **Candidate behavior cannot be resolved** — classify it as `deferred`, leave
  the spec unchanged, persist the reconciliation task, and continue.
- **Local reconciliation task cannot be persisted** — stop wrap-up because the
  documentation debt would otherwise be lost.
- **External task publication needs approval or fails** — retain the local task,
  report the external state, and continue without weakening the provider's write
  policy.
- **Spec write fails** — stop wrap-up and preserve the code changes for recovery.
- **A downstream deterministic test or quality gate fails** — do not commit or
  push either code or spec updates.
- **Several specs match one path** — inspect all of them independently; do not
  choose a single owner.
- **No previous spec matches** — the current session spec remains a candidate
  when the normal spec-first workflow was used. Track an undocumented externally
  observable behavior change as deferred reconciliation work rather than
  inventing a new spec during wrap-up.

## Workflow Placement

Reconciliation runs after the task register has been updated and before changed
verification-map maintenance, security review, code review, and final tests.
This placement provides completed task intent while ensuring every spec edit is
covered by all downstream gates.

The sequence is:

```text
capture immutable session change set
  -> update task register
  -> discover candidate specs
  -> reconcile affected specs
  -> persist tasks for deferred reconciliation
  -> maintain verification map when applicable
  -> security and quality reviews
  -> deterministic tests
  -> commit and push code plus specs atomically
```

## Testing Approach

Tests pin the deterministic parts of the workflow and use fixtures rather than
modifying real project specs:

- exact path and glob matching
- rejection of unsupported glob syntax
- staged, unstaged, committed, renamed, and deleted path collection
- explicit metadata taking precedence over legacy fallback
- current-session spec inclusion
- exact parsing of the plan's `> Spec:` association
- many-to-many path matching and candidate deduplication
- rejection of absolute paths and traversal
- invalid metadata producing a loud failure
- idempotent deferred-task creation, update, and reopen behavior
- local task persistence when external publication is unavailable or gated
- automatic external publication only when tracker policy permits it
- deferred task links entering the PR description
- legacy migration rules for an affected spec
- ordinary-bullet Acceptance Criteria in newly generated spec templates
- all updated specs entering downstream review context
- failure of tests or quality gates preventing commit and push
- canonical `.agents/skills/` and compatibility `.claude/skills/` parity

Semantic fixture scenarios pin the required outcomes: behavior change updates a
spec, unrelated shared-file change leaves it byte-identical, and insufficient
evidence defers reconciliation without preventing the PR. Tests do not attempt
to replace agent reasoning with a keyword heuristic.

## Acceptance Criteria

- New workflow-created specs contain valid `implementation_paths` frontmatter,
  a factual `## Implementation Paths` section, and ordinary-bullet Acceptance
  Criteria.
- Wrap-up collects committed, staged, unstaged, renamed, and deleted paths into
  one immutable pre-reconciliation change set.
- The current session spec is always considered when completed task entries name
  it.
- New plan blocks associate their tasks with exactly one repository-relative
  spec using `> Spec: specs/<feature-name>.md`.
- Specs with metadata are selected by repository-relative path/glob
  intersection; legacy specs fall back to `## Files Likely Involved`.
- Path matches generate candidates only; every candidate receives an
  `updated`, `unchanged`, or `deferred` semantic outcome.
- Every semantically affected candidate is updated, including multiple specs
  matched by a shared path; unrelated candidates remain byte-identical.
- Updating a legacy spec adds accurate metadata, replaces prospective path prose,
  and converts Acceptance Criteria checkboxes to ordinary bullets.
- Updated specs describe only current behavior and contain no change-log prose or
  superseded behavior.
- Invalid or unsafe metadata stops wrap-up with actionable evidence.
- An unresolved behavioral effect leaves the spec unchanged, creates or updates
  one idempotent reconciliation task for that spec, and does not prevent the
  remaining gates, commit, push, or PR creation.
- Deferred work is published externally only when the configured task provider's
  existing write policy permits it; otherwise the committed local task remains
  canonical and the pending publication is reported.
- Every deferred task records the unresolved question, inspected and missing
  evidence, relevant paths, source revision, and verifiable reconciliation
  criteria, and is linked from the PR description.
- Updated specs participate in the existing verification, security, review,
  deterministic test, commit, and push gates with the code they document.
- A failing downstream gate prevents both code and spec changes from being
  committed or pushed.
- Wrap-up reports bounded counts and paths for candidate, updated, unchanged,
  and deferred specs.
- Existing specs without metadata remain valid until an affected reconciliation
  migrates them.

## Implementation Paths

- `.agents/skills/wrap-up-session/**` — Step 3.2: candidate discovery, outcome
  assignment, legacy migration, deferred-work persistence, and reporting.
  `scripts/spec-reconcile.py` is the deterministic half.
- `.agents/skills/task-registry/**` — `upsert`, the idempotent provider-neutral
  create-or-update that records a deferred reconciliation task.
- `.agents/skills/plan/SKILL.md`, `.agents/skills/brainstorm/SKILL.md` — the two
  generators that emit specs in this format.
- `specs/README.md` — the format's human documentation.
- `CLAUDE.md` — the Review Dispatch Contract, whose item 2 carries every spec
  relevant to a session.
- `tests/test-living-spec-reconciliation.sh` — the deterministic guards and the
  fixture scenarios.
- `.claude/skills/**` — byte-identical compatibility mirrors of the above.
