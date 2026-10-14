---
name: learn
description: Extract durable learnings from the current session and persist them as typed documents in tasks/solutions/.
argument-hint: "[--cleanup]"
disable-model-invocation: false
harness: universal
---

# /learn — Capture Session Learnings

Extract durable learnings from this session and persist each as a typed document
under `tasks/solutions/<category>/<slug>.md`, plus one narrative entry in
`tasks/history.md`. The schema, `problem_type` enum, and category map live in
`tasks/solutions/README.md` — documents must validate against it
(`tests/test-solutions-schema.sh` enforces this in the template repo).

## Steps

### 1. Review the Session
- Run `git log --oneline -10` to see what changed
- Read `tasks/todo.md` to see what was completed
- Recall any corrections the user made or surprises encountered

### 2. Extract 1–5 Learnings
Focus on insights that would prevent future mistakes or speed up future work:
- Mistakes made and their root causes → **bug track**
- Effective approaches discovered, architectural decisions, edge cases,
  workflow patterns → **knowledge track**

Skip trivial or one-off observations. Only persist learnings with reuse value.

### 3. Ground Every Claim
A claim about how code behaves must be **verified against the tree and cited as
`file:line`**, or softened and attributed ("this session observed…"). Cite PR
numbers, not bare commit SHAs — rebase and squash merges rewrite SHAs. A learning
with no verifiable code claim goes on the knowledge track with its claims
attributed to the session rather than stated as fact.

### 4. Score Overlap Before Writing
For each candidate, compare against existing documents (grep
`tasks/solutions/` frontmatter: `problem_type`, `module`, `tags`) across the
five dimensions of the candidate's track:

| Track | Dimensions |
|-------|------------|
| bug | problem, root cause, solution, files touched, prevention rule |
| knowledge | situation (`applies_when`), claim, files or module, rule, consequence |

On the knowledge track the claim is what the document asserts (the decision,
pattern or convention), the rule is what to do when the situation recurs, and
the consequence is what ignoring it costs. A document on the other track scores
Moderate at most: cross-link it, never merge across tracks.

| Score | Dimensions matched | Action |
|-------|--------------------|--------|
| High | 4–5 | Update the existing document. Do not create a second one. |
| Moderate | 2–3 | Create the new document and cross-link both. |
| Low | 0–1 | Create the new document. |

If the existing document is wrong, update it and note the correction — never add
a contradicting sibling.

### 5. Write the Documents
Create `tasks/solutions/` (and the category directory) if absent — first write
bootstraps the store. Filename is a stable ASCII kebab-case slug from the title;
**the date goes in frontmatter, never in the filename**. Frontmatter per track:

- both tracks: `title`, `date`, `problem_type`, `module`, `tags`
- bug track: `symptoms`, `root_cause`, `resolution`
- knowledge track: `applies_when`

A document with an inferred or missing required field gets `needs_review: true`
so `/memory-maintain` sweeps it later.

### 6. Append the Session Entry to `tasks/history.md`
The narrative log records what happened, not learnings:

```
### [YYYY-MM-DD] — [2-3 word summary]
- Key changes: [bullet list of what was built/changed]
- Learnings captured: [links to the tasks/solutions/ documents, or "none"]
```

### 7. Capture New Concepts (side effect — never a separate prompt)
If a learning surfaced project-specific vocabulary — an entity, named process,
or status term whose meaning is local to this project — add it to
`tasks/concepts.md` under the matching section, keeping the entry format
(`- **term** — definition.`, alphabetical). A term that already exists gets its
definition refined in place, never a duplicate bullet. Standard industry terms
do not qualify — `/memory-maintain` prunes them.

If `tasks/concepts.md` is absent (project predates the seed), recreate the
template seed in full — the format header, a `> Sweep: pending` marker line,
the `## Harness vocabulary` section **with its six entries** (tier, gate,
register, drift, ceiling, store — Phase 0 sweeps only the project's own
material and will not refill them), and the `## Project vocabulary` section —
so the next `/memory-maintain` run still performs its one-time bootstrap sweep
and later writers find the sections they file under.

Most sessions surface no new vocabulary; write nothing in that case.

### 8. Confirm
Reply: "Learnings captured: [N] documents in `tasks/solutions/` ([updated/created]), history entry appended[, [M] glossary terms added/refined]."

---

## Optional: `--cleanup`

When invoked as `/learn --cleanup`, after completing Steps 1–8, run a folder sweep to surface legacy or unused files for archival.

For each directory that has accumulated session artifacts:
1. List all files and check creation dates via `git log --follow --oneline -- <file>`
2. Flag files that:
   - Were created more than 30 days ago and have never been read in recent sessions
   - Are referenced by no current spec, task, or source file
   - Appear to be one-off experiments (scratch files, test outputs, temporary logs)
3. Propose archival:
   > "These files appear unused: [list]. Archive to `archive/` or delete? (archive/delete/keep each)"
4. Act on user response. Do not delete without confirmation.

Skip: `tasks/`, `specs/`, `.claude/`, `.agents/` — these are always kept.
