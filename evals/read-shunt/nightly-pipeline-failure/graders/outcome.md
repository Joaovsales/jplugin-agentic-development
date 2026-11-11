---
type: regex
weight: 1
pattern: release_tag[\s\S]*publish_manifest|publish_manifest[\s\S]*release_tag
match: contains
target: last_message
---
The answer must name the missing release_tag key and the publish_manifest function.
