# Lens: `janitor` — bugs

The `janitor` routine looks for behavior that is wrong today. Its engine is the
project's own proof of correctness, run in full, and the bar to file is a
reproduction this run actually executed.

## Engine

1. **Full test suite.** Run the project's suite once, verbatim, and record the
   command and exit status. Every failing test is a candidate; a test that fails
   on one run and passes on a rerun is a candidate too — flakiness is a bug in the
   test, and it is filed as one with both runs' output.
2. **Verifier full pass.** Invoke `/maintain-verification-skill` with **no**
   `--scope` option — the full source-and-live audit. Its source wave runs inline
   when dispatch is unavailable, one feature at a time; its live pass drives every
   mapped feature under the `/verify --scope e2e` rules. When invoked from
   `/sweep` its ship-or-stop step defers to the caller: the sweep owns the PR, so
   verification map corrections it proved are carried on the sweep branch and
   nothing else is committed by the engine.
3. **Product regressions** the full pass reports are candidates. Features the
   pass could not reach — app failed to launch, fixture absent, credentials
   missing — are coverage gaps with the prerequisite that would reach them.

## Bar

A candidate is filed only with all of:

- A reproduction **executed this run**: the exact command, what was observed,
  what was expected. The last `--reproduction` line is
  `observed: … / expected: …`. For a failing test the command is the test
  runner invocation narrowed to that test.
- Confidence `75` or above, with the `evidence` line quoting the motivating
  output or code with `file:line`.
- A proposed fix as concrete steps and at least one checkable criterion.

Files as `--kind bug`; `MUST-FIX` → `--label now`, `SHOULD-FIX` → `--label next`.
Product code is never edited by this lens.
