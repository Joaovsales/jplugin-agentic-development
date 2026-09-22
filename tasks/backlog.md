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
- [ ] `registry/upsert.py` `_link_parent_line` imports `escalation._authoritative_parent`
  lazily inside the function and takes 6 positional parameters (quality-gate Phase 3
  SHOULD-FIX, `manual`, owner agent, not applied). Move the parent-resolution helper
  to a module both sides import and fold the parameters into one request object.
- [ ] Re-run the AC 15 live walkthrough under an isolated `CLAUDE_CONFIG_DIR` so the
  harness resolves the project-local skills rather than the user-scope copies, with a
  fixture whose two ready slices are each large enough for `/build` to dispatch — the
  first run (`tasks/e2e-log.md`, 2026-09-22) could not observe parallel dispatch or a
  handover consumed across a dispatch boundary. Tighten the AC sentence so
  `DECISIONS CARRIED` is placed in the planning session, where `/plan` prints it.
- [ ] `upsert --parent` prints `parent link pending` and exits 0 when the provider is
  unreachable, but nothing records the pending link — the next `upsert` run has no
  reason to retry it (wrap-up review pass 2, SHOULD-FIX `manual`, skipped). Persist the
  pending parent on the local record (`parent:` metadata) so a later apply completes it.
- [ ] `upsert --parent` dry run previews a native link from the provider's capabilities
  while the apply path may land the body locally (`LOCAL_PENDING`) and store the parent
  as metadata instead (wrap-up review pass 3, SHOULD-FIX 75 `manual`, skipped). Decide
  the preview from the same target the apply resolves, or say in the preview that the
  target is decided at apply time.
- [ ] `slice.py` and `registry/index.py` each locate the `## Plan:` block with their own
  scanner (`_find_plan_block` beside the index's row parser) — one span locator shared
  by reader and writer, per `tasks/solutions/patterns/reader-and-writer-must-share-one-span-locator.md`
  (wrap-up review pass 1, SHOULD-FIX `manual`, skipped).
- [ ] `slice.py validate` reports the first refused surface pattern and stops; a spec with
  several bad patterns is fixed one run at a time (wrap-up review pass 2, `advisory`).
  Collect every `SpecPathError` across the table before exiting 2.
