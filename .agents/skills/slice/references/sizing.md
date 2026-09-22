# Sizing — one ceiling

Split a slice when any of these hold:

- **files > 8** in its expanded surface
- **systems > 2** touched by its expanded surface
- **ACs > 3** carried by the slice
- it changes a public interface **and** a consumer of it in another system
- its name needs "and"

Files and systems are counted off the **expanded** surface — globs resolved
against the tree — never off the glob patterns themselves.

A **system** is the first path segment, or the second segment under a
container directory (`src`, `lib`, `.agents/skills`, `tests`). A skill's
inventory rows — the skills tables in `CLAUDE.md` and `README.md`, the
session banner line in `.claude/hooks/session-start.sh` — count together as
that skill's one system, not as three separate ones.

A slice over the ceiling is allowed when the `Sizing:` line in § Build Order
names it and says why. It is never silent, and there is no separate
escalation path per rule above — one line covers whichever rule was crossed.

A one-file, one-AC slice is a valid slice on its own; nothing here sets a
minimum. Every slice is measured against the one ceiling above — none is
sorted into a size bucket first.
