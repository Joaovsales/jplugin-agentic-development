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

# --- an unchanged link does not hide a changed referent ---------------------
R="$(gi_repo)"
mv "$R/tests/expected-failures.txt" "$R/known-failures"
printf '[pytest]\n' > "$R/actual-pytest-config"
ln -s ../known-failures "$R/tests/expected-failures.txt" 2>/dev/null
ln -s actual-pytest-config "$R/pytest.ini" 2>/dev/null
if [ -L "$R/pytest.ini" ] && [ -L "$R/tests/expected-failures.txt" ]; then
  git -C "$R" add -A && git -C "$R" commit -q -m links
  run gate_in "$R" --base HEAD
  assert_exit 0 "referent: unchanged links and referents exit 0"
  printf 'tests/test-a.sh linux* two is two\n' >> "$R/known-failures"
  printf 'addopts = --ignore=tests\n' >> "$R/actual-pytest-config"
  run gate_in "$R" --base HEAD
  assert_exit 1 "referent: a changed referent behind an unchanged link exits 1"
  assert_contains "$output" "GATE_TAMPERED pytest.ini" "referent: the weakened config behind the link is tampering"
  assert_contains "$output" "GATE_TAMPERED tests/expected-failures.txt" "referent: the grown list behind the link is tampering"
  assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt — tests/test-a.sh linux* two is two" \
    "referent: the row added behind the link is reported"

  R="$(gi_repo)"
  OUT="$(fixture_dir)"
  printf '[metadata]\n' > "$OUT/setup.cfg"
  ln -s "$OUT/setup.cfg" "$R/setup.cfg"
  git -C "$R" add -A && git -C "$R" commit -q -m "outside link"
  run gate_in "$R" --base HEAD
  assert_exit 3 "outside referent: a link out of the repository exits 3"
  assert_contains "$output" "NOT_CHECKED setup.cfg — " "outside referent: names the link"
  assert_contains "$output" "outside the repository" "outside referent: says why"

  R="$(gi_repo)"
  ln -s "$OUT" "$R/config-dir"
  ln -s config-dir/setup.cfg "$R/setup.cfg"
  git -C "$R" add -A && git -C "$R" commit -q -m "directory link"
  run gate_in "$R" --base HEAD
  assert_exit 3 "directory referent: an unsupported directory symlink exits 3"
  assert_contains "$output" "NOT_CHECKED setup.cfg" "directory referent: names the gate instead of following outside"
else
  skip "referent: ln -s made no symlink here (Windows without symlink support)"
fi

# --- a clean filter cannot launder a changed runner -------------------------
R="$(gi_repo)"
SAVED="$(fixture_dir)/run.sh.orig"
cp "$R/tests/run.sh" "$SAVED"
printf 'tests/run.sh filter=hide\n' > "$R/.gitattributes"
git -C "$R" config filter.hide.clean "cat '$SAVED'"
printf '#!/bin/sh\nexit 0\n' > "$R/tests/run.sh"
assert_eq "" "$(git -C "$R" diff --name-only HEAD -- tests/run.sh)" "clean filter fixture: git diff sees no change"
run gate_in "$R" --base HEAD
assert_exit 1 "clean filter: the laundered runner still exits 1"
assert_contains "$output" "GATE_TAMPERED tests/run.sh" "clean filter: names the runner"

# --- a CRLF-only checkout difference is not a change ------------------------
R="$(gi_repo)"
printf '#!/bin/bash\r\nfor f in tests/test-*.sh; do bash "$f"; done\r\n' > "$R/tests/run.sh"
run gate_in "$R" --base HEAD
assert_exit 0 "crlf: line endings alone exit 0"
assert_not_contains "$output" "tests/run.sh" "crlf: the runner is unchanged"

# ===========================================================================
printf '\n--- the protection policy cannot remove itself ---\n'
# ===========================================================================

R="$(gi_repo)"
BASE="$(git -C "$R" rev-parse HEAD)"
printf '# Agents\n<!-- jplugin-agentic-development:end -->\n\nFull suite: bash tests/run.sh\n' > "$R/AGENTS.md"
git -C "$R" commit -q -am "drop the policy"
printf '#!/bin/sh\nexit 0\n' > "$R/tests/run.sh"
printf 'tests/test-a.sh linux* two is two\n' >> "$R/tests/expected-failures.txt"
run gate_in "$R" --base "$BASE"
assert_exit 1 "policy removed: exits 1"
assert_contains "$output" "GATE_TAMPERED tests/run.sh" "policy removed: the base declaration still protects the runner"
assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt — tests/test-a.sh linux* two is two" \
  "policy removed: the base expected-failures file is still read"
assert_contains "$output" "GATE_TAMPERED AGENTS.md — Protected paths: tests/run.sh declared at ${BASE:0:8}, removed" \
  "policy removed: the removed glob is reported"
assert_contains "$output" "GATE_TAMPERED AGENTS.md — Expected failures: tests/expected-failures.txt declared at ${BASE:0:8}, now none" \
  "policy removed: the removed expected-failures declaration is reported"

R="$(gi_repo)"
sed 's#^Expected failures: .*#Expected failures: tests/other.txt#' "$R/AGENTS.md" > "$R/AGENTS.md.new" && mv "$R/AGENTS.md.new" "$R/AGENTS.md"
printf 'Protected paths: src/**\n' >> "$R/AGENTS.md"
printf 'tests/test-a.sh linux* two is two\n' >> "$R/tests/expected-failures.txt"
run gate_in "$R" --base HEAD
assert_contains "$output" "GATE_TAMPERED AGENTS.md — Expected failures: tests/expected-failures.txt declared at" \
  "policy retargeted: the retarget is reported"
assert_contains "$output" "now tests/other.txt" "policy retargeted: names the new target"
assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt" "policy retargeted: the old list is still read"
assert_not_contains "$output" "Protected paths: src/**" "policy widened: a new declaration is not a finding"

# --- linked policy uses the historical referent, not the link text ----------
R="$(gi_repo)"
mkdir -p "$R/config"
mv "$R/AGENTS.md" "$R/config/agent-policy.md"
ln -s config/agent-policy.md "$R/AGENTS.md" 2>/dev/null
if [ -L "$R/AGENTS.md" ]; then
  git -C "$R" add -A && git -C "$R" commit -q -m "linked policy"
  run gate_in "$R" --base HEAD
  assert_exit 0 "linked policy: unchanged policy is clean"
  printf '<!-- jplugin-agentic-development:end -->\n' > "$R/config/agent-policy.md"
  printf 'exit 0\n' >> "$R/tests/run.sh"
  printf 'tests/test-a.sh linux* two is two\n' >> "$R/tests/expected-failures.txt"
  run gate_in "$R" --base HEAD
  assert_exit 1 "linked policy: removing declarations cannot hide tampering"
  assert_contains "$output" "GATE_TAMPERED AGENTS.md" "linked policy: reports removed historical declarations"
  assert_contains "$output" "GATE_TAMPERED tests/run.sh" "linked policy: keeps the historical protected runner"
  assert_contains "$output" "EXPECTED_FAILURE_ADDED tests/expected-failures.txt — tests/test-a.sh linux* two is two" \
    "linked policy: keeps the historical expected-failures list"

  R="$(gi_repo)"
  OUT="$(fixture_dir)/policy.md"
  cp "$R/AGENTS.md" "$OUT"
  rm "$R/AGENTS.md"
  ln -s "$OUT" "$R/AGENTS.md"
  run gate_in "$R" --base HEAD
  assert_exit 3 "current policy link: outside referent is not checked"
  assert_contains "$output" "outside the repository" "current policy link: explains unsupported referent"
  git -C "$R" add AGENTS.md && git -C "$R" commit -q -m "outside policy link"
  rm "$R/AGENTS.md"
  cp "$OUT" "$R/AGENTS.md"
  run gate_in "$R" --base HEAD
  assert_exit 3 "historical policy link: outside referent is not an empty policy"
  assert_contains "$output" "outside the repository" "historical policy link: explains unsupported referent"

  R="$(gi_repo)"
  rm "$R/AGENTS.md"
  ln -s missing-policy.md "$R/AGENTS.md"
  git -C "$R" add AGENTS.md && git -C "$R" commit -q -m "dangling policy link"
  run gate_in "$R" --base HEAD
  assert_exit 3 "dangling policy link: missing referent is not an empty policy"
  assert_not_contains "$output" "gate-integrity: clean" "dangling policy link: never clean"
else
  skip "linked policy: ln -s made no symlink here"
fi

# --- added protection cannot relax an existing gate's Surface precision -----
R="$(gi_repo)"
printf 'exit 0\n' >> "$R/tests/run.sh"
run gate_in "$R" --base HEAD --spec specs/f.md --slice 1
assert_exit 1 "overlapping policy control: broad Surface does not declare the runner"
printf 'Protected paths: tests/**\n' >> "$R/AGENTS.md"
run gate_in "$R" --base HEAD --spec specs/f.md --slice 1
assert_exit 1 "overlapping policy: a new broad glob cannot authorize the runner"
assert_contains "$output" "GATE_TAMPERED tests/run.sh" "overlapping policy: preserves the baseline authorization boundary"
assert_not_contains "$output" "GATE_CHANGED tests/run.sh" "overlapping policy: never downgrades existing tampering"

R="$(gi_repo)"
printf 'Protected paths: src/**\n' >> "$R/AGENTS.md"
printf 'print("changed")\n' > "$R/src/app.py"
run gate_in "$R" --base HEAD --spec specs/f.md --slice 1
assert_exit 0 "new protection: an unrelated new declaration still allows its own Surface"
assert_contains "$output" "GATE_CHANGED src/app.py" "new protection: the newly protected source is checked"
assert_not_contains "$output" "GATE_TAMPERED AGENTS.md" "new protection: unrelated protection is not policy tampering"

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
printf '\n--- each slice is judged against its own snapshot ---\n'
# ===========================================================================

R="$(gi_repo)"
cat > "$R/specs/f.md" <<'EOF'
---
implementation_paths:
  - .github/workflows/**
  - src/**
---
# Spec: f
## Build Order
| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Gates | gates | `.github/workflows/**` | — | 1 | t | s |
| 2 | Code | code | `src/**` | 1 | 2 | t | s |
EOF
git -C "$R" commit -q -am "sequential slice surfaces"
run gate_in "$R" --snapshot
assert_exit 0 "snapshot: exits 0"
S0="$output"
assert_true "snapshot: prints one tree id" grep -Eqx '[0-9a-f]{40}([0-9a-f]{24})?' <<<"$S0"
assert_eq "" "$(git -C "$R" status --porcelain)" "snapshot: leaves the index and the tree untouched"

printf 'on: pull_request\n' > "$R/.github/workflows/ci.yml"
run gate_in "$R" --base "$S0" --spec specs/f.md --slice 1
assert_exit 0 "two slices: the first slice's declared edit exits 0"
assert_contains "$output" "GATE_CHANGED .github/workflows/ci.yml" "two slices: the first slice's edit is GATE_CHANGED"

run gate_in "$R" --snapshot
S1="$output"
assert_eq "" "$(git -C "$R" diff --cached --name-only)" "dirty snapshot: accepted uncommitted work stays unstaged"
printf 'print("slice 1")\n' > "$R/src/app.py"
printf 'on: push\n' > "$R/.github/workflows/new.yml"
run gate_in "$R" --base "$S1" --spec specs/f.md --slice 2
assert_exit 1 "two slices: an undeclared protected file the second slice adds exits 1"
assert_contains "$output" "GATE_TAMPERED .github/workflows/new.yml" "two slices: the second slice's own tamper is caught"
assert_not_contains "$output" "GATE_TAMPERED .github/workflows/ci.yml" \
  "two slices: the first slice's accepted edit is not blamed on the second"
rm "$R/.github/workflows/new.yml"
run gate_in "$R" --base "$S1" --spec specs/f.md --slice 2
assert_exit 0 "two slices: a source-only second slice against its snapshot exits 0"
assert_contains "$output" "gate-integrity: clean" "two slices: clean"

run gate_in "$R" --base "$S0" --spec specs/f.md --slice 2
assert_exit 1 "session base: the same second slice against the session base is blamed"
run gate_in "$R" --base "$S0" --spec specs/f.md --slice 1 --slice 2
assert_exit 0 "parallel batch: --slice repeated takes the union of the batch's surfaces"

# Snapshot the bytes present at dispatch, even when a clean filter lies about them.
R="$(gi_repo)"
SAVED="$(fixture_dir)/run.sh.orig"
cp "$R/tests/run.sh" "$SAVED"
printf 'tests/run.sh filter=hide\n' > "$R/.gitattributes"
git -C "$R" config filter.hide.clean "cat '$SAVED'"
printf '#!/bin/sh\nexit 0\n' > "$R/tests/run.sh"
run gate_in "$R" --snapshot
S_FILTER="$output"
run gate_in "$R" --base "$S_FILTER"
assert_exit 0 "snapshot filter: unchanged working bytes match their dispatch snapshot"
assert_contains "$output" "gate-integrity: clean" "snapshot filter: raw snapshot is clean"

# --- committed submodules retain their gitlink IDs in the snapshot ----------
R="$(gi_repo)"
DEP="$(fixture_repo)"
printf 'dependency\n' > "$DEP/dep.txt"
git -C "$DEP" add -A && git -C "$DEP" commit -q -m dependency
DEP_ID="$(git -C "$DEP" rev-parse HEAD)"
git -C "$R" -c protocol.file.allow=always submodule add -q "$DEP" vendor/dep
git -C "$R" add -A && git -C "$R" commit -q -m "add submodule"
run gate_in "$R" --snapshot
assert_exit 0 "submodule snapshot: a clean project with a gitlink succeeds"
if [ "$status" -eq 0 ]; then
  assert_contains "$(git -C "$R" ls-tree "$output" -- vendor/dep)" "160000 commit $DEP_ID" \
    "submodule snapshot: retains the recorded commit ID and mode"
fi
assert_eq "" "$(git -C "$R" status --porcelain)" "submodule snapshot: real index and worktree stay clean"
git -C "$R" submodule deinit -q -f -- vendor/dep
run gate_in "$R" --snapshot
assert_exit 0 "submodule snapshot: a deinitialized gitlink is supported"
if [ "$status" -eq 0 ]; then
  assert_contains "$(git -C "$R" ls-tree "$output" -- vendor/dep)" "160000 commit $DEP_ID" \
    "submodule snapshot: deinitialized gitlink keeps its ID"
fi

R="$(gi_repo)"
rm "$R/src/app.py"
mkdir "$R/src/app.py"
run gate_in "$R" --snapshot
assert_exit 3 "unsupported snapshot type: an ordinary directory replacing a file is refused"
assert_contains "$output" "cannot snapshot non-file src/app.py" "unsupported snapshot type: refusal names the directory"

# A partial symlink read failure must retain findings for other gates.
R="$(gi_repo)"
printf '[pytest]\n' > "$R/actual-pytest-config"
ln -s actual-pytest-config "$R/pytest.ini" 2>/dev/null
if [ -L "$R/pytest.ini" ]; then
  git -C "$R" add -A && git -C "$R" commit -q -m link
  printf 'exit 0\n' >> "$R/tests/run.sh"
  INJECT="$(fixture_dir)/symlink-failure.py"
  cat > "$INJECT" <<'PY'
import importlib.util
import os
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("gate_integrity", sys.argv[1])
gate = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gate
spec.loader.exec_module(gate)
readlink = os.readlink

def partial_failure(path):
    if path.endswith("/pytest.ini"):
        raise OSError("injected symlink read failure")
    return readlink(path)

with patch.object(gate.os, "readlink", side_effect=partial_failure):
    sys.exit(gate.main(["--repo", sys.argv[2], "--base", "HEAD"]))
PY
  run "$PY" "$INJECT" "$GATE" "$R"
  assert_exit 1 "symlink read failure: another tampered gate still takes precedence"
  assert_contains "$output" "NOT_CHECKED pytest.ini" "symlink read failure: names the unreadable link"
  assert_eq 1 "$(printf '%s\n' "$output" | sed -n '/^NOT_CHECKED /p' | wc -l | tr -d ' ')" \
    "symlink read failure: exactly one NOT_CHECKED line"
  assert_contains "$output" "GATE_TAMPERED tests/run.sh" "symlink read failure: keeps other findings"
  assert_not_contains "$output" "Traceback" "symlink read failure: no traceback"
else
  skip "symlink read failure: ln -s made no symlink here"
fi

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

R="$(gi_repo)"
chmod 000 "$R/AGENTS.md"
if [ -r "$R/AGENTS.md" ]; then
  skip "unreadable AGENTS.md: chmod 000 leaves the file readable here (root or Windows)"
else
  run gate_in "$R" --base HEAD
  assert_exit 3 "unreadable AGENTS.md: exits 3, never the tampered 1"
  assert_contains "$output" "gate-integrity: not checked — " "unreadable AGENTS.md: not checked"
  assert_contains "$output" "AGENTS.md" "unreadable AGENTS.md: names the file"
  assert_not_contains "$output" "Traceback" "unreadable AGENTS.md: no traceback"
fi
chmod 644 "$R/AGENTS.md"

run gate_in "$R" --base=--all
assert_exit 3 "option-like base: exits 3"
assert_contains "$output" "not checked — base --all does not resolve" "option-like base: read as a revision, never an option"

# Pin the Git argument boundary rather than relying on a particular Git's response.
BOUNDARY="$(fixture_dir)/revision-boundary.py"
cat > "$BOUNDARY" <<'PY'
import importlib.util
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("gate_integrity", sys.argv[1])
gate = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gate
spec.loader.exec_module(gate)
git = gate._git

def checked_git(repo, *args, **kwargs):
    if args[0] == "rev-parse" and "--verify" in args:
        assert "--end-of-options" in args, args
        assert args.index("--end-of-options") < len(args) - 1, args
    return git(repo, *args, **kwargs)

with patch.object(gate, "_git", side_effect=checked_git):
    gate._resolve_base(sys.argv[2], "HEAD")
PY
run "$PY" "$BOUNDARY" "$GATE" "$R"
assert_exit 0 "revision boundary: --end-of-options precedes the supplied base"

finish
