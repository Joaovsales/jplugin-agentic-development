---
title: The plugin version guard is only as current as origin/master in the tree that runs it
date: 2026-10-16
problem_type: process
module: tests/test-plugin-manifest.sh § version_base; .claude-plugin/plugin.json
tags: [plugin, versioning, version-guard, origin-master, wsl, pre-push, ci]
applies_when: a branch changes anything under `.agents/skills`, `.agents/hooks`, `.agents/references` or `hooks`, and the pre-push full suite runs in a clone or worktree copy rather than the checkout that tracks GitHub
---

## The plugin version guard is only as current as origin/master in the tree that runs it

**Claim**: `tests/test-plugin-manifest.sh` compares the tree with the merge base
of `HEAD` and `refs/remotes/origin/master` (`version_base`,
`tests/test-plugin-manifest.sh:163-170`), skips when no such ref exists and
honours `PLUGIN_VERSION_BASE` over both. On 2026-10-16 the HyperFrames branch
changed `.agents/skills/design-stack/**` without bumping
`.claude-plugin/plugin.json`; the pre-push suite ran green in a WSL clone whose
`origin` was the Windows checkout and whose `origin/master` was months old, so
the guard reported `ok: 1.1.0 -> 1.6.4` and passed. CI, with `fetch-depth: 0`
and the real base 080484d, failed the one assertion: `payload changed since
080484d but version went '1.6.4' -> '1.6.4'` (PR #289, one repair round).

**Rule**:
- A change under the payload paths is a release: bump `version` in
  `.claude-plugin/plugin.json` in the same branch (README § *Releasing skills*).
  Check it before the push, not after CI — `git diff --quiet <merge-base> --
  .agents/skills .agents/hooks .agents/references hooks` non-zero means a bump
  is due.
- A suite run in any tree other than the GitHub-tracking checkout proves the
  guard only if that tree's `origin/master` is current: fetch it first
  (`git fetch origin +refs/remotes/origin/master:refs/remotes/origin/master` from
  a clone of the local checkout). `PLUGIN_VERSION_BASE` is for one targeted run
  of `tests/test-plugin-manifest.sh`, never exported around the whole suite — it
  also overrides the base inside the test's fixture repositories and fails three
  of its own assertions (observed 2026-10-16).
- Read the guard's own `ok:` line in the log (`ok: <old> -> <new>`): an `old`
  far below the current release means the base is stale and the pass is void.

**Consequence of ignoring it**: a green local suite, a red CI run on the one
test that cannot pass without a version bump, and a closure-repair round that
re-enters the receipt, the suite and the push.

Related: [derive-plugin-payload-coverage-from-plugin-root-reads](../patterns/derive-plugin-payload-coverage-from-plugin-root-reads.md),
[a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux](a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md),
[cached-suite-keys-on-the-verbatim-command-so-parallelism-comes-from-the-environment](../tooling/cached-suite-keys-on-the-verbatim-command-so-parallelism-comes-from-the-environment.md).
