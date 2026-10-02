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
build="$repo/.agents/skills/build/SKILL.md"
assert_file_contains "$build" 'SelectionRequired' 'build rejects missing existing UI choice'
assert_file_contains "$build" 'ConceptReviewRequired' 'build requires concept approval'
assert_file_contains "$build" 'tasks/design-approvals/<feature>.json' 'build records approval receipt'
assert_file_contains "$build" 'prompt_sha256' 'receipt binds owner prompt'
assert_file_contains "$build" 'frontend-design-validator' 'design validation dispatch'
for agent in frontend-developer frontend-design-validator; do
  assert_file_contains "$repo/.agents/agents/$agent.md" 'DESIGN.md' "$agent reads brief"
  assert_file_contains "$repo/.agents/agents/$agent.md" 'concept' "$agent reads concept"
  assert_file_contains "$repo/.claude/agents/$agent.md" 'DESIGN.md' "$agent Claude mirror reads brief"
  assert_file_contains "$repo/.claude/agents/$agent.md" 'concept' "$agent Claude mirror reads concept"
done
finish
