---
title: git hash-object on a symlink path hashes the file it points to, not the link git stores
date: 2026-11-18
problem_type: bug
module: .agents/skills/quality-gate/scripts/gate-integrity.py — _Contents.current, _Contents.base_effective
tags: [git, hash-object, symlink, content-hash, gate-integrity, false-positive]
symptoms: an unchanged, committed symlink `pytest.ini -> real.txt` was reported `GATE_TAMPERED pytest.ini` (exit 1), which would stop a /build slice; a symlink retargeted at a missing file came out NOT_CHECKED instead of GATE_TAMPERED
root_cause: git records a symlink as a blob whose content is the link's target path, and `git ls-tree` gives that blob id. `git hash-object <path>` and `--stdin-paths` open the path and follow the link, so they hash the target file's bytes — never equal to the stored blob — and fail outright on a dangling link
resolution: fixed — 2026-11-19. Compare link text and effective content against the base tree, using raw-byte Git blob hashes computed in-process; outside-repository and directory-link referents are NOT_CHECKED. Snapshot creation uses filter-free hashes and a scratch index
---

**Status**: fixed — 2026-11-18
**Regression test**: `tests/test-gate-integrity.sh` § "a symlinked protected file is hashed as its link target" (skipped where `ln -s` makes no symlink)

## Prevention

Any integrity comparison against `git ls-tree` blob ids must compare a
symlink's target string *and* the content it resolves to, and must hash raw
bytes itself rather than through `git hash-object` (see the follow-up below).

## Follow-up — 2026-11-18, review of PR #447

Hashing only the link text was itself incomplete: an unchanged link then hid a
changed referent (a grown expected-failures list, a weakened `pytest.ini`). A
link is now compared twice — link text, and the content it resolves to,
followed through the base tree on one side and the working tree on the other;
a link leaving the repository is NOT_CHECKED. The same review found that
`git hash-object` itself is the wrong primitive for an integrity check: it runs
the clean filter `.gitattributes` names, which can return the original bytes
for a rewritten runner. Blob ids are now computed in-process
(`sha1/sha256("blob <len>\0" + bytes)`), with CRLF-as-LF the only accepted
normalization. Regression tests: `tests/test-gate-integrity.sh` § "an unchanged
link does not hide a changed referent" and § "a clean filter cannot launder a
changed runner".

The re-review also found policy discovery reading a historical `AGENTS.md`
symlink's link-text blob as instructions, silently losing the baseline policy.
Gate contents and policy discovery now share `_Contents` resolution in both
historical and working trees. A missing, outside or unsupported policy
referent is not checked; it never becomes an empty policy. Regression:
`tests/test-gate-integrity.sh` sections `linked policy`, `current policy link`,
`historical policy link` and `dangling policy link`.
