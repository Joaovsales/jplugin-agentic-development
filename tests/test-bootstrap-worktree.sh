# tests/test-bootstrap-worktree.sh — bootstrap-worktree.sh creates an agent
# worktree and gives it what a bare `git worktree add` leaves out: node_modules
# (linked) and the gitignored .env* files (copied). Every run is in a fixture
# repo with an explicit worktree path inside the fixture, so the checkout this
# suite runs from is never touched. Each worktree is removed before `finish`.
. "$(dirname "$0")/lib.sh"

SCRIPT="$(under_test .agents/skills/build/scripts/bootstrap-worktree.sh)"

# bootstrap <repo> <arg...> — run the script with <repo> as cwd.
bootstrap() {
  local repo="$1"; shift
  run bash -c 'cd "$1" && shift && exec bash "$@"' _ "$repo" "$SCRIPT" "$@"
}

# main_repo — a fixture repo with one commit; untracked files are added by the case.
main_repo() {
  local repo
  repo="$(fixture_repo)" || exit 143
  echo base > "$repo/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  printf '%s\n' "$repo"
}

# drop_worktree <repo> <path> <label> — `git worktree remove --force`, then prove it is gone.
drop_worktree() {
  git -C "$1" worktree remove --force "$2" >/dev/null 2>&1
  assert_file_absent "$2" "Cleanup: worktree $3 removed"
}

# ── Full layout: new branch, node_modules, .env files ────────────────────────
MAIN="$(main_repo)"
BOX="$(fixture_dir)"
mkdir -p "$MAIN/node_modules/dep"
echo pkg > "$MAIN/node_modules/dep/index.js"
echo "KEY=1" > "$MAIN/.env"
echo "KEY=local" > "$MAIN/.env.local"
echo "KEY=example" > "$MAIN/.env.example"
WT="$BOX/wt-full"
bootstrap "$MAIN" feat/x "$WT"
assert_exit 0 "Full: exits 0"
assert_contains "$output" "linked  node_modules -> " "Full: reports the node_modules link"
assert_contains "$output" "copied  2 env file(s)" "Full: copies .env and .env.local, not the .env.example"
assert_contains "$output" "worktree ready: $(cd "$WT" && pwd)" "Full: names the worktree path"
assert_contains "$output" "branch: feat/x" "Full: names the branch"
assert_file_exists "$WT/a.txt" "Full: the worktree holds the tracked files"
assert_eq "feat/x" "$(git -C "$WT" branch --show-current)" "Full: the worktree is on the new branch"
assert_file_exists "$WT/node_modules/dep/index.js" "Full: node_modules resolves inside the worktree"
assert_file_contains "$WT/.env" "KEY=1" "Full: .env is copied with its content"
assert_file_contains "$WT/.env.local" "KEY=local" "Full: .env.local is copied with its content"
assert_file_absent "$WT/.env.example" "Full: .env.example is not copied"
drop_worktree "$MAIN" "$WT" "full"

# ── Existing branch is reused, not recreated ─────────────────────────────────
git -C "$MAIN" branch existing
WT="$BOX/wt-existing"
bootstrap "$MAIN" existing "$WT"
assert_exit 0 "Existing branch: exits 0"
assert_eq "existing" "$(git -C "$WT" branch --show-current)" "Existing branch: the worktree checks it out"
drop_worktree "$MAIN" "$WT" "existing"

# ── Default path: ../<repo>-<branch-slug> ────────────────────────────────────
bootstrap "$MAIN" feat/y
assert_exit 0 "Default path: exits 0"
WT="$(dirname "$MAIN")/$(basename "$MAIN")-feat-y"
assert_file_exists "$WT/a.txt" "Default path: the worktree is ../<repo>-<branch with / as ->"
drop_worktree "$MAIN" "$WT" "default-path"

# ── Nothing to link or copy: the documented skip and warning ─────────────────
BARE="$(main_repo)"
WT="$BOX/wt-bare"
bootstrap "$BARE" feat/z "$WT"
assert_exit 0 "Bare main: exits 0"
assert_contains "$output" "skipped node_modules (absent in" "Bare main: says node_modules was skipped"
assert_contains "$output" "WARNING no .env* found in" "Bare main: warns that no .env* was found"
assert_file_absent "$WT/node_modules" "Bare main: no node_modules appears in the worktree"
drop_worktree "$BARE" "$WT" bare

# ── --detach-head: pinned to HEAD, no branch ─────────────────────────────────
WT="$BOX/wt-detached"
bootstrap "$MAIN" --detach-head "$WT"
assert_exit 0 "--detach-head: exits 0"
assert_contains "$output" "detached at HEAD $(git -C "$MAIN" rev-parse --short HEAD)" "--detach-head: names the pinned commit"
assert_eq "" "$(git -C "$WT" branch --show-current)" "--detach-head: no branch is checked out"
assert_eq "$(git -C "$MAIN" rev-parse HEAD)" "$(git -C "$WT" rev-parse HEAD)" "--detach-head: the worktree is at the main HEAD"
drop_worktree "$MAIN" "$WT" "detached"

# ── Refusals ─────────────────────────────────────────────────────────────────
bootstrap "$MAIN"
assert_exit 1 "No arguments: refused"
assert_contains "$output" "usage: bootstrap-worktree.sh" "No arguments: prints the usage"

bootstrap "$MAIN" --detach-head
assert_exit 1 "--detach-head without a path: refused"
assert_contains "$output" "--detach-head requires a path" "--detach-head without a path: says so"

mkdir -p "$BOX/taken"
bootstrap "$MAIN" feat/q "$BOX/taken"
assert_exit 1 "Path already exists: refused"
assert_contains "$output" "path already exists:" "Path already exists: says so"
assert_eq "" "$(git -C "$MAIN" branch --list feat/q)" "Path already exists: no branch is created"

bootstrap "$(fixture_dir)" feat/q "$BOX/elsewhere"
assert_exit 1 "Outside a repository: refused"
assert_contains "$output" "not a git repository" "Outside a repository: says so"

finish
