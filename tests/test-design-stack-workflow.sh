#!/bin/bash
# Planning and build skills must carry the project-owned design contract.
. "$(dirname "$0")/lib.sh"

repo="$(cd "$(dirname "$0")/.." && pwd)"
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'SelectionRequired' 'existing UI requires selection'
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'spatial' 'new UI spatial default'
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'backend' 'non-UI bypass'
finish
