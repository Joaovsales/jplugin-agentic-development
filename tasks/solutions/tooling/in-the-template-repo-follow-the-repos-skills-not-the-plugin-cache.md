---
title: In the template repo, follow the repo's own skills, not the installed plugin copy
date: 2026-09-29
problem_type: tooling
module: .agents/skills/, ~/.claude/plugins/cache/jplugin-agentic-development/
tags: [plugin, skills, version-skew, quality-gate, wrap-up]
applies_when: running /quality-gate, /wrap-up-session or another jplugin skill while working inside jplugin-agentic-development itself
---

The `jplugin:` skills that the Skill tool loads come from the plugin cache
(`~/.claude/plugins/cache/jplugin-agentic-development/jplugin/<version>/`). That
copy is pinned to the version you installed. Inside this repository, the working
tree is usually ahead of it. On 2026-09-29 the cached 1.1.0 `/quality-gate` had
three phases and no receipt, while the repo's version had six phases ending in
`receipt.py write`. The cached `/wrap-up-session` still dispatched four review
passes, while the repo's version reuses the quality receipt.

These tests and scripts check the repo's version, not the cache: `receipt.py`,
`closure.py` and `tests/test-instruction-budget.sh`. Following the cached text
therefore produces a wrap-up the repo's own gates reject. Compare before you
follow one:

```bash
diff -q .agents/skills/<skill>/SKILL.md ~/.claude/plugins/cache/jplugin-agentic-development/jplugin/*/.agents/skills/<skill>/SKILL.md
```

If they differ, follow `.agents/skills/<skill>/SKILL.md`.
