---
type: regex
weight: 1
pattern: "def format_receipt\\s*\\("
match: contains
target:
  source: file
  path: reporting/receipt.py
---
The requested edit exists in the file.
