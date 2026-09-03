# Backlog

Judgment-call proposals surfaced by `/tidy` (repo-hygiene routine) that were not
mechanically fixable. One line each; promote to a real task when picked up.

- [ ] CLAUDE.md's Skills table (`## Skills — .agents/skills/`) lists `/graphify`
  alongside real `.agents/skills/` entries, but `graphify` is an external
  pip-installed CLI (see README.md § "Optional — graphify code graph"), not a
  file under `.agents/skills/`. Decide whether to drop the row, move it out of
  the table into prose, or add a footnote marking it as an optional external
  integration.
