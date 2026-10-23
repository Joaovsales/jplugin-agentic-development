# Backlog

Judgment-call proposals surfaced by `/tidy` (repo-hygiene routine) that were not
mechanically fixable. One line each; promote to a real task when picked up.

- [ ] CLAUDE.md's Skills table (`## Skills — .agents/skills/`) lists `/graphify`
  alongside real `.agents/skills/` entries, but `graphify` is an external
  pip-installed CLI (see README.md § "Optional — graphify code graph"), not a
  file under `.agents/skills/`. Decide whether to drop the row, move it out of
  the table into prose, or add a footnote marking it as an optional external
  integration.

## From #106 — plan slices and handover (build report follow-ups)

- [ ] `slice.py check` reports the build's own bookkeeping — `tasks/todo.md` and the
  tracker's detail records (`tasks/details/*.md`) — as `undeclared:` on every slice
  that files or hands over, so its exit code is 1 by construction there (observed on
  all four fixture slices in the AC 15 run). Decide whether `check` excludes the plan
  index and the configured detail directory, or whether `/build` declares them.
- [ ] Re-run the AC 15 live walkthrough under an isolated `CLAUDE_CONFIG_DIR` so the
  harness resolves the project-local skills rather than the user-scope copies, with a
  fixture whose two ready slices are each large enough for `/build` to dispatch — the
  first run (`tasks/e2e-log.md`, 2026-09-22) could not observe parallel dispatch or a
  handover consumed across a dispatch boundary. Tighten the AC sentence so
  `DECISIONS CARRIED` is placed in the planning session, where `/plan` prints it.
- [ ] `slice.py` and `registry/index.py` each locate the `## Plan:` block with their own
  scanner (`_find_plan_block` beside the index's row parser) — one span locator shared
  by reader and writer, per `tasks/solutions/patterns/reader-and-writer-must-share-one-span-locator.md`
  (wrap-up review pass 1, SHOULD-FIX `manual`, skipped).
- [ ] `slice.py validate` reports the first refused surface pattern and stops; a spec with
  several bad patterns is fixed one run at a time (wrap-up review pass 2, `advisory`).
  Collect every `SpecPathError` across the table before exiting 2.

## From github-rest-in-sandboxes — quality-gate follow-ups (receipt GO 7b3f8c4e)

- [ ] `registry/providers/base.py` `linked_pr_exclusion_available()` keeps a tri-state
  (None / True / False) beside the per-task `linked_pr_state()` returning `None` for
  "unknown"; after the REST migration the GitHub implementation is a constant `True`, so
  `_select`'s `False` refusal is unreachable for every shipped provider and a caller must
  know both protocols and the "guard with the availability first" ordering (quality-gate
  Phase 4 SHOULD-FIX, `manual`, not applied). Retire the tri-state or fold it into one
  answer.
- [ ] `linked_pr_state`'s return type promotes the stringly-typed `extra` keys
  (`"unresolved_linked_pr": "true"|"false"`, `"merged_linked_pr": "#n"`) to the
  `TrackerProvider` contract; a second tracker writing `"True"` or misspelling a key reads
  as clean in `select_candidates` (Phase 4 SHOULD-FIX, `manual`, not applied). Return a
  small frozen `LinkedPrState` and fold it into `extra` at the boundary.
- [ ] `providers/github.py` `_describe` re-parses the argv `_write`/`_paged` assembled to
  recover method and path for an error message; a new flag on `_write` would make the
  scanner report its value as the path (Phase 4 NITPICK). Pass a label from the call sites.
- [ ] The "reference belongs to this repository" rule is spelled twice around
  `closing_references_in` (`_closes_here` and `closing_references`); let the parser take
  `here=` and answer it once (Phase 4 NITPICK).
- [ ] Two parallel `gh api` REST stacks now exist — `wrap-up-session/scripts/gh_pr.py`
  (`run`/`api`/`ask`/`path`) and `task-registry/.../github.py` (`_run`/`_json`/`_write`/
  `_path`) — plus two GitHub-remote parsers; the next sandbox-proxy quirk lands in one and
  not the other. Decision 8 of `specs/github-rest-in-sandboxes.md` places the PR helper in
  the wrap-up skill, so this may be the accepted price of skill independence (Phase 4
  NITPICK, advisory, owner human): decide, and record the trade-off beside Decision 8.
