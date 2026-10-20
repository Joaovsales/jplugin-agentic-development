# Design-mode `/build` comparison — operator runbook

Operator-only. Nothing in this file or in `answer-key.md` is copied to a candidate.
The two feature directories (`retrykit/`, `confkit/`) are the seeds; each is copied,
renamed to something neutral and committed before a candidate sees it.

This is slice 14 of `specs/aposd-first-build.md` (AC17), run as `/eval` Mode B
(variant lift, `.agents/skills/eval/SKILL.md`). Read its § Blinding non-negotiables
before staging anything.

## The two arms

| Arm | Plugin checkout | Plan staged into `tasks/todo.md` |
|-----|-----------------|----------------------------------|
| A | master (legacy `/build`, `slice.py ready` prints `mode=tdd`) | `<feature>/plans/legacy.md` |
| B | the design-mode branch (slices 9 and 11 present, `mode=design`) | `<feature>/plans/design.md` |

Both arms get the same seed, the same spec and the same organic prompt. Only the plan
file and the plugin checkout differ. N >= 2 per arm per feature (so >= 4 runs per arm
over both features). Run the arms interleaved, never all of one arm first.

Blinding: the candidate never learns it is measured and never learns another run
exists. Use short project-shaped directory names such as `~/work/relay-7f3a` and
`~/work/settings-2c91`; never a name that carries the arm, the feature set or the
word for what this is.

## Stage one run

Run from Git Bash. `SEED` is this directory's feature folder, `ARM` is `legacy` or
`design`, `PLUGIN` is a checkout of the arm's branch (a plain `git worktree add` of
master for A, of the design-mode branch for B).

```bash
SEED=/path/to/tests/fixtures/build-eval/retrykit      # or .../confkit
ARM=legacy                                            # or design
SPEC=retry-with-budget                                # or layered-config
PLUGIN=/path/to/checkout-of-the-arm-branch
RUN=$HOME/work/relay-7f3a                             # neutral, unique per run

mkdir -p "$RUN" && cp -r "$SEED"/. "$RUN"/
cd "$RUN"
mkdir -p tasks
{ echo "# Tasks"; echo; cat plans/$ARM.md; } > tasks/todo.md
rm -rf plans                       # the candidate must not see either plan file
git init -q && git add -A && git commit -qm "Initial project" && git tag base
python scripts/run_tests.py        # seed state: 4 passing tests, exit 0
```

Check the staging with the arm's own plugin before the run:

```bash
python3 "$PLUGIN/.agents/skills/slice/scripts/slice.py" ready \
  --index tasks/todo.md --spec specs/$SPEC.md
# arm A prints  mode=tdd   arm B prints  mode=design
```

Do not run `/slice`: the plan is staged by hand. The legacy plan carries `TDD:` rows
and task ids; the design plan carries bare slice headers and one feature row
(`<!-- task-id: plan.<spec-id> -->`). Because the feature row has no tracker link,
arm B's `/build` pre-flight tries one `upsert`; this directory has no remote and no
tracker configuration, so it must continue with the "feature issue not filed" line.
If a run stops there, record it as a run failure, not an arm result.

## The organic prompt

One prompt per feature, identical for both arms. State the goal, name the plan and
nothing else. No mention of design, interfaces, freezing or tests being written first.

retrykit:

```
We need retries with a shared budget in this project. The spec is
specs/retry-with-budget.md and the plan is in tasks/todo.md. Please build it with
/build and make sure everything passes. Commit as you go but do not push anywhere.
```

confkit:

```
We need layered config loading in this project. The spec is
specs/layered-config.md and the plan is in tasks/todo.md. Please build it with
/build and make sure everything passes. Commit as you go but do not push anywhere.
```

The no-push clause is part of the prompt: the run directories have no remote, so a
push would only fail noisily, and `/wrap-up-session` is not asked for. Do not add
`/quality-gate` to the prompt; `/build` runs it itself (Layer 2), and its design
findings are graded from the transcript.

## Run the candidate

```bash
cd "$RUN"
export MSYS_NO_PATHCONV=1          # Git Bash rewrites a leading /name into a path
claude -p "<the organic prompt above>" \
  --plugin-dir "$PLUGIN" \
  --output-format stream-json --verbose \
  --permission-mode acceptEdits \
  --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Task,Skill" \
  > "$RUN/../transcript-<run-label>.jsonl"
```

Use Windows-form paths for `--plugin-dir` if `claude` is a native Windows binary
(`C:/Users/...`), and keep the prompt's `/build` literal. Keep the transcript outside
the run directory; the candidate must not find it.

Cost: the final `{"type":"result", ...}` event of the stream carries
`total_cost_usd` and `usage`; read it with
`grep '"type":"result"' transcript.jsonl | tail -1`. Record cost per run.

Per-run wall-clock limit: one hour. A run that hits it is graded on what exists and
flagged `timed_out`.

## After the run

```bash
cd "$RUN"
python scripts/run_tests.py > ../final-<run-label>.txt 2>&1   # suite at the end state
git log --format='%h %s' base..HEAD > ../log-<run-label>.txt
git diff base..HEAD > ../diff-<run-label>.patch
```

Keep, per run: the transcript, the final suite output, the git log, the diff, and a
copy of `tasks/todo.md` at the end (for the `> Frozen:` and `> Test amended:` lines).

## Grade

Grading is in `answer-key.md`; the criteria were written there before any run and
must not change after the first run starts. In short, four measures per run:

1. **AC coverage**: how many of the feature's ACs hold, checked by the answer key's
   probe test files (run against the candidate's code; the candidate never sees them).
2. **Test-freeze violations**: from the git history, arm B only (arm A has no freeze
   and scores n/a, recorded as 0).
3. **`/quality-gate` design findings**: the count of design findings the answer key
   lists as pitfalls, judged on the final diff by one judge in one pass over all runs
   under sanitized labels (`run-01` ... `run-NN`; never the arm, the plugin or the
   run directory name).
4. **Cost**: `total_cost_usd` from the result event, summed per arm.

Aggregate per arm as the mean over its runs; report every run too, so a single
outlier is visible.

## The keep-or-revert rule (AC17, verbatim)

> A Mode B `/eval` run (N ≥ 2 per arm) compares arm A, master's `/build` on a legacy
> plan of the same features, with arm B, the design-mode `/build`, on AC coverage,
> test-freeze violations, `/quality-gate` design findings and cost. The report
> states the rule's result: keep design mode when arm B's AC coverage is at least
> arm A's, its design findings are fewer, and its cost is at most twice arm A's;
> otherwise recommend reverting slices 9 and 11. The user makes the call, and the
> report path is in the PR body.

State the result as three explicit comparisons, each with both numbers, then the
recommendation (keep, or revert slices 9 and 11). The user decides; the report path
goes in the PR body. Report test-freeze violations beside the rule even though the
rule does not use them. Never edit the rule's thresholds after seeing data.

## Rubric

The judge rubric and the answer keys are in `answer-key.md`. The judge may know it is
judging; it sees only sanitized labels and diffs, never an arm, a plugin or a model
name, and scores every run in one pass on one scale (`.agents/skills/eval/SKILL.md`
§ Grading).

## Cleanup

Delete the run directories and the plugin worktrees after grading. The fixtures here
stay unchanged; never run a candidate inside this directory.
