# Extract the shared path-glob matcher out of spec-reconcile.py

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: glob-matcher-shared-module
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: .agents/skills/sync/scripts/sync-retire.py carries a `TODO(shortcut):` on `_pattern_to_regex` naming the duplication; .agents/skills/wrap-up-session/scripts/spec-reconcile.py:110-137 implements the same three-token semantics (`*` and `?` non-crossing, `**` crossing) and the same rejection list for absolute, traversing, backslash-separated and unsupported-glob patterns, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

Two scripts now implement the same whole-path glob semantics. They agree today, which is the dangerous state: a fix to one silently widens or narrows only half the surfaces that depend on it, and both are used to decide which files a destructive or bookkeeping operation touches.

## Acceptance Criteria

- [ ] One importable module owns `_pattern_to_regex` and `match_path`
- [ ] Both `sync-retire.py` and `spec-reconcile.py` consume it; neither keeps a copy
- [ ] The differing validation contracts stay separate — a sync-keep pattern must additionally name a syncable root, a spec `implementation_paths` entry must not
- [ ] The module ships inside a syncable path, so downstream projects receive it
- [ ] `tests/test-sync-retirement.sh` and `tests/test-living-spec-reconciliation.sh` both stay green, and the `TODO(shortcut):` marker is removed

## Notes

Deferred from the deterministic-retirement build. `spec-reconcile.py`'s hyphenated
filename makes it importable only through `importlib`, so sharing needs a new
module rather than an import of the existing file.
