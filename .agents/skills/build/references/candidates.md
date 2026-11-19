# Candidates — several Builders on one slice

A hard slice can be built N ways and the best result kept by fixed rules
(contract: `specs/parallel-candidates.md`). It is opt-in per slice and costs N
dispatches, so use it only where one attempt keeps failing or the design is
genuinely open; the run ledger records every attempt, so the choice can be
checked against one stronger attempt later.

## Opting in

A slice opts in with one line directly under its heading in `tasks/todo.md`,
N ≥ 2:

```markdown
### Slice 2/3 — Parser
> Candidates: 3
- [ ] Parser — …
```

Without that line the slice builds as before.

## The flow, in place of Step 1's single dispatch

```bash
python3 .agents/skills/build/scripts/candidates.py open --slice <n> --count <N>
```

Creates N detached worktrees at the current `HEAD` through
`bootstrap-worktree.sh --detach-head`, at `<toplevel>/../<repo>-slice-<n>-c<k>`,
and prints `candidates: c<k> <path>` for each. Commit the previous slice first:
candidates start from `HEAD`, not from the working tree.

Dispatch one Builder per path — the Step 1 delegation prompt, plus "work only
inside `<path>`". Builders run in parallel; none runs the affected tests.

```bash
python3 .agents/skills/build/scripts/candidates.py rank --spec <spec> --slice <n> \
  --branch "$(git branch --show-current)" --base <build base sha> \
  --agent c1=<true|false|unknown> ... -- <affected-test command>
```

`--agent c<k>=` is each dispatch's claim, read as in Slice Close; a candidate
with no `--agent` is `unknown`. `rank` measures each candidate's diff against
the commit it started at, runs the verification through `slice_outcome.py`
inside it, then ranks smallest key first:

1. eligible (`slice_result=True SUCCEEDED`) before ineligible;
2. more checks passed (`agent_result`, `verification_result`);
3. fewer diff lines;
4. fewer changed paths outside the slice's Surface;
5. lower candidate number — the tiebreak that makes the order total.

It prints one line per candidate with its reason, writes them into the run
record (`.agents/skills/build/references/run-ledger.md` § *Candidates*),
applies the winner's diff to the main tree, prints `candidates: applied c<k>`
and removes every candidate worktree — also when it is terminated.

| Exit | Meaning | Next |
|------|---------|------|
| 0 | winner applied | Slice Close, as for any slice; `attempts=<N>` in Phase 6's `--slice` |
| 1 | no eligible candidate, or the winner's diff does not apply (patch kept under `tasks/tmp/`) | Step 3, as for a failed slice |
| 2 | usage | fix the call |

## Stopping between `open` and `rank`

```bash
python3 .agents/skills/build/scripts/candidates.py discard --slice <n>
```

Removes the slice's candidate worktrees and prints `candidates: removed c<k>
<path>` for each. `open` refuses while any are left, naming `discard`.
