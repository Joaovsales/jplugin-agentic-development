#!/bin/bash
. "$(dirname "$0")/lib.sh"

SCRIPT="$(under_test scripts/sync-impact.py)"
SYNC_SKILL="$(under_test .agents/skills/sync/SKILL.md)"
under_test .agents/skills/sync/scripts >/dev/null

REPO="$(fixture_repo)"
cd "$REPO" || exit 1
mkdir -p .agents/skills/sync .agents/git-hooks .claude/skills
cp "$SYNC_SKILL" .agents/skills/sync/SKILL.md
cat > AGENTS.md <<'EOF'
<!-- jplugin-agentic-development:begin -->
Shared rules
<!-- jplugin-agentic-development:end -->
Template-specific rules
EOF
echo old > .claude/skills/retired.txt
echo old > .agents/git-hooks/pre-push
git add . && git commit -qm base
git tag last-sync

echo changed >> AGENTS.md
echo docs > README.md
mkdir -p .claude-plugin .github/workflows app .agents/skills-extra
echo '{"version":"1.2.3"}' > .claude-plugin/plugin.json
echo workflow > .github/workflows/tests.yml
echo code > app/main.py
echo unknown > .agents/skills-extra/example
git add . && git commit -qm other

summarize() {
  "$TEST_PYTHON" "$SCRIPT" "$1" "$2" | "$TEST_PYTHON" -c '
import json, sys
report = json.load(sys.stdin)
for group in ("project_sync", "plugin_only", "other"):
    print(group + ":" + ", ".join(report[group]))
'
}

out="$(summarize last-sync HEAD)"
assert_eq 'project_sync:
plugin_only:.claude-plugin/plugin.json
other:.agents/skills-extra/example, .github/workflows/tests.yml, AGENTS.md, README.md, app/main.py' \
  "$out" "version, external rules, workflow, app and unrecognized paths do not call for a project sync"

git mv .agents/git-hooks/pre-push app/old-hook
git rm -q .claude/skills/retired.txt
"$TEST_PYTHON" -c 'from pathlib import Path; p = Path("AGENTS.md"); p.write_text(p.read_text().replace("Shared rules", "Revised rules"))'
mkdir -p .claude
echo '{}' > .claude/settings.json
git add . && git commit -qm mixed

out="$(summarize HEAD^ HEAD)"
assert_eq 'project_sync:.agents/git-hooks/pre-push, .claude/settings.json, .claude/skills/retired.txt, AGENTS.md
plugin_only:
other:app/old-hook' "$out" "mixed diff includes both sides of a rename, retirement, settings and managed rules"
assert_eq '' "$(git status --porcelain)" "the comparison leaves the worktree and index clean"

run "$TEST_PYTHON" "$SCRIPT" missing HEAD
assert_exit 2 "an unresolved ref refuses to classify"
assert_contains "$output" 'sync-impact: git rev-parse' "the unresolved ref has an actionable diagnostic"

echo 'malformed rules' > AGENTS.md
git add AGENTS.md && git commit -qm malformed
run "$TEST_PYTHON" "$SCRIPT" HEAD^ HEAD
assert_exit 2 "a commit without managed markers refuses to classify"
assert_contains "$output" 'carries no managed block' "the malformed managed block has an actionable diagnostic"

finish
