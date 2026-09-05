---
title: mawk silently never matches a bounded regex interval
date: 2026-09-04
problem_type: tooling
module: tests/test-syncable-paths.sh
tags: [awk, mawk, regex, portability, silent-failure]
applies_when: writing an awk regex in a shell test, especially one that gates or terminates parsing
---

## The rule

`mawk` does not support interval expressions (`{n,m}`). A pattern using one does
not error — it simply never matches, so the guard it implements silently does
nothing.

## How it showed up

Two parsers read the same `## Syncable Paths` doc block: a Python one and an awk
extractor in a pinning test. They were aligned by changing the awk terminator to
`/^#{2,6} /`. The suite stayed green, which looked like confirmation.

Checking directly showed the terminator never fired — awk still emitted a root
declared after a `### Subsection`, while the Python parser stopped there. The
"fix" was a no-op, and the two parsers were still disagreeing.

```
$ awk --version | head -1
mawk 1.3.4 20240123
```

`gawk` supports intervals by default and would have masked this entirely on a
different machine.

## The fix

`/^##+ /` — one-or-more, which is plain ERE and portable. Verified against the
same fixture: awk and the Python parser now return the same root set.

## What generalises

- A green suite after a regex change proves nothing if no test exercises the
  branch the regex guards. Check the regex against a fixture directly.
- `mawk` is the default `awk` on Debian/Ubuntu, so "works on my machine" with
  `gawk` is a real portability trap in shell test suites.
- Prefer `+`/`*` over `{n,m}` in awk unless the bound is load-bearing.
