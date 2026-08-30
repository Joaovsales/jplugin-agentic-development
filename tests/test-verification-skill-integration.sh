#!/bin/bash
# Contract for the vendored pstack verification-skill authoring workflow.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CREATOR=.agents/skills/create-verification-skill/SKILL.md
MAINTAINER=.agents/skills/maintain-verification-skill/SKILL.md
EXAMPLE=.agents/skills/create-verification-skill/references/feature-map-example
NOTICE_TEXT="$(awk '/^> MIT License$/ { found=1 }
  found && /^>/ { sub(/^> ?/, ""); print; next }
  found { exit }' THIRD_PARTY_NOTICES.md)"
MIT_LICENSE_BLOB=6b5400237fdf6545be0b8fae370d6f2fcff8fb25

for skill in create-verification-skill maintain-verification-skill; do
  canonical=".agents/skills/$skill/SKILL.md"
  compat=".claude/skills/$skill/SKILL.md"
  frontmatter="$(awk 'NR == 1 && /^---$/ { in_frontmatter=1; next }
    in_frontmatter && /^---$/ { exit }
    in_frontmatter { print }' "$canonical" 2>/dev/null)"
  assert_contains "$frontmatter" "name: $skill" "$skill: valid frontmatter name"
  assert_contains "$frontmatter" "description:" "$skill: description is present"
  assert_contains "$frontmatter" "disable-model-invocation: false" "$skill: model invocation is enabled"
  assert_contains "$frontmatter" "harness: universal" "$skill: harness-neutral registration"
  assert_files_identical "$canonical" "$compat" "$skill: canonical and Claude copies match"
  assert_file_contains ".agents/skills/$skill/LICENSE.pstack" "Copyright (c) 2026 Lauren Tan" \
    "$skill: standalone canonical copy bundles attribution"
  assert_file_contains ".claude/skills/$skill/LICENSE.pstack" "Permission is hereby granted" \
    "$skill: standalone Claude copy bundles the MIT grant"
  assert_files_identical ".agents/skills/$skill/LICENSE.pstack" ".claude/skills/$skill/LICENSE.pstack" \
    "$skill: bundled notices match across trees"
  assert_eq "$NOTICE_TEXT" "$(cat ".agents/skills/$skill/LICENSE.pstack")" \
    "$skill: bundled license matches the complete repository notice"
  assert_eq "$MIT_LICENSE_BLOB" "$(git hash-object ".agents/skills/$skill/LICENSE.pstack")" \
    "$skill: bundled license matches the reviewed MIT text exactly"
done

for section in Launch Doctor Drive Evidence Cleanup Helpers; do
  assert_file_contains "$CREATOR" "**$section:**" "creator: generated skill requires $section"
done
assert_file_contains "$CREATOR" "Surface and capability ceiling" \
  "creator: generated skill declares its surface and capability ceiling"
assert_file_contains "$CREATOR" 'canonical `.agents/skills/` tree' \
  "creator: canonical generated path"
assert_file_contains "$CREATOR" 'compatibility `.claude/skills/` tree' \
  "creator: mirrored generated path"
assert_file_contains "$CREATOR" "byte-identical" "creator: generated trees stay byte-identical"
assert_file_contains "$CREATOR" "top 3-5" "creator: seeds a bounded feature map"
assert_file_contains "$CREATOR" "evidence still exists" "creator: proof survives cleanup"
assert_file_not_matches "$CREATOR" 'TBD|PLACEHOLDER|TODO:' \
  "creator: contains no unfinished authoring placeholders"
assert_file_contains "$CREATOR" "Never kill by process name" \
  "creator: explicitly forbids process-name cleanup"
assert_file_not_matches "$CREATOR" '(^|[[:space:]`])(pkill|killall)([[:space:]`]|$)' \
  "creator: contains no unsafe process-name cleanup command"

FEATURE_LINKS="$(sed -n '/^## Features$/,$p' "$EXAMPLE/README.md" | sed -n 's/.*](\.\/\([^)]*\.md\)).*/\1/p')"
for feature in $FEATURE_LINKS; do
  headings="$(grep '^## ' "$EXAMPLE/$feature" 2>/dev/null)"
  assert_eq "4" "$(printf '%s\n' "$headings" | grep -c '^## ')" \
    "feature example: $feature has exactly four H2 sections"
  assert_eq "## Sub-features" "$(printf '%s\n' "$headings" | sed -n '1p')" \
    "feature example: $feature starts with Sub-features"
  assert_eq "## How to get to it (user POV)" "$(printf '%s\n' "$headings" | sed -n '2p')" \
    "feature example: $feature next documents user entry points"
  assert_contains "$(printf '%s\n' "$headings" | sed -n '3p')" "## Driving it with " \
    "feature example: $feature next documents its driving harness"
  assert_eq "## Gotchas" "$(printf '%s\n' "$headings" | sed -n '4p')" \
    "feature example: $feature ends with Gotchas"
done
assert_file_contains "$EXAMPLE/README.md" "## Features" "feature example: indexed map"
assert_file_contains "$EXAMPLE/README.md" "every user entry point" \
  "feature example: every entry point is independently accounted for"
FEATURE_COUNT="$(printf '%s\n' "$FEATURE_LINKS" | sed '/^$/d' | wc -l)"
if [ "$FEATURE_COUNT" -ge 3 ] && [ "$FEATURE_COUNT" -le 5 ]; then
  assert_eq "bounded" "bounded" "feature example: contains 3-5 indexed entries"
else
  assert_eq "3-5" "$FEATURE_COUNT" "feature example: contains 3-5 indexed entries"
fi
for feature in $FEATURE_LINKS; do
  if [ -f "$EXAMPLE/$feature" ]; then
    assert_eq "exists" "exists" "feature example: indexed target $feature exists"
  else
    assert_eq "exists" "missing" "feature example: indexed target $feature exists"
  fi
done
assert_eq "$(find "$EXAMPLE" -maxdepth 1 -type f -name '*.md' ! -name README.md -printf '%f\n' | sort)" \
  "$(printf '%s\n' "$FEATURE_LINKS" | sort)" \
  "feature example: every feature file is indexed exactly once"

assert_file_contains "$MAINTAINER" "--scope changed" "maintainer: changed-scope mode"
assert_file_contains "$MAINTAINER" "session intent" "maintainer: changed mode consumes session intent"
assert_file_contains "$MAINTAINER" "base-to-HEAD diff" "maintainer: changed mode consumes the diff"
assert_file_contains "$MAINTAINER" "internal-only" "maintainer: changed mode skips internal-only work"
assert_file_contains "$MAINTAINER" "active branch" "maintainer: changed mode edits the active branch"
assert_file_contains "$MAINTAINER" "idempotent" "maintainer: changed mode is idempotent"
assert_file_contains "$MAINTAINER" "count candidates before validating their contents" \
  "maintainer: counts every verify-* candidate before target validation"
assert_file_contains "$MAINTAINER" 'candidate set as `/verify --scope e2e`' \
  "maintainer: shares verify's ambiguity boundary"
assert_file_contains "$MAINTAINER" "one read-only subagent per feature" \
  "maintainer: full mode has independent source coverage"
assert_file_contains "$MAINTAINER" "Exercise every feature" \
  "maintainer: full mode drives every feature"
for outcome in clean changed blocked; do
  assert_file_matches "$MAINTAINER" "^- \\*\\*$outcome\\*\\*" \
    "maintainer: declares exact $outcome outcome"
done
OUTCOMES="$(awk '/^## Outcomes$/ { found=1; next } found && /^## / { exit } found { print }' "$MAINTAINER" \
  | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')"
assert_eq "$(printf '%s\n' clean changed blocked)" "$OUTCOMES" \
  "maintainer: clean, changed, and blocked are the only outcomes"
assert_file_contains "$MAINTAINER" "Only edit" "maintainer: confines edits to verification skill"
assert_file_contains "$MAINTAINER" "does not open a separate PR" \
  "maintainer: changed-scope mode does not own a PR"
assert_file_contains "$MAINTAINER" "at most one PR" \
  "maintainer: full mode owns at most one correction PR"

assert_file_contains THIRD_PARTY_NOTICES.md "MIT License" "provenance: full MIT notice"
assert_file_contains THIRD_PARTY_NOTICES.md "does not declare a license for the repository as a whole" \
  "provenance: MIT scope is limited to derived material"
assert_file_contains THIRD_PARTY_NOTICES.md "Copyright (c) 2026 Lauren Tan" \
  "provenance: upstream copyright"
assert_file_contains THIRD_PARTY_NOTICES.md "https://github.com/cursor/plugins" \
  "provenance: upstream repository"
assert_file_contains THIRD_PARTY_NOTICES.md "pstack/skills/create-verification-skill/SKILL.md" \
  "provenance: creator source path"
assert_file_contains THIRD_PARTY_NOTICES.md "pstack/skills/maintain-verification-skill/SKILL.md" \
  "provenance: maintainer source path"
assert_file_contains THIRD_PARTY_NOTICES.md "68836ddaf5697224520f1847d90cdb90ca8babaa" \
  "provenance: pinned revision"
assert_file_contains README.md "cursor/plugins" "README: pstack source credit"

finish
