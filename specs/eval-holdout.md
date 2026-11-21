---
implementation_paths:
  - .agents/skills/eval/SKILL.md
  - .agents/skills/eval/scripts/variant-holdout.py
  - tests/test-eval-variant-holdout.sh
---

# Spec: Variant-lift holdout and two-baseline promotion

## Summary

`/eval` Mode B (variant lift) splits its prompts into a tuning set and a
holdout set the variant is never tuned on, and promotes a variant only when its
holdout mean beats both the unchanged skill and the variant's previous version.
One script, `variant-holdout.py`, owns the split rule, the refusal below four
distinct prompts, the manifest and the verdict. A fingerprint recorded by the
orchestrator outside the tuning loop binds the verdict to the original split.
Prior art: mitkox/esf @ e5567fb, `tools/brief_lab/README.md`.

## Behavior

Before any candidate is spawned,
`variant-holdout.py split <prompts.json> --manifest <manifest.json>` reads the
run's prompts, refuses a set with fewer than four distinct prompts, prints which
prompts are tuning and which are holdout, and writes that membership to the
manifest, refusing to overwrite one. It prints `split: fingerprint <hex>` (the
`fingerprint` field with `--json`): SHA-256 of the canonical normalized manifest
JSON, with sorted keys, compact separators, unescaped Unicode and UTF-8 encoding.
The normalized prompts and array order come from the split rule. Before
dispatching any tuning, the orchestrator records `Manifest fingerprint: <hex>`
in the eval report header outside the tuning agent's write surface. The tuning
agent tunes against the tuning prompts only and is never asked to recompute the
expected fingerprint. Published results carry the same value in the PR body.

After the runs are graded,
`variant-holdout.py verdict <manifest.json> <scores.jsonl> --expect <fingerprint>`
requires the value retained in that pre-tuning header. It reads the manifest,
re-applies the split rule to its prompts and refuses it unless the rule
reproduces its membership and its fingerprint matches `--expect`. It then
reads one score per run and refuses any
scored prompt the manifest lacks and any manifest prompt with no scored runs.
The cut depends on the whole set, so adding or dropping a prompt after tuning
can move it, and either can put a tuned-on prompt in the holdout. It then prints a
report: the split, each arm's mean on the tuning set and on the holdout set,
each arm's cost, and one `Verdict:` line. The verdict is `promote` only when the
candidate's holdout mean is strictly greater than both the `unchanged` and the
`previous` holdout means; otherwise it is `reject`, naming the baseline it did
not beat. A variant that wins on the tuning set and not on the holdout is
rejected, and the report shows the tuning win beside the holdout loss.

The three arms are:

- `unchanged` — the skill as it is on the default branch, what ships if nothing
  is promoted (esf's "direct use").
- `previous` — the variant before this tuning round (esf's "unoptimised brief").
- `candidate` — the tuned variant (esf's "optimised brief").

## Inputs

- `prompts.json` — a JSON array of prompt strings, the organic prompts the run
  hands candidates.
- `manifest.json` — `{"tuning": [<prompt>...], "holdout": [<prompt>...]}`, the
  normalised split `split --manifest` wrote before tuning.
- `--expect <fingerprint>` — required by `verdict`; the orchestrator's original
  recorded fingerprint, never recomputed from the submitted manifest.
- `scores.jsonl` — one JSON object per graded run:
  `{"prompt": <string>, "arm": "unchanged"|"previous"|"candidate", "score": <finite number>, "cost_usd": <nonnegative number, optional>}`.
  Several runs of one prompt and arm are averaged per prompt first, so every
  prompt weighs the same in its set's mean.
- `--json` on `verdict` prints the same result as JSON.

## Outputs

- `split` prints `tuning:` and `holdout:` lists, one prompt per line, writes the
  manifest when `--manifest` is given, prints `split: fingerprint <hex>`, and
  exits 0. With `--json`, it prints the two arrays and a `fingerprint` field.
- `verdict` prints the split, a table of arm × tuning mean × holdout mean ×
  cost, and `Verdict: promote — …` or `Verdict: reject — …`; it exits 0 on
  either verdict.
- Any refusal prints `variant-holdout: <reason>` on stderr and exits 2.

## Edge Cases

- Fewer than four distinct prompts (after whitespace is collapsed and ends are
  trimmed, so two copies of one prompt count once) — refused, exit 2, before any
  split is printed.
- A prompt missing one of the three arms in `scores.jsonl` — refused: a baseline
  the report cannot show is not a comparison.
- An unknown arm name, a non-numeric or non-finite score, a negative cost, or a
  line that is not a JSON object — refused with the line number.
- A run without `cost_usd` — that arm's cost prints `unknown`, never `0`.
- A tie between the candidate and a baseline on the holdout — `reject`: the
  candidate has to beat both baselines, not match them.
- A scored prompt not in the manifest (added after tuning), or a manifest
  prompt with no scored runs (dropped after tuning) — refused before any mean
  is computed: either moves the `n // 2` boundary.
- A manifest whose membership the split rule does not reproduce (edited by
  hand) — refused. An existing manifest is never overwritten by `split`.
- A regenerated, consistently replaced, or unlinked-and-regenerated manifest
  with a different fingerprint — refused against the original `--expect` value,
  even if its partition is valid. Omitting `--expect` also refuses (exit 2).

### Trust boundary

A local manifest can always be rewritten by its operator. The verifier binds
it to the fingerprint the orchestrator retained outside the tuning loop; it
cannot establish when an arbitrary fingerprint was recorded. An orchestrator
that rewrites its own recorded fingerprint is out of scope. No external ledger
or filesystem immutability is claimed.

## Interfaces

### `variant-holdout.py`

- **Path:** `.agents/skills/eval/scripts/variant-holdout.py`
- **Hides:** prompt normalisation, the split rule (the prompts sorted by the
  SHA-256 of their normalised text; the first `n // 2` are holdout), per-prompt
  averaging and the two-baseline rule.
- **Interface:** `variant-holdout.py split <prompts.json> [--manifest <manifest.json>]` · `variant-holdout.py verdict <manifest.json> <scores.jsonl> --expect <fingerprint> [--json]`
- **Alternative considered:** a `split` field written into each score record by
  the author. It lost because a declared split can be edited after the scores
  are seen. Recomputing the split from the scored prompts alone lost too: the
  cut depends on the set, so a prompt added or dropped after tuning moves it
  (PR #449 review). A self-consistent manifest alone lost too: it can be
  regenerated after tuning. The externally retained fingerprint anchors its
  original identity; the rule separately validates its membership.
- **Depth:** one call refuses an undersized or incomplete run, reproduces the
  split and applies the promotion rule, so the reader of the report never
  re-derives which prompts were held out.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Who chooses the holdout? | A deterministic rule over the original normalized prompt set (SHA-256 order, first `n // 2` held out), pinned by `split --manifest` and revalidated by `verdict`. | assumed | Unattended run; an author-chosen split can be chosen on the outcome, the failure the issue names. |
| 2 | What are "no change" and "previous version" in a harness that cannot ablate a skill? | `unchanged` is the default-branch skill; `previous` is the variant before this tuning round. | assumed | Mirrors esf's direct use / unoptimised / optimised triple without claiming a presence/absence ablation, which SKILL.md says is not measurable here. |
| 3 | Does a tie promote? | No — strictly greater than both baselines. | assumed | "Beats both" in the issue. |
| 4 | Does cost enter the verdict? | No; the report prints each arm's cost and `unknown` when a run did not report one, and SKILL.md keeps "report cost beside lift" as the reader's judgment. | assumed | The issue asks to record unreported cost as unknown, not to change the cost rule. |
| 5 | Exit code on `reject`? | 0, with the verdict in the `Verdict:` line, as `grade-code-graph.py` does. Refusals exit 2. | assumed | A reject is a measurement, not an error; sibling graders already follow this. |
| 6 | How is the verdict bound to the split-time prompts? | `split --manifest` writes the membership and prints its fingerprint; before tuning the orchestrator records that value outside the tuning loop, then passes it unchanged via required `--expect`. The verdict validates both identity and membership. | confirmed | Coordinator decision after PR #449 re-review: a self-consistent regenerated manifest still promoted the tuning-only candidate. |
| 7 | What is the residual trust boundary? | The orchestrator retains the original fingerprint honestly; rewriting its own recorded fingerprint is out of scope. | confirmed | Coordinator chose a small external fingerprint anchor, without a new ledger. |

## Acceptance Criteria

- AC1: `variant-holdout.py split` and `variant-holdout.py verdict` given fewer
  than four distinct prompts exit 2 naming the four-prompt minimum, and print no
  split or verdict.
- AC2: The `verdict` report prints the `unchanged` and `previous` holdout means
  beside the candidate's, and the split it used.
- AC3: A candidate whose tuning mean beats both baselines while its holdout mean
  does not beat both gets `Verdict: reject`; one that beats both on the holdout
  gets `Verdict: promote`.
- AC4: A run without `cost_usd` reports that arm's cost as `unknown`.
- AC5: `/eval` SKILL.md § Mode B tells the author to run `split` before
  spawning, record the fingerprint in the report header before dispatching any
  tuning and in the PR body when publishing results, pass that retained value to
  `verdict --expect`, tune on tuning prompts only, score all three arms, and
  promote only on a `promote` verdict.
- AC6: `verdict` requires the manifest `split --manifest` wrote, and refuses
  (exit 2, no verdict) a scored prompt added after the split, a manifest prompt
  dropped from the scores, and a manifest edited to move a prompt.
- AC7: Each prompt weighs the same in its set's mean whatever its run count: a
  holdout prompt run ten times cannot outvote the others.
- AC8: `split` prints the canonical manifest fingerprint. `verdict` requires
  `--expect` and refuses (exit 2, no verdict) regenerated, in-place replaced and
  unlinked-and-regenerated manifests against the original fingerprint; the
  original manifest still verifies.

## Implementation Paths

- `.agents/skills/eval/scripts/variant-holdout.py` — the split, the refusals and
  the two-baseline verdict.
- `.agents/skills/eval/SKILL.md` — § Mode B's steps name the script, the three
  arms and the promotion rule.
- `tests/test-eval-variant-holdout.sh` — AC1 to AC8.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | variant-lift holdout | `variant-holdout.py` split and verdict, and § Mode B steps that use them | `.agents/skills/eval/scripts/variant-holdout.py`, `.agents/skills/eval/SKILL.md`, `tests/test-eval-variant-holdout.sh` | — | 1, 2, 3, 4, 5, 6, 7, 8 | `bash tests/test-eval-variant-holdout.sh` | 3 files · 1 system · 8 ACs |

Build prompt:

```
Invoke `/build` for `specs/eval-holdout.md`.
Plan: `## Plan: Variant-lift holdout and two-baseline promotion` in `tasks/todo.md`, 1 slices, ready set <1>.
Files: .agents/skills/eval/SKILL.md, .agents/skills/eval/scripts/variant-holdout.py, tests/test-eval-variant-holdout.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: split writes the normalized original manifest and prints its fingerprint; before tuning the orchestrator records that fingerprint outside the tuning agent's write surface; verdict requires it via --expect and validates identity, membership and the scored prompt set; an orchestrator rewriting its own recorded fingerprint is out of scope; the holdout is the SHA-256-ordered first n // 2 prompts; arms are unchanged, previous, candidate; a tie rejects; cost never enters the verdict and a missing cost reads unknown; reject exits 0, refusals exit 2.
```
