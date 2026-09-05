# Adjacent unbounded quantifiers make the glob matcher hang

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: glob-matcher-redos
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `out.append(".*")` for `**` and `out.append("[^/]*")` for `*` in `_pattern_to_regex` (`.agents/skills/sync/scripts/sync-retire.py`); security review reproduced a hang exceeding an 8s alarm on a 70-char non-matching path for patterns `'**?' x9`, `'*?' x12` and `'**' x18`, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

Glob tokens are emitted verbatim, so runs of `**` or `*?` compile to `.*.*.*…` — catastrophic backtracking on a non-matching path. `match_path` runs once per pattern per project-only path with no cache, before any deletion, so a pathological sync-keep hangs `/sync` indefinitely rather than failing.

Severity is bounded: the input is the project's own `.claude/sync-keep`, which is never synced, so this is self-inflicted or requires repo write access.

Deliberately not fixed in the deterministic-retirement build: the same shape exists in `scripts/spec-reconcile.py`, and fixing one copy while the other keeps the defect is how the two silently diverge. This should land with — or after — [[glob-matcher-shared-module]].

## Acceptance Criteria

- [ ] Adjacent unbounded quantifiers cannot produce a regex that backtracks catastrophically
- [ ] A pathological pattern fails fast or matches promptly; it never hangs
- [ ] The fix lands in one place, not once per script
- [ ] `spec-reconcile.py` gets the same behaviour, not a second implementation of it
- [ ] A timing-bounded regression test covers the reproduced patterns

## Notes

Found in security review of the deterministic-retirement build (`autofix_class: manual`, `owner: human` — the judgement is about sequencing against the shared-matcher extraction). Related: [[glob-matcher-shared-module]].
