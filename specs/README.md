# Specs

Feature specifications live here. Created by `/plan` and `/brainstorm`, consumed
by `/build`, and kept true by `/wrap-up-session`.

A spec is a **living contract**: it describes the repository's current, tested
behavior, not the intent someone had before writing the code. Git history
preserves earlier intent, so a reader should never have to reconcile historical
amendments or a stale implementation plan to learn what the code does now.

Each spec states:

- **Behavior** — what the feature does
- **Inputs / Outputs** — data flow
- **Edge Cases** — boundary conditions
- **Acceptance Criteria** — how to verify it works, as ordinary bullets

Acceptance Criteria are bullets rather than checkboxes. A checkbox records an
intention and goes half-ticked forever; these criteria state what is true of the
code, and `/build` tracks completion in `tasks/todo.md` where progress belongs.

## Implementation path metadata

A maintained spec declares its current implementation surface in YAML
frontmatter, so `/wrap-up-session` can find it again when that surface changes:

```yaml
---
implementation_paths:
  - .agents/skills/wrap-up-session/**
  - tests/test-wrap-up-session.sh
---
```

Rules:

- Repository-relative POSIX paths or globs. Never absolute, never `..`.
- Matching is case-sensitive against the whole path. `*` matches zero or more
  characters except `/`, `?` matches exactly one character except `/`, and `**`
  matches zero or more characters including `/`. No other glob syntax is accepted
  — a spec carrying one fails wrap-up loudly rather than silently matching
  nothing.
- Declare the complete current surface, not only the files changed when the spec
  was written. Source, configuration, and tests all qualify when a change to them
  can alter or verify the specified behavior.
- Paths may overlap between specs. The mapping is many-to-many: one changed file
  may select several specs, and all of them are examined.

A spec also carries a human-readable `## Implementation Paths` section explaining
each path's role. **Frontmatter is the matching contract; the section is
explanatory.** They are maintained together and neither substitutes for the other.

## Legacy specs

A spec written before this format carries `## Files Likely Involved` instead.
Those are still valid, and wrap-up falls back to parsing paths out of that
section. Migration is lazy and behavior-driven: a legacy spec is converted only
when reconciliation determines the session actually changed what it describes.
Rewriting one purely to modernise its format would bury a behavioral diff in
formatting noise.
