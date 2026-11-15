---
type: regex
weight: 1
pattern: "(?=[\\s\\S]*gateway/queue\\.py)(?=[\\s\\S]*\\benqueue_dispatch\\b)"
match: contains
target: last_message
---
The response identifies the responsible location.
