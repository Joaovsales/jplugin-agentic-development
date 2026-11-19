# Run ledger — who records what

Every build run and every review rework leaves one record,
`tasks/runs/<run-id>.json`, written only through
`.agents/skills/build/scripts/run_ledger.py` (contract: `specs/run-ledger.md`).
The records are committed with the run's other `tasks/` files. No record holds
a total: `run_ledger.py stats` derives first-pass rate, attempts per merged PR
and cost and tokens per merged PR from the files each time it runs.

## `/build` Phase 6 — the build run

Once every slice has closed, record the run against the build's base SHA:

```bash
python3 .agents/skills/build/scripts/run_ledger.py record --branch "$(git branch --show-current)" \
  --base <base sha> --spec specs/<feature>.md [--pr <n>] \
  --model planner=<model> --model builder=<model> --model reviewer=<model> \
  --slice "<n> attempts=<k> <Outcome line>" ... [--tokens <n>] [--cost <usd>] [--parent <run-id>]
```

- `--slice` repeats once per slice: its number, the dispatches it took
  (`attempts`, the first counts as 1), then its `> Outcome:` line without the
  `> Outcome: ` prefix. A label that does not follow from its results is refused.
- `--model` names the model each tier actually ran on.
- `--tokens` and `--cost` are passed only when the harness reported them.
  Left out, the record stores `unknown`, never 0, and `stats` shows any
  merged PR missing them as `unknown`.
- The run id defaults to `<branch slug>-<base sha, 12 chars>`, so running the
  same `record` again rewrites the same file and changes no count. Pass
  `--pr` once the pull request exists (`/wrap-up-session` may re-run the same
  call with it).
- On a `routine/fix/` branch that retries an earlier fix, pass
  `--parent <run-id>` of the earlier run (`run_ledger.py last --branch <its branch>`).

## `/receive-review` — a rework run

A human or external reviewer asking for changes on an open PR starts a rework
run whose parent is the branch's latest run. `/receive-review` decides the
parent `changes_requested` and records the rework with `--parent`; see its
§ *Record the rework run*.

## Candidates

A slice built by several candidates (`.agents/skills/build/references/candidates.md`)
is recorded by `candidates.py rank` itself, into the same run record (the run
id from `--branch` and `--base`, as `record` derives it): a `candidates`
field, `{"<slice>": [ … ]}`, one entry per candidate with `candidate`, `rank`,
`selected`, `eligible`, the three outcomes and `label`, `checks_passed`,
`diff_lines`, `outside_surface` and `reason`. `record` has no option for it
and keeps it; `stats` does not read it. The write takes the same per-run
lock as `record` and `decide` and refuses a malformed stored record; a
`candidates` field that is not an object is malformed. The schema stays `run-ledger/1`.

## The merge or close — the human result

Whoever merges or closes the PR — the owner, or the job that performs the
merge, next to its `task-registry closes` call — records the decision on the
branch's latest run:

```bash
run="$(python3 .agents/skills/build/scripts/run_ledger.py last --branch <branch>)"
python3 .agents/skills/build/scripts/run_ledger.py decide --run-id "$run" --result merged   # or --result closed
```

`merged` and `closed` are final: `decide` refuses to change them, since
a final human decision is never overwritten — and `record` has no option
that sets a human result at all, so a later run cannot either. Deciding the same
result twice is a no-op.

Both writers hold the same per-run OS lock across read, validation and atomic
replacement: `flock` on Unix, a one-byte `msvcrt` lock on Windows. A writer
waits at most 10 seconds, then refuses with the lock path. The OS releases
locks when a process exits, so a crashed writer leaves no stale ownership;
the ignored `.lock` files stay in place so waiters keep using the same file.

## Reading the ledger

```bash
python3 .agents/skills/build/scripts/run_ledger.py stats
```

A PR is a chain of runs linked by `parent_run_id`. First pass is a PR merged
in one run with no `changes_requested`, over the merged plus closed PRs; an
attempt is a run in the chain. A rate or per-PR value with nothing to divide
by prints `unknown`, never 0%.

Malformed stored decisions, histories or telemetry refuse with the record's
path. `last` keeps exit 1 for both absence and errors; only its exact diagnostic
`last: no run on branch <branch> in <ledger>` means absence. Callers stop and
report every other failure rather than skipping the ledger step.
