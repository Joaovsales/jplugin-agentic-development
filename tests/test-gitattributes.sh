#!/usr/bin/env bash
# tests/test-gitattributes.sh — the append-only registers union-merge; tasks/todo.md does not.
#
# Every open PR appends to the same registers, so each one conflicted with master
# on them. The root .gitattributes dog-foods project-template/.gitattributes:
# union on the logs that only grow, and tasks/todo.md left out on purpose,
# because its rows are ticked and deleted in place and union would keep both the
# open and the closed copy of a row.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

ROOT_ATTRS="$(under_test .gitattributes)"
TEMPLATE_ATTRS="$(under_test project-template/.gitattributes)"

union_paths() { tr -d '\r' < "$1" | awk '$2 == "merge=union" { print $1 }'; }

# merge_registers <register> — a fixture repo carrying the root .gitattributes,
# where master and a branch each append one block to <register>; merges the
# branch into master and leaves the merge's exit in `status`, its text in `output`.
merge_registers() {
  local repo="$1" register="$2"
  [ -n "$repo" ] && [ -d "$repo/.git" ] || _abort "merge_registers: no fixture repo"
  mkdir -p "$repo/tasks"
  cp "$ROOT_ATTRS" "$repo/.gitattributes"
  printf '# Register\n\n## Session Summary — base\n- Completed: base\n' > "$repo/$register"
  git -C "$repo" add -A >/dev/null
  git -C "$repo" commit -qm base
  git -C "$repo" branch -q -M master
  git -C "$repo" switch -qc feature
  printf '## Session Summary — feature\n- Completed: feature\n' >> "$repo/$register"
  git -C "$repo" commit -qam feature
  git -C "$repo" switch -q master
  printf '## Session Summary — master\n- Completed: master\n' >> "$repo/$register"
  git -C "$repo" commit -qam master
  run git -C "$repo" merge --no-edit feature
}

if begin_case "attributes"; then
  root_list="$(union_paths "$ROOT_ATTRS")"
  assert_eq "$(union_paths "$TEMPLATE_ATTRS")" "$root_list" \
    "root .gitattributes union-merges the same registers as project-template/.gitattributes"
  assert_contains "$root_list" "tasks/history.md" "tasks/history.md is union-merged"
  assert_not_contains "$root_list" "tasks/todo.md" "tasks/todo.md is not union-merged"
  assert_file_contains "$TEMPLATE_ATTRS" "under one task-id" \
    "the template says why tasks/todo.md is left out"
fi

if begin_case "union-register"; then
  repo="$(fixture_repo)"
  merge_registers "$repo" tasks/history.md
  assert_exit 0 "two appended Session Summaries in tasks/history.md merge without a conflict"
  merged="$(cat "$repo/tasks/history.md")"
  assert_contains "$merged" "- Completed: feature" "the merged history keeps the branch's block"
  assert_contains "$merged" "- Completed: master" "the merged history keeps master's block"
  assert_not_contains "$merged" "<<<<<<<" "the merged history carries no conflict markers"
fi

if begin_case "todo-not-union"; then
  repo="$(fixture_repo)"
  merge_registers "$repo" tasks/todo.md
  assert_exit 1 "the same append/append on tasks/todo.md still stops for a human"
  assert_contains "$output" "CONFLICT (content): Merge conflict in tasks/todo.md" \
    "the stop names tasks/todo.md"
fi

finish
