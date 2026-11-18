---
title: git hash-object on a symlink path hashes the file it points to, not the link git stores
date: 2026-11-18
problem_type: bug
module: .agents/skills/quality-gate/scripts/gate-integrity.py — _working_blobs
tags: [git, hash-object, symlink, content-hash, gate-integrity, false-positive]
symptoms: an unchanged, committed symlink `pytest.ini -> real.txt` was reported `GATE_TAMPERED pytest.ini` (exit 1), which would stop a /build slice; a symlink retargeted at a missing file came out NOT_CHECKED instead of GATE_TAMPERED
root_cause: git records a symlink as a blob whose content is the link's target path, and `git ls-tree` gives that blob id. `git hash-object <path>` and `--stdin-paths` open the path and follow the link, so they hash the target file's bytes — never equal to the stored blob — and fail outright on a dangling link
resolution: fixed — 2026-11-18. A path for which `os.path.islink` is true is hashed as `git hash-object --stdin` of `os.readlink(path)`; regular files keep the batched `--stdin-paths` call. A `core.symlinks=false` checkout writes the link as a plain file holding the target text, which hashes to the same blob, so Windows agrees
---

**Status**: fixed — 2026-11-18
**Regression test**: `tests/test-gate-integrity.sh` § "a symlinked protected file is hashed as its link target" (skipped where `ln -s` makes no symlink)

## Prevention

Any content-hash comparison against `git ls-tree` blob ids must hash a symlink's
target string, not its target's bytes. Check `os.path.islink` before handing a
path to `hash-object`.
