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
distinct prompts and the verdict, so no run can be scored on the prompts it was
tuned on. Prior art: mitkox/esf @ e5567fb, `tools/brief_lab/README.md`.

## Behavior

Before any candidate is spawned, `variant-holdout.py split <prompts.json>`
reads the run's prompts, refuses a set with fewer than four distinct prompts,
and prints which prompts are tuning and which are holdout. The author tunes the
variant against the tuning prompts only.

After the runs are graded, `variant-holdout.py verdict <scores.jsonl>` reads one
score per run, recomputes the same split from the prompts it finds, and prints
a report: the split, each arm's mean on the tuning set and on the holdout set,
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
- `scores.jsonl` — one JSON object per graded run:
  `{"prompt": <string>, "arm": "unchanged"|"previous"|"candidate", "score": <finite number>, "cost_usd": <nonnegative number, optional>}`.
  Several runs of one prompt and arm are averaged per prompt first, so every
  prompt weighs the same in its set's mean.
- `--json` on `verdict` prints the same result as JSON.

## Outputs

- `split` prints `tuning:` and `holdout:` lists, one prompt per line, and exits 0.
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

## Interfaces

### `variant-holdout.py`

- **Path:** `.agents/skills/eval/scripts/variant-holdout.py`
- **Hides:** prompt normalisation, the split rule (the prompts sorted by the
  SHA-256 of their normalised text; the first `n // 2` are holdout), per-prompt
  averaging and the two-baseline rule.
- **Interface:** `variant-holdout.py split <prompts.json>` · `variant-holdout.py verdict <scores.jsonl> [--json]`
- **Alternative considered:** a `split` field written into each score record by
  the author. It lost because a declared split can be edited after the scores
  are seen; a split recomputed from the prompt text cannot.
- **Depth:** one call refuses an undersized or incomplete run, reproduces the
  split and applies the promotion rule, so the reader of the report never
  re-derives which prompts were held out.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Who chooses the holdout? | A deterministic rule over the prompt text (SHA-256 order, first `n // 2` held out), recomputed by `verdict`. | assumed | Unattended run; an author-chosen split can be chosen on the outcome, the failure the issue names. |
| 2 | What are "no change" and "previous version" in a harness that cannot ablate a skill? | `unchanged` is the default-branch skill; `previous` is the variant before this tuning round. | assumed | Mirrors esf's direct use / unoptimised / optimised triple without claiming a presence/absence ablation, which SKILL.md says is not measurable here. |
| 3 | Does a tie promote? | No — strictly greater than both baselines. | assumed | "Beats both" in the issue. |
| 4 | Does cost enter the verdict? | No; the report prints each arm's cost and `unknown` when a run did not report one, and SKILL.md keeps "report cost beside lift" as the reader's judgment. | assumed | The issue asks to record unreported cost as unknown, not to change the cost rule. |
| 5 | Exit code on `reject`? | 0, with the verdict in the `Verdict:` line, as `grade-code-graph.py` does. Refusals exit 2. | assumed | A reject is a measurement, not an error; sibling graders already follow this. |

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
  spawning, tune on the tuning prompts only, score all three arms, and promote
  only on a `promote` verdict.

## Implementation Paths

- `.agents/skills/eval/scripts/variant-holdout.py` — the split, the refusals and
  the two-baseline verdict.
- `.agents/skills/eval/SKILL.md` — § Mode B's steps name the script, the three
  arms and the promotion rule.
- `tests/test-eval-variant-holdout.sh` — AC1 to AC5.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | variant-lift holdout | `variant-holdout.py` split and verdict, and § Mode B steps that use them | `.agents/skills/eval/scripts/variant-holdout.py`, `.agents/skills/eval/SKILL.md`, `tests/test-eval-variant-holdout.sh` | — | 1, 2, 3, 4, 5 | `bash tests/test-eval-variant-holdout.sh` | 3 files · 1 system · 5 ACs |

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
Constraints: the holdout is the SHA-256-ordered first n // 2 prompts, recomputed by verdict; arms are unchanged, previous, candidate; a tie rejects; cost never enters the verdict and a missing cost reads unknown; reject exits 0, refusals exit 2.
```
