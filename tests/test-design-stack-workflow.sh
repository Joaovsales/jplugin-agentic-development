#!/bin/bash
# Planning and build skills must carry the project-owned design contract.
. "$(dirname "$0")/lib.sh"

repo="$(cd "$(dirname "$0")/.." && pwd)"
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'SelectionRequired' 'existing UI requires selection'
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'spatial' 'new UI spatial default'
assert_file_contains "$repo/.agents/skills/prd/SKILL.md" 'backend' 'non-UI bypass'
for planner in plan system-design-planning; do
  skill="$repo/.agents/skills/$planner/SKILL.md"
  assert_file_contains "$skill" 'DESIGN.md' "$planner reads project brief"
  assert_file_contains "$skill" 'design/concepts/<feature>.html' "$planner writes concept"
  assert_file_contains "$skill" 'SHA-256' "$planner binds concept digest"
  assert_file_contains "$skill" 'owner-started' "$planner requires owner review"
  assert_file_contains "$skill" 'localized UI' "$planner allows localized change"
done
finish
