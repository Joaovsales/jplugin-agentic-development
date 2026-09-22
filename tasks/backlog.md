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
