# Spec reconciliation

> Performed by `/wrap-up-session` § *Spec reconciliation*. Design rationale:
> `specs/living-spec-reconciliation.md`.

A spec describes the repository's **current, tested behavior**. Git history keeps
the earlier intent, so a reader should never have to reconcile historical
amendments or a stale implementation plan to learn what the code does now. This
step is what makes that true: it brings every spec the session actually affected
back into agreement with the code, and commits the spec edit atomically with the
change it documents.

It runs **after** the task register, so completed task intent is available,
and **before** the changed verification map, the quality receipt and the full
suite, so every spec edit passes through all of them.

## Discover candidates

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py discover \
  --base <base-branch> --json
```

When discovery selects something surprising, `changeset` prints the same snapshot
without the matching step, which separates "the change set is wrong" from "the
patterns are wrong":

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py changeset \
  --base <base-branch>
```

Each candidate arrives with `spec`, `source`, `reasons`, and ready-to-use
`evidence` lines. Pass those `evidence` strings through **verbatim** when a
candidate defers — the script owns their shape, so retyping them is how the two
drift apart.

The script captures one immutable change set — committed `<base>...HEAD`, staged,
and unstaged, with both endpoints of a rename and the old path of a deletion —
and returns every spec that change set selects, with the reason for each match.
It is taken **once, before any spec is written**: a change set re-derived
afterwards would contain this step's own edits.

Discovery is deterministic and ordered:

1. the spec named by the completed plan's `> Spec:` line, whether or not it
   carries path metadata;
2. specs whose `implementation_paths` frontmatter intersects the change set;
3. legacy specs, through their `## Files Likely Involved` section;
4. deduplicated, with every match reason retained.

Paths inside `specs/` are excluded from matching, so the step cannot select its
own output. **Invalid or unsafe metadata exits non-zero naming the spec and the
value** — it is never ignored and never treated as "no match", because a
pattern that matches nothing is indistinguishable from a spec nobody touched.

## Assign an outcome

A path match is a *candidate*, not a verdict. For each candidate, read the
relevant diff, the full affected code flow, its callers, and the deterministic
tests, then assign **exactly one outcome**:

| Outcome | When | Action |
|---------|------|--------|
| `updated` | observable behavior or the current implementation surface changed | rewrite the affected contract sections and refresh path metadata |
| `unchanged` | the path changed but the spec's behavior and surface remain accurate | **leave the file byte-identical** |
| `deferred` | the behavioral effect cannot be determined from repository evidence | leave the spec unchanged, persist a reconciliation task (below), continue |

The comparison is **semantic rather than keyword-based**. Formatting-only
changes, internal refactors with no contract or surface change, and edits to a
shared file unrelated to this spec all produce `unchanged`. Grepping the diff for
words that appear in the spec is not this step: it rewrites specs that did not
change and misses the ones that did.

For `updated`, trace the **complete current feature flow** rather than copying
paths out of the diff, then replace stale metadata with the smallest accurate set
of paths covering that surface. This is what repairs old mappings when files move
or new implementation paths appear.

Updated prose describes behavior directly. It **must not mention the session**,
the diff, the fact that an update occurred, or the behavior it supersedes. That
history belongs in Git, and a spec carrying it becomes a changelog that rots on
the next commit.

## Migrate a legacy spec, but only when it changed

When a candidate **without** metadata is `updated`:

1. add valid `implementation_paths` frontmatter;
2. replace `## Files Likely Involved` with `## Implementation Paths`;
3. rewrite prospective descriptions into current factual ones;
4. convert Acceptance Criteria checkboxes into ordinary bullets;
5. leave unrelated accurate content intact.

An `unchanged` legacy candidate is **not** rewritten merely to migrate its
format. Migration rides on behavioral change so the diff stays readable —
reformatting a spec in the same commit that alters it would bury the part a
reviewer needs to see.

## Persist deferred work

An uncertain behavioral effect is **documentation debt, not a wrap-up blocker**.
For each `deferred` candidate, record one durable task through `/task-registry`
before continuing — workflow code never calls the tracker itself:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert --apply \
  --derive-id spec-reconciliation --spec <spec-path> \
  --title 'Reconcile <spec> with current <area> behavior' \
  --kind research \
  --summary '<the behavior question repository evidence could not resolve>' \
  --evidence '<each selected-by: line from the candidate, verbatim>' \
  --evidence 'inspected: <what was read>' \
  --evidence 'missing: <what was not available>' \
  --evidence 'revision: <branch> @ <short-sha>' \
  --criterion 'Determine the current behavior' \
  --criterion 'Update <spec> and its implementation_paths to match' \
  --criterion 'Add deterministic coverage where the gap came from a missing test'
```

**Use `--derive-id`, never a hand-typed ID.** The ID is
`spec-reconciliation.<normalized-spec-path>`, derived from the **complete**
repository-relative spec path so each spec has at most one live reconciliation
task. Both `spec-reconciliation.feature-c` and
`spec-reconciliation.specs-feature-c-md` are *valid* IDs, so a hand-typed one
that normalizes differently mints a second task instead of updating the first —
silently, and only on the second session. `--derive-id` computes it from the
`--spec` path you already have, which makes that mismatch unrepresentable.

A recurring unresolved change updates that task with new evidence; if it had been
completed, the new uncertainty **reopens** it. Re-running wrap-up over the same
change set is therefore idempotent.

Where the canonical body lands follows the project's **existing** write policy —
this step never widens it:

| Situation | Result |
|-----------|--------|
| No tracker configured | the local Markdown record is canonical |
| External provider and its policy already permits unattended writes | the external issue is the record; the index links it |
| Approval required and not given, or provider unreachable | the local record stays canonical, and **publication is pending** |

In the last case wrap-up **does not pause or fail**. Pausing would hang an
unattended run, and publishing anyway would breach the policy the project set;
keeping the work locally and reporting the pending publication loses neither.

If the local record itself cannot be written, **STOP wrap-up: the documentation
debt would otherwise be lost** — which is the one thing this step exists to
prevent. End through `.agents/skills/wrap-up-session/SKILL.md` § *Terminal PR assertion*.

The **PR description** lists every deferred reconciliation task, so a reviewer
sees that the affected spec was deliberately left alone rather than missed.

## Report

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

No candidates is a **successful outcome** and stays one line. So is all-unchanged — but it still names the specs it compared.

Updated specs then join the code in the verification, security, review, test,
commit, and push gates that follow — and a **failing gate blocks both**. A spec
committed while the code it documents was rejected would publish a description of
behavior that does not exist, which is worse than the stale spec it replaced.
