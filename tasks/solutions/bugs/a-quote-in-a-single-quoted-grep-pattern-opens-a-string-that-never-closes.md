---
title: A quote character inside a single-quoted grep -E pattern opens a string that never closes
date: 2026-10-25
problem_type: bug
module: tests/test-model-tiers.sh § 11 (the absence sweep for the Pi inherit directive); tests/lib.sh assert_sweep_empty
tags: [bash, quoting, grep, tests, syntax-error, character-class, tmpdir]
symptoms: `bash -n tests/test-model-tiers.sh` failed with `syntax error near unexpected token '('` reported at a line *20 lines below* the real fault; running the suite printed no assertions at all. Truncating the file at each line number localised it — a prefix ending at 240 parsed clean, a prefix ending at 245 reported `unexpected EOF while looking for matching \`"'\`` at the line holding the grep pattern
root_cause: The pattern needed a character class containing both quote characters and was written as `'...[["'"']?inherit'`. Character by character the sequence is `[`, `"`, `'`, `"`, `'`, `]` — so the single quote after `["` closes the outer single-quoted string, the `"` that follows **opens a double-quoted string**, and the remaining `'` `]?inherit` `'` are all inside it. No second `"` appears before end of line, so the double-quoted string is unterminated and bash consumes the following lines looking for its close, which is why the reported line drifted. The intended idiom for embedding a literal single quote is `'"'"'`, and it was written `"'"` without the closing double quote
resolution: fixed — 2026-10-25. The pattern was rewritten to avoid quote characters entirely: `grep -rlE '^[[:space:]]*model:.*inherit' -- "$tree"`, which matches `model: inherit`, `model: "inherit"` and `model: 'inherit'` alike. The guard's positive control (`assert_sweep_empty` verifies the pattern matches its fixture before sweeping, `tests/lib.sh:576`) still passes, so the rewrite did not quietly neuter the check
---

**Status**: fixed — 2026-10-25
**Regression test**: `tests/test-model-tiers.sh` § 11 — `ModelTier: no Pi-only inherit directive under .agents`, which fails 2 assertions when `model: inherit` is appended to `.agents/agents/code-reviewer.md`

## Prevention

Never put a quote character inside a single-quoted `grep -E` pattern. Reach for a
wildcard instead — `.*` or `[^[:alnum:]]` — because the pattern's job is to match
the line, and a line that starts with `model: ` and contains `inherit` is the
thing being hunted. When a quote really is unavoidable, the working idiom is
`'"'"'` (single-quote, double-quote, single-quote, double-quote, single-quote) and
it is worth pasting rather than retyping.

The diagnostic that mattered: **`bash -n` reports the line where the parser gives
up, not the line that broke.** Binary-searching with `head -N file | bash -n`
found the real line in two probes. A whole test suite silently printing nothing is
the same signal — read it as a parse failure of the file, not as a test failure.

Related: `git-show-ref-colon-path-is-rewritten-by-msys-in-git-bash-hooks.md` and
`grep-end-of-options-before-exclude-dir-drops-the-exclusions.md` are the same
family — a shell one-liner whose failure mode is an empty result rather than an
error, in a check that then reports green.
