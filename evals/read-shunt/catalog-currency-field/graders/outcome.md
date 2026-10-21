---
type: regex
weight: 1
pattern: currency
match: contains
target:
  source: file
  path: models.py
---
models.py must define the currency field.
