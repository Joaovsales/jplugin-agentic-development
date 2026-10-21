---
type: regex
weight: 1
pattern: total_cents
match: contains
target:
  source: file
  path: billing_client.py
---
The fixed client must read the total_cents field.
