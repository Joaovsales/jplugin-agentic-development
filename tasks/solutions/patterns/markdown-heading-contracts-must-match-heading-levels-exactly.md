---
title: Markdown heading contracts must match heading levels exactly
date: 2026-08-29
problem_type: pattern
module: tests/test-verification-skill-integration.sh
tags: [testing, markdown, contract-tests, mutation-testing, false-green]
applies_when: writing contract tests that require a Markdown section at a specific heading level or in a specific order
---

A contract test that searches for `## Gotchas` as a substring also accepts
`### Gotchas`. The 2026-08-29 session exposed that false green with a mutation
probe, then changed the test to collect only exact H2 lines and assert the count
and order (`tests/test-verification-skill-integration.sh:50`).

When a document's structure is load-bearing, test the structure rather than a
token contained inside it:

- Anchor the heading level (`^## `), not only the heading text.
- Assert the expected number of peer headings.
- Assert their order when a consumer depends on a fixed schema.
- Mutate the heading level once to prove the test rejects the malformed shape.

This is distinct from a prose-presence assertion: the words can still exist
while the document no longer satisfies the structural contract.
