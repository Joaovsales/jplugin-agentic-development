---
type: regex
weight: 1
pattern: def tax_for
match: contains
target:
  source: file
  path: orders.py
---
orders.py must define tax_for.
