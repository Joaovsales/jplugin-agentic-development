---
title: Write skill prose so the static guards can read it — pinned phrases on one line, home paths without the skills token
date: 2026-09-15
problem_type: convention
module: .agents/skills/*/SKILL.md, tests/test-doc-conventions.sh, tests/test-skill-references.sh
tags: [skills, static-pins, test-skill-references, doc-conventions, authoring]
applies_when: writing or rewrapping a SKILL.md that tests/test-doc-conventions.sh pins, or naming a path under ~/.claude/skills or ~/.agents/skills in any skill body
---

## The rule

Two of the suite's static guards read skill prose with line-oriented `grep`, so
the prose has to be shaped for them, not only for a human:

1. **A pinned phrase lives on one line.** `assert_file_contains` in
   `tests/lib.sh` is a literal, single-line `grep -F`. A sentence the pin quotes
   may be rewrapped by an editor so that the phrase straddles a line break, and
   the pin goes RED with the skill's meaning unchanged. When a phrase is pinned,
   keep it intact on one line (bold it if that helps it survive a reflow), or pin
   it through `assert_contains` on the whitespace-collapsed `flatten` output
   instead.
2. **Never write `~/.claude/skills/<name>` or `.claude/skills/<name>` for a
   skill that is not in the tree.** `tests/test-skill-references.sh` extracts
   every `.claude/skills/...` and `.agents/skills/...` token from skill bodies and
   requires the path to exist in the repository; a `~/` prefix does not exempt
   it. An operator-local or downstream-only skill has to be named the other way
   round — `<name> under ~/.claude/skills` — which the token regex does not
   match.

## Why

The `/tidy` build (2026-09-14) hit both in one session:

- The AC-3 pin `neither a producer nor a consumer` failed 2/620 after the
  sentence was rewrapped across two lines; the fix was the wording, not the
  test (`tests/test-doc-conventions.sh`, the `# --- tidy:` block).
- The skill's allowlist named two skills that exist only on the operator's
  machine (`aws-saml2aws-auth`, `prior-year-evidence`). Written as
  `~/.claude/skills/aws-saml2aws-auth` they would have failed the reference
  guard as missing repository paths, because the guard's token regex accepts
  any `.claude/skills/[A-Za-z0-9_./-]+` regardless of prefix.

Both guards are doing their job — the first keeps a documented contract from
silently disappearing, the second keeps a path a skill names from pointing at
nothing — so the accommodation belongs in the prose.

## Related

- [[recursive-grep-over-dot-claude-hits-stale-worktree-checkouts]] — another
  case where a guard's literal grep reaches further than the author expected.
