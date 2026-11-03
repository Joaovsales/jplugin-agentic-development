# tests/test-pre-compact.sh — P1 PreCompact flush hook.
. "$(dirname "$0")/lib.sh"

HOOK="$(under_test .agents/hooks/pre-compact.sh)"

# precompact <repo> <trigger> — run the hook with <repo> as cwd, the way Claude
# Code does: hook input as JSON on stdin.
precompact() {
  run bash -c 'cd "$1" && printf "{\"trigger\":\"%s\"}" "$2" | bash "$3"' _ "$1" "$2" "$HOOK"
}

# --- Case 1: seeded todo.md, dirty tree, custom branch ---
tmp1="$(fixture_repo)"
git -C "$tmp1" checkout -q -b feature-x
mkdir -p "$tmp1/tasks"
printf '> Spec: specs/demo.md\n\n[~] TDD: in-progress thing -> do it\n[ ] TDD: pending thing -> later\n' > "$tmp1/tasks/todo.md"
echo scratch > "$tmp1/scratch.txt"
precompact "$tmp1" auto
cp1="$tmp1/tasks/checkpoint.md"
assert_exit 0 "P1: pre-compact exits 0 on success"
assert_file_exists "$cp1" "P1: checkpoint.md created"
assert_file_contains "$cp1" "feature-x" "P1: checkpoint records git branch"
assert_file_contains "$cp1" "Checkpoint —" "P1: checkpoint has timestamp header"
assert_file_contains "$cp1" "in-progress thing" "P1: checkpoint records [~] item"
assert_file_contains "$cp1" "pending thing" "P1: checkpoint records [ ] item"
assert_file_contains "$cp1" "specs/demo.md" "P1: checkpoint records active spec"
assert_file_contains "$cp1" "tasks/solutions" "M3: resume steps point at the typed store"
assert_file_not_matches "$cp1" 'tasks/memory\.md' "M3: checkpoint no longer references tasks/memory.md"

# --- Case 2: no todo.md -> git-only state, no crash ---
tmp2="$(fixture_repo)"
precompact "$tmp2" manual
cp2="$tmp2/tasks/checkpoint.md"
assert_exit 0 "P1: pre-compact exits 0 when tasks/todo.md absent"
assert_file_contains "$cp2" "no tasks/todo.md" "P1: git-only checkpoint notes missing todo"

finish
