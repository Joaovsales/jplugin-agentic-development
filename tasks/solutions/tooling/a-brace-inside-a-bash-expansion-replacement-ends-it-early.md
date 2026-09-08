---
title: A brace inside a ${var:+...} replacement ends the expansion early
date: 2026-09-07
problem_type: tooling
module: tests/test-routine-selectors.sh
tags: [bash, parameter-expansion, test-fixtures, json]
applies_when: building JSON or any brace-bearing text with ${var:+...} or ${var:-...} in bash
---

## The rule

Bash ends a `${...}` expansion at the first unescaped `}` — including one inside
the replacement text. A replacement that itself contains a brace is therefore cut
short, and the remainder is emitted as literal characters.

Build the replacement into a variable **before** the expansion, or escape every
brace inside it.

## What happened

A test fixture generated GitHub issue JSON with an optional extra label:

```bash
printf '... "labels":[{"name":"bug"}%s] ...' "$1" "$2" "$1" \
  "${3:+,{\"name\":\"$3\"}}"
```

The intent was `,{"name":"now"}` when `$3` is set and nothing otherwise. Bash
closed the expansion at the `}` of `\"$3\"}`, so the trailing `}` became a
literal, and every issue rendered as:

```json
"labels":[{"name":"bug"}}]
```

Malformed JSON. The provider rejected the read and `select` exited 1 — surfacing
as a fixture that "selects nothing" rather than as a quoting error, which is what
made it cost time: the failure looked like the feature under test.

Note the empty case is fine, which is why it survives casual testing — only the
branch that actually substitutes is broken.

## The fix

```bash
local extra=""
if [ -n "${3:-}" ]; then extra=",{\"name\":\"$3\"}"; fi
printf '... "labels":[{"name":"bug"}%s] ...' "$1" "$2" "$1" "$extra"
```

## Related

- [[explicit-encoding-at-every-python-io-boundary]] — same family: a boundary
  whose escaping rules differ from the surrounding language's.
