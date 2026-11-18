#!/bin/bash
# tests/test-gate-integrity.sh — .agents/skills/quality-gate/scripts/gate-integrity.py
# (specs/gate-integrity.md): every protected file is compared by content hash
# against its blob at the base commit, so an assume-unchanged edit, a committed
# edit and diff.mnemonicPrefix all still surface; a protected change outside
# the Surface is GATE_TAMPERED (exit 1), one the Surface names is GATE_CHANGED.
. "$(dirname "$0")/lib.sh"

PY="$TEST_PYTHON"
GATE="$(under_test .agents/skills/quality-gate/scripts/gate-integrity.py)"

# gate_in <repo> <args...> — the script with <repo> as cwd.
gate_in() { local repo="$1"; shift; ( cd "$repo" && "$PY" "$GATE" "$@" ); }

# gi_repo — a fixture repo with one commit holding protected runners declared
# in AGENTS.md, a default-protected workflow and pyproject.toml, an existing
# test file, an unprotected source file and a two-slice spec. Prints the path.
gi_repo() {
  local d
  d="$(fixture_repo)" || exit 143
  mkdir -p "$d/tests" "$d/.github/workflows" "$d/src" "$d/specs"
  cat > "$d/AGENTS.md" <<'EOF'
# Agents
<!-- jplugin-agentic-development:begin -->
Protected paths: ignored-above-the-marker.txt
<!-- jplugin-agentic-development:end -->

Full suite: bash tests/run.sh
Protected paths: `tests/run.sh` tests/lib.sh
Expected failures: tests/expected-failures.txt
EOF
  printf '#!/bin/bash\nfor f in tests/test-*.sh; do bash "$f"; done\n' > "$d/tests/run.sh"
  printf 'assert_eq() { [ "$1" = "$2" ]; }\n' > "$d/tests/lib.sh"
  printf '# known failures\ntests/test-old.sh linux* old message\n' > "$d/tests/expected-failures.txt"
  printf '. tests/lib.sh\nassert_eq 1 1 "one is one"\nassert_eq 2 2 "two is two"\n' > "$d/tests/test-a.sh"
  printf 'on: push\n' > "$d/.github/workflows/ci.yml"
  printf '[tool.ruff]\nline-length = 100\n' > "$d/pyproject.toml"
  printf 'print("app")\n' > "$d/src/app.py"
  printf 'notes\n' > "$d/ignored-above-the-marker.txt"
  cat > "$d/specs/f.md" <<'EOF'
---
implementation_paths:
  - src/**
  - tests/**
  - .github/workflows/**
---

# Spec: f

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Code | code | `src/**`, `tests/**` | — | 1 | t | s |
| 2 | Gates | gates | `tests/expected-failures.txt`, `.github/workflows/**` | 1 | 2 | t | s |
EOF
  git -C "$d" add -A
  git -C "$d" commit -q -m base
  printf '%s\n' "$d"
}

# ===========================================================================
printf '\n--- clean and unprotected changes ---\n'
# ===========================================================================

R="$(gi_repo)"
run gate_in "$R" --base HEAD
assert_exit 0 "clean: an unchanged tree exits 0"
assert_contains "$output" "gate-integrity: clean" "clean: summary says clean"

printf 'print("changed")\n' > "$R/src/app.py"
printf 'notes changed\n' > "$R/ignored-above-the-marker.txt"
run gate_in "$R" --base HEAD
assert_exit 0 "unprotected: a source edit and a file declared only above the end marker are not gates"
assert_not_contains "$output" "GATE_" "unprotected: no gate line"

# ===========================================================================
printf '\n--- tampering outside the surface ---\n'
# ===========================================================================

R="$(gi_repo)"
printf 'exit 0\n' >> "$R/tests/run.sh"
run gate_in "$R" --base HEAD
assert_exit 1 "tamper: an uncommitted runner edit with no spec exits 1"
assert_contains "$output" "GATE_TAMPERED tests/run.sh" "tamper: names the backticked declared runner"
assert_contains "$output" "gate-integrity: GATE_TAMPERED (1)" "tamper: summary counts one"

# --- a committed edit: the working tree is clean against HEAD ---------------
R="$(gi_repo)"
BASE="$(git -C "$R" rev-parse HEAD)"
printf 'on: [push, pull_request]\n' > "$R/.github/workflows/ci.yml"
git -C "$R" commit -q -am "weaken ci"
assert_eq "" "$(git -C "$R" status --porcelain)" "committed fixture: the working tree is clean"
run gate_in "$R" --base "$BASE"
assert_exit 1 "committed: an edit committed after the base still exits 1"
assert_contains "$output" "GATE_TAMPERED .github/workflows/ci.yml" "committed: names the default-protected workflow"

# --- assume-unchanged: git diff and git status both print nothing -----------
R="$(gi_repo)"
printf 'assert_eq() { return 0; }\n' > "$R/tests/lib.sh"
git -C "$R" update-index --assume-unchanged tests/lib.sh
assert_eq "" "$(git -C "$R" diff --name-only HEAD)" "assume-unchanged fixture: git diff against the base is empty"
assert_eq "" "$(git -C "$R" status --porcelain)" "assume-unchanged fixture: git status is empty"
run gate_in "$R" --base HEAD
assert_exit 1 "assume-unchanged: the hidden edit still exits 1"
assert_contains "$output" "GATE_TAMPERED tests/lib.sh" "assume-unchanged: names the hidden file"

# --- diff.mnemonicPrefix and diff.noprefix change nothing -------------------
R="$(gi_repo)"
git -C "$R" config diff.mnemonicPrefix true
git -C "$R" config diff.noprefix true
printf 'exit 0\n' >> "$R/tests/run.sh"
run gate_in "$R" --base HEAD
assert_exit 1 "mnemonicPrefix: a runner edit still exits 1"
assert_contains "$output" "GATE_TAMPERED tests/run.sh" "mnemonicPrefix: names the runner"

# --- added, deleted and default-protected files -----------------------------
R="$(gi_repo)"
printf 'on: push\n' > "$R/.github/workflows/new.yml"
rm "$R/tests/lib.sh"
printf '[tool.ruff]\nline-length = 300\n' > "$R/pyproject.toml"
run gate_in "$R" --base HEAD
assert_exit 1 "add/delete: exits 1"
assert_contains "$output" "GATE_TAMPERED .github/workflows/new.yml" "add/delete: a new untracked workflow is tampering"
assert_contains "$output" "GATE_TAMPERED tests/lib.sh" "add/delete: a deleted runner is tampering"
assert_contains "$output" "GATE_TAMPERED pyproject.toml" "add/delete: the default list protects pyproject.toml"
assert_contains "$output" "gate-integrity: GATE_TAMPERED (3)" "add/delete: summary counts three"

# --- a symlinked protected file is hashed as its link target, like git does --
R="$(gi_repo)"
printf '[pytest]\n' > "$R/real-pytest.ini"
ln -s real-pytest.ini "$R/pytest.ini" 2>/dev/null
if [ -L "$R/pytest.ini" ]; then
  git -C "$R" add -A && git -C "$R" commit -q -m link
  run gate_in "$R" --base HEAD
  assert_exit 0 "symlink: an unchanged symlinked protected file exits 0"
  assert_not_contains "$output" "GATE_TAMPERED pytest.ini" "symlink: an unchanged link is not tampering"
  rm "$R/pytest.ini" && ln -s elsewhere.ini "$R/pytest.ini"
  run gate_in "$R" --base HEAD
  assert_contains "$output" "GATE_TAMPERED pytest.ini" "symlink: a retargeted link is tampering"
else
  skip "symlink: ln -s made no symlink here (Windows without symlink support)"
fi

# ===========================================================================
printf '\n--- the surface declares a protected path ---\n'
# ===========================================================================

R="$(gi_repo)"
printf '# a comment\n' >> "$R/tests/expected-failures.txt"
run gate_in "$R" --base HEAD --spec specs/f.md --slice 2
assert_exit 0 "declared: a protected file the slice names exits 0"
assert_contains "$output" "GATE_CHANGED tests/expected-failures.txt" "declared: reported as GATE_CHANGED"
assert_not_contains "$output" "GATE_TAMPERED" "declared: not tampering"

run gate_in "$R" --base HEAD --spec specs/f.md --slice 1
assert_exit 1 "broad surface: tests/** does not declare a protected file"
assert_contains "$output" "GATE_TAMPERED tests/expected-failures.txt" "broad surface: still tampering"

printf 'on: pull_request\n' > "$R/.github/workflows/ci.yml"
run gate_in "$R" --base HEAD --spec specs/f.md
assert_exit 0 "spec alone: the union of every slice's surface declares both files"
assert_contains "$output" "GATE_CHANGED .github/workflows/ci.yml" "spec alone: workflow declared by a glob inside the protected pattern"
assert_not_contains "$output" "EXPECTED_FAILURE_ADDED" "comment row: a comment added to the expected-failures file is not a row"

# ===========================================================================
printf '\n--- expected-failure rows are always reported ---\n'
# ===========================================================================

R="$(gi_repo)"
printf 'tests/test-a.sh linux* two is two\n' >> "$R/tests/expected-failures.txt"
run gate_in "$R" --base HEAD --spec specs/f.md --slice 2
assert_exit 0 "xfail row, declared: exits 0"
assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt — tests/test-a.sh linux* two is two" \
  "xfail row, declared: names the test file and the assertion"
assert_contains "$output" "gate-integrity: findings (2)" "xfail row, declared: GATE_CHANGED and the row are two findings"

run gate_in "$R" --base HEAD
assert_exit 1 "xfail row, undeclared: exits 1"
assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt — tests/test-a.sh linux* two is two" \
  "xfail row, undeclared: the row is reported beside GATE_TAMPERED"

R="$(gi_repo)"
printf 'tests/test-old.sh linux* old message\n# known failures\n' > "$R/tests/expected-failures.txt"
run gate_in "$R" --base HEAD
assert_not_contains "$output" "EXPECTED_FAILURE_ADDED" "reorder: reordered rows add nothing"

# ===========================================================================
printf '\n--- skip markers and deleted assertions in existing tests ---\n'
# ===========================================================================

R="$(gi_repo)"
printf 'def test_x():\n    assert 1 == 1\n' > "$R/tests/test_b.py"
printf 'it("works", () => {\n  expect(1).toBe(1);\n});\n' > "$R/src/widget.test.js"
printf 'class FooTest {\n  @Test void t() {}\n}\n' > "$R/src/FooTest.java"
git -C "$R" add -A
git -C "$R" commit -q -m "more tests"
printf '. tests/lib.sh\nskip "flaky on CI"\nassert_eq 1 1 "one is one"\n' > "$R/tests/test-a.sh"
printf 'import pytest\n@pytest.mark.xfail\ndef test_x():\n    assert 1 == 1\n' > "$R/tests/test_b.py"
printf 'it.only("works", () => {\n  expect(1).toBe(1);\n});\n' > "$R/src/widget.test.js"
printf 'class FooTest {\n  @Disabled\n  @Test void t() {}\n}\n' > "$R/src/FooTest.java"
printf 'skip "new file"\n' > "$R/tests/test-new.sh"
run gate_in "$R" --base HEAD
assert_exit 0 "weakening: findings alone exit 0"
assert_contains "$output" 'SKIP_ADDED tests/test-a.sh:2 — skip "flaky on CI"' "weakening: a lib.sh skip line"
assert_contains "$output" "SKIP_ADDED tests/test_b.py:2 — @pytest.mark.xfail" "weakening: a pytest xfail marker"
assert_contains "$output" 'SKIP_ADDED src/widget.test.js:1 — it.only("works", () => {' "weakening: a .only focus"
assert_contains "$output" "SKIP_ADDED src/FooTest.java:2 — @Disabled" "weakening: a JUnit @Disabled"
assert_contains "$output" 'ASSERTION_DELETED tests/test-a.sh:3 — assert_eq 2 2 "two is two"' \
  "weakening: the removed assertion with its base line"
assert_not_contains "$output" "ASSERTION_DELETED tests/test_b.py" "weakening: an assertion kept in place is not deleted"
assert_not_contains "$output" "tests/test-new.sh" "weakening: a test file new since the base is not an existing test"
assert_contains "$output" "gate-integrity: findings (5)" "weakening: five findings"

R="$(gi_repo)"
printf '. tests/lib.sh\nassert_eq 2 2 "two is two"\nassert_eq 1 1 "one is one"\n' > "$R/tests/test-a.sh"
run gate_in "$R" --base HEAD
assert_exit 0 "moved assertion: exits 0"
assert_not_contains "$output" "ASSERTION_DELETED" "moved assertion: reordering assertions deletes none"

R="$(gi_repo)"
rm "$R/tests/test-a.sh"
run gate_in "$R" --base HEAD
assert_contains "$output" 'ASSERTION_DELETED tests/test-a.sh:2 — assert_eq 1 1 "one is one"' "deleted test file: first assertion"
assert_contains "$output" 'ASSERTION_DELETED tests/test-a.sh:3 — assert_eq 2 2 "two is two"' "deleted test file: second assertion"

# ===========================================================================
printf '\n--- a check that cannot run is never clean ---\n'
# ===========================================================================

R="$(gi_repo)"
run gate_in "$R" --base no-such-rev
assert_exit 3 "unresolvable base: exits 3"
assert_contains "$output" "gate-integrity: not checked — base no-such-rev does not resolve to a commit" "unresolvable base: says why"
assert_not_contains "$output" "clean" "unresolvable base: never clean"

NOGIT="$(fixture_dir)"
run gate_in "$NOGIT" --base HEAD
assert_exit 3 "not a repository: exits 3"
assert_contains "$output" "gate-integrity: not checked — " "not a repository: not checked"

R="$(gi_repo)"
printf 'Protected paths: /etc/passwd\n' >> "$R/AGENTS.md"
git -C "$R" commit -q -am "bad glob"
run gate_in "$R" --base HEAD
assert_exit 3 "invalid glob: exits 3"
assert_contains "$output" "not checked — invalid protected path" "invalid glob: names the cause"
assert_contains "$output" "/etc/passwd" "invalid glob: names the glob"

R="$(gi_repo)"
printf 'exit 0\n' >> "$R/tests/lib.sh"
chmod 000 "$R/tests/lib.sh"
if [ -r "$R/tests/lib.sh" ]; then
  skip "unreadable file: chmod 000 leaves the file readable here (root or Windows)"
else
  run gate_in "$R" --base HEAD
  assert_exit 3 "unreadable file: exits 3"
  assert_contains "$output" "NOT_CHECKED tests/lib.sh — " "unreadable file: names the file"
  assert_contains "$output" "gate-integrity: not checked — 1 file(s) unreadable" "unreadable file: summary"
fi
chmod 644 "$R/tests/lib.sh"

finish
