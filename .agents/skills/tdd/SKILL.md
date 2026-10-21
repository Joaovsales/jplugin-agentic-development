---
name: tdd
description: Red-green-refactor for a list of acceptance criteria or a bug's expected behaviour, with Prove-It for bugs (reproduce with a failing test first). Called by /build for each slice and by /debug for its fix step; use directly when asked to do TDD or to write the test first.
argument-hint: "<criteria: AC ids | expected behaviour> [surface: globs]"
disable-model-invocation: false
harness: universal
---

# /tdd — Red, Green, Refactor

The one definition of the TDD rules. `/build` and `/debug` call it; nothing else
restates it.

**Called with** a list of criteria (an AC id, a legacy `TDD:` row, or a bug's
expected behaviour) and a surface (the files you may edit). **Returns** when every
criterion has a test that failed first and now passes, or stops naming the
criterion it could not make fail. The loop, the order and the evidence rules below
are internal — callers name what must be true.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Code written before the test: delete it and start over. Do not keep it as
"reference", do not adapt it, do not look at it.

## The Loop — once per criterion

1. **Red.** Write one test for exactly that criterion, in the project's test
   directory. No implementation yet.
2. **Prove the failure.** Run it. It must fail for the expected reason — the
   behaviour is missing, not an import or setup error. It passes at once: the test
   is wrong or the behaviour exists; investigate before going on. If you cannot
   make it fail, stop and report that criterion.
3. **Green.** Write the minimum code that passes. No extra features, no
   "while I'm here".
4. **Prove the pass.** Run it again. On failure fix only the specific issue.
5. **Refactor.** Clean Code and SOLID per `AGENTS.md`, behaviour unchanged, tests
   re-run green.
6. **Record.** Tick the criterion's row if the caller keeps one; report
   `✓ <criterion> — <what was implemented>`.

Edit only inside the surface; a file you must touch outside it is reported as
`[SURFACE] +<path> | reason: <one sentence>`.

## Prove-It — for bugs

A bug's expected behaviour is the criterion. Reproduce the bug with a failing test
**before** touching the fix: the failure you see is the bug, the pass after the fix
is the proof. A fix with no test that failed first is a guess.

1. Write the test that exhibits the bug; run it and read the failure — it must be
   the reported symptom, not a different error.
2. Fix the root cause, not the symptom.
3. Run the test green, then the surrounding tests, so the fix broke nothing.

## Red flags — stop and start over with a failing test

- Code written before test
- Test written after implementation
- Test passes immediately without implementation
- Can't explain why test failed
- Tests added "later"
- Rationalizing "just this once"
- "I already manually tested it"
- "Keep as reference" or "adapt existing code"

All of these mean: delete the code, start over with a failing test.

## Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Need to explore first" | Fine. Throw away exploration, start with a test. |
| "Test hard = design unclear" | Listen to the test. Hard to test = hard to use. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Manual test faster" | Manual doesn't prove edge cases. |
| "Existing code has no tests" | You're improving it. Add tests. |
| "Just this once" | That's rationalization. |
| "It's about spirit not ritual" | Tests-after ≠ TDD. You get coverage, lose proof. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. Keeping unverified code is debt. |

## When stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the wished-for API. Write the assertion first. |
| Test too complicated | Design too complicated. Simplify the interface. |
| Must mock everything | Code too coupled. Use dependency injection. |
| Test setup is huge | Extract helpers. Still complex? Simplify the design. |

Mock and test-utility pitfalls: `references/testing-anti-patterns.md`.
