#!/bin/bash
# tests/test-repo-identity.sh — the repository is jplugin-agentic-development
# everywhere a user or a script can read its name (specs/claude-plugin-manifest.md
# § Repository identity).
#
# WHY THIS EXISTS
#
# The GitHub repository was renamed; 87 occurrences of the old name survived in
# 17 tracked files, including the install path users are told to clone into,
# the CI workflow's clone URL and the Codex hook ids. A rename that stops at the
# remote leaves every later change pinning a name the remote no longer answers
# to except by redirect. This sweep keeps the old name out for good.
#
# `git grep`, not `grep -r`: `.claude/worktrees/` holds other sessions' checkouts
# frozen at older commits, all still carrying the old name, and `grep -r` cannot
# tell them from this tree. History under `tasks/` and `specs/` is exempt — it
# records what was, and rewriting it would forge the record.
#
# The needles are assembled at runtime so this file is not itself a hit, and so
# no allowlist is needed (an allowlist rots one exception at a time).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

OLD_SLUG="coding-agent"; OLD_SLUG="$OLD_SLUG-workflow"
OLD_TITLE="Coding Agent"; OLD_TITLE="$OLD_TITLE Workflow"
NEW_SLUG="jplugin-agentic-development"

hits() {
  git grep -l -e "$1" -- . ':!tasks' ':!specs' 2>/dev/null | paste -sd' ' - || true
}

SLUG_HITS="$(hits "$OLD_SLUG")"
TITLE_HITS="$(hits "$OLD_TITLE")"
assert_eq "" "$SLUG_HITS" \
  "identity: the old repository slug appears in no tracked file outside tasks/ and specs/ (hits: ${SLUG_HITS:-none})"
assert_eq "" "$TITLE_HITS" \
  "identity: the old title-case name appears in no tracked file outside tasks/ and specs/ (hits: ${TITLE_HITS:-none})"

# Non-vacuity: the new name must actually be present where users read it, or an
# empty tree would pass the sweep above.
assert_file_contains README.md "~/$NEW_SLUG" \
  "README: install path is ~/$NEW_SLUG"
assert_file_contains README.md "git remote set-url origin https://github.com/Joaovsales/$NEW_SLUG.git" \
  "README: existing clones are told the one-line remote fix"
assert_file_contains .github/workflows/sync-template.yml "https://github.com/Joaovsales/$NEW_SLUG" \
  "CI sync workflow clones the renamed repository"

# Hook ids travel with their consumers: the installer names the files, the
# Python adapter resolves one of them by name, and the renderer's managed-block
# markers carry the same slug. One rename must reach all three.
for consumer in scripts/install-codex.sh codex/hooks/session_start.py scripts/render-codex.py; do
  assert_file_contains "$consumer" "$NEW_SLUG" \
    "hook ids: $consumer carries the new slug"
done

finish
