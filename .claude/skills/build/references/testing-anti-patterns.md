# Testing Anti-Patterns Reference

## Core Principle

"Test what the code does, not what the mocks do."

## 1. Testing Mock Behavior Instead of Real Behavior

**Problem:** Asserting on mock existence rather than actual component functionality.

**Fix:** Test real behavior or remove the mock. Mocks isolate dependencies — they are never the subject of assertions.

## 2. Test-Only Methods in Production Code

**Problem:** Adding methods solely for test cleanup pollutes production code with non-production concerns.

**Fix:** Move test utilities to dedicated test helper modules. Production code must not contain test-only surface area.

## 3. Mocking Without Understanding Dependencies

**Problem:** Over-mocking without grasping what a dependency actually does breaks test logic and masks real integration failures.

**Fix:** Understand each dependency first. Mock minimally. Preserve necessary side effects so tests reflect real behavior.

## 4. Incomplete Mock Objects

**Problem:** Partial mock objects hide structural assumptions and fail silently when the real API changes shape.

**Fix:** Always mirror complete real API responses in mocks. If the real object has 10 fields, the mock has 10 fields.

## 5. Integration Tests as Afterthought

**Problem:** Integration testing becomes an optional final step added after implementation is complete.

**Fix:** Follow TDD from the start — write tests first at every level, including integration.

## Red Flags

- Mock setup exceeds 50% of test code
- Methods called only in tests exist in production code
- Unable to explain why a specific mock is necessary
- Tests pass but production breaks

## Prevention

Strict TDD prevents most anti-patterns. Writing tests first forces you to think about what you are actually testing before mocks are introduced.
