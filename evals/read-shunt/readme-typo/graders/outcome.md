---
type: regex
weight: 1
pattern: recieve
match: not_contains
target:
  source: file
  path: README.md
---
README.md must no longer contain the misspelling.
