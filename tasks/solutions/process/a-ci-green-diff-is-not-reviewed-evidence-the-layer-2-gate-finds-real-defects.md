---
title: A CI-green diff is not reviewed evidence; the Layer-2 gate finds real defects
date: 2026-11-16
problem_type: process
module: /quality-gate (Layer 2) and every PR that ships without it
tags: [quality-gate, review, ci, evidence, orchestration]
applies_when: deciding whether a small or docs-heavy PR can skip /quality-gate because CI is green, or when a worker that cannot dispatch reviewers wants to merge first and review later
---

On 2026-11-15/16 the session's PRs (#409, #410, #411, #419, #424, #425, #426,
#427, #430) each went through a Layer-2 gate. The coordinator reported that
the gate found real defects on every PR, not style nits. The ones checked
against the record:

- **Vacuous test assertion** (#419, label 419-A in
  `docs/bonsai-2-27b/eval/README.md`): the version-guard regression test
  compared equal versions, so it passed whichever way the old/new values
  were ordered and proved nothing.
- **False comment** (#409, label 409-B): said a `jq` merge would overwrite
  local pins. A key merge does not overwrite them.
- **Duplicated logic** (#409, label 409-A): two copies of the same JSON-fence
  parser in one diff.
- **Container claims and isolation** (#411, labels 411-A to 411-M; follow-up
  #426): base images pinned only by tag, `--cache-ram` equal to `mem_limit`,
  and an overstated claim that a compose `command:` cannot override the
  hardening. #411 merged before its gate ran ("the quality-gate reviewers
  were not run", PR body). #426 then had to seal egress. Its own testing
  showed that `internal: true` alone still left the host's bridge gateway
  reachable, so the fix publishes the port through a relay and binds only
  `127.0.0.1:18080`.
- **Unit error inside a fitness argument** (reported by the coordinator; the
  PR body does not name it): a GB value labelled GiB, in a table whose only
  purpose was to argue whether a model fits in VRAM.
- **Fourth malformed-row failure mode** (#427): an embedded line break in a
  title or summary lost the task id when the row was read back, so the next
  upsert appended a duplicate row.

The four PRs scored in the local-reviewer eval (#409, #410, #411, #419)
carry **26 labelled findings** between them (see
[the local-reviewer result](../architecture/local-reviewer-tier-is-not-fit-and-a-smoke-test-is-not-an-adequacy-test.md)).

**Rule.** Green CI shows only that the tests pass, and these defects were
in the tests, the comments and the docs. Run the gate before merging, even
on docs-only and test-only PRs. A worker that cannot dispatch reviewers
hands the gate to its orchestrator; it does not merge and record
"review pending".

**Consequence of skipping.** #411 merged unreviewed and needed a second
PR (#426) to close two SHOULD-FIX findings on a security-relevant container.
