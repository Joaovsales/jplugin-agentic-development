# Design-mode slice loop for /build

A slice is design mode when `slice.py ready` prints `mode=design`: a § Interfaces
`Path:` of the spec matches the slice Surface and the plan block is not legacy.
Everything else is tdd mode and unchanged: one dispatch per slice, run through
`/tdd`, parallel in worktrees when the Surface is disjoint.

Design-mode slices run one at a time in the main tree, in table order: never in
parallel and never worktree-isolated, because the freeze compares commits on one
branch. `/build` implements nothing itself — every step below is a dispatch, and
each one carries the stall rules of `subagent-resilience.md`. Tdd-mode slices
dispatched beside a design-mode slice keep running in their worktrees; a failed
Write dispatch stops only its own slice.

## The loop

Record the slice base `<sha>` (`git rev-parse HEAD`) before step 1.

1. Stubs — dispatch an implementer (`backend-developer` or `frontend-developer`)
   to add stubs with interface comments for the slice's new or changed entry
   points only; existing code is never replaced by a stub. Commit; that commit
   is `S`. The Surface check still applies to the stub paths.
2. Write — dispatch `test-engineer` (Write job, model `sonnet` on Claude Code).
   The prompt carries only § Acceptance Criteria, § Interfaces, § Edge Cases
   or, in an architecture spec, § Component contracts and § Data models, and
   the stub paths. It carries no implementation, no plan block, no handovers
   and no earlier slice's code. The writer returns test files that exercise only
   the interface and one `context: fresh | forked | inline` line.
3. Red — commit the test files; that commit is `F`. Run them with the affected-test
   command. They must fail for the new or changed behaviour; a green run means
   the tests assert nothing, so re-dispatch step 2 once and then trip the
   circuit breaker. Keep the failing summary in one line.
4. Freeze — write one line under the slice heading, before any implementation
   commit:

   ```markdown
   > Frozen: <S>..<F> — red: <failing summary> — context: <fresh, forked or inline>
   ```

   `context:` is the writer's own value. Claude Code (`Agent`) and Pi dispatch
   fresh. Codex writes `forked` unless Q1 of the spec is answered fresh (see
   `harness-dispatch.md`). At most one `> Frozen:` line per slice: a second
   freeze for the same slice is refused.
5. Implement — dispatch the implementer to make the frozen tests green without
   editing them. A test that must change is a `> Test amended:` line, never a
   silent edit:

   ```markdown
   > Test amended: <path> — <reason>
   ```

   `<path>` must be a contract test of the slice (a file changed in `S..F`
   outside `tasks/`).
6. Depth pass — one more dispatch step over the implementation: shallow
   modules, pass-through methods, leaked internals and error paths worth
   defining away, per the APOSD review in Phase 3.5. Tests stay green.
7. Check — Slice Close runs

   ```bash
   python3 .agents/skills/slice/scripts/slice.py check --spec <spec> --slice <n> --base <sha> --index tasks/todo.md
   ```

   Exit 3 prints `frozen-edited: <path>`, `amended-unknown: <path>` or
   `missing freeze commit`: stop on exit 3 — end the build, report the line,
   and write no handover. Exit 1 is surface drift, informational; 0 is clean;
   2 is bad input.
8. Handover — write the `> Handover:` blockquote and add one line naming the
   interface the slice landed, so later slices do not re-derive it:

   ```markdown
   > Interface: <path> — <entry points>
   ```

   Then mark the header `[x]`. A header `[x]` with no handover stays the
   forbidden state.

## Resume and duplicates

An interrupted slice resumes from its plan lines:

- with `> Frozen:` — resume implementation (step 5) from the working tree;
- no `> Frozen:` line but commits after the slice base — those are the stubs;
  discard uncommitted tests from a stalled run and re-dispatch step 2 against
  the existing stubs;
- a stalled dispatch retries once, then the circuit breaker.

The handover is written once. `slice.py ready` and `check` are idempotent.
