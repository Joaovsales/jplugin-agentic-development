# tests/test-pre-compact.sh — P1 PreCompact flush hook.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/.agents/hooks/pre-compact.sh"

# --- Case 1: seeded todo.md, dirty tree, custom branch ---
tmp1=$(mktemp -d)
cd "$tmp1"
git init -q && git config user.email t@t && git config user.name t
git checkout -q -b feature-x
mkdir -p tasks
printf '> Spec: specs/demo.md\n\n[~] TDD: in-progress thing -> do it\n[ ] TDD: pending thing -> later\n' > tasks/todo.md
echo scratch > scratch.txt
printf '{"trigger":"auto"}' | bash "$HOOK"
ec=$?
cp1="$tmp1/tasks/checkpoint.md"
assert_eq "0" "$ec" "P1: pre-compact exits 0 on success"
assert_eq "true" "$([ -f "$cp1" ] && echo true || echo false)" "P1: checkpoint.md created"
assert_file_contains "$cp1" "feature-x" "P1: checkpoint records git branch"
assert_file_contains "$cp1" "Checkpoint —" "P1: checkpoint has timestamp header"
assert_file_contains "$cp1" "in-progress thing" "P1: checkpoint records [~] item"
assert_file_contains "$cp1" "pending thing" "P1: checkpoint records [ ] item"
assert_file_contains "$cp1" "specs/demo.md" "P1: checkpoint records active spec"
assert_file_contains "$cp1" "tasks/solutions" "M3: resume steps point at the typed store"
assert_eq "0" "$(grep -c 'tasks/memory.md' "$cp1")" "M3: checkpoint no longer references tasks/memory.md"

# --- Case 2: no todo.md -> git-only state, no crash ---
tmp2=$(mktemp -d)
cd "$tmp2"
git init -q && git config user.email t@t && git config user.name t
printf '{"trigger":"manual"}' | bash "$HOOK"
ec=$?
cp2="$tmp2/tasks/checkpoint.md"
assert_eq "0" "$ec" "P1: pre-compact exits 0 when tasks/todo.md absent"
assert_file_contains "$cp2" "no tasks/todo.md" "P1: git-only checkpoint notes missing todo"

cd "$REPO"
rm -rf "$tmp1" "$tmp2"
finish
