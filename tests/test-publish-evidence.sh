#!/usr/bin/env bash
# tests/test-publish-evidence.sh — publish_evidence.py pushes e2e screenshots to an
# orphan `e2e-evidence` branch and prints the PR-body section that embeds them.
#
# WHY THIS EXISTS
#
# A VISUAL acceptance criterion passes only with a PNG on disk, and a reviewer can
# only see that PNG if it is reachable from the PR. The publisher puts it on a
# branch that shares no history with the feature branch, so the images never land
# on master. Four properties are load-bearing and each fails silently if broken:
#   - the feature branch (HEAD, index, working tree) is never touched, otherwise a
#     wrap-up push would carry screenshots or a dirty index into the PR;
#   - the evidence branch only grows and is never force-pushed, because merged PRs
#     link to its commits and a rewrite would break every link;
#   - a project can opt out (`E2E evidence: local`) or sit on a non-GitHub host,
#     and then NOTHING is pushed — privacy is not on the chopping block;
#   - a publish race (another session pushed first) is retried once, and a second
#     failure is loud, not swallowed.
#
# Fixtures are bare-repo remotes under mktemp; origin LOOKS like GitHub through
# `url.<bare>.insteadOf`, so the parser sees the raw URL and the push goes local.
# A `gh` stub keeps the visibility probe off the network, and a `git` shim on PATH
# advances the remote between fetch and push to reproduce the race for real.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$REPO/.agents/skills/wrap-up-session/scripts/publish_evidence.py"
REAL_GIT="$(command -v git)"
export REAL_GIT

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

# gh stub: prints $GH_PRIVATE (true/false) for `gh api ...`; fails when unset.
STUBS="$T/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/gh" <<'STUB'
#!/bin/sh
[ -n "$GH_PRIVATE" ] || exit 1
echo "$GH_PRIVATE"
STUB
chmod +x "$STUBS/gh"
export GH_PRIVATE=true

# Race shim: on `git push`, a competing publisher advances the remote first.
SHIM="$T/shim"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<'STUB'
#!/bin/bash
[ -n "$CALL_LOG" ] && printf '%s\n' "$*" >> "$CALL_LOG"
if [ -n "$PUSH_ENV_LOG" ] && { [ "$1" = push ] || { [ "$1" = -C ] && [ "$3" = push ]; }; }; then
  printf 'LC_ALL=%s\n' "$LC_ALL" >> "$PUSH_ENV_LOG"
fi
if [ "$1" = push ] || { [ "$1" = -C ] && [ "$3" = push ]; }; then
  if [ "$RACE_MODE" = always ] || { [ "$RACE_MODE" = once ] && [ ! -e "$RACE_MARK" ]; }; then
    : > "$RACE_MARK"
    PATH="$ORIG_PATH" bash "$COMPETE" >/dev/null 2>&1 || exit 97
  fi
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$SHIM/git"
cat > "$T/compete.sh" <<'STUB'
#!/bin/bash
# Another session publishing to e2e-evidence: a commit on the current remote tip.
g() { "$REAL_GIT" "$@"; }
cd "$OTHER" || exit 1
unset GIT_INDEX_FILE
tip="$(g ls-remote origin refs/heads/e2e-evidence | cut -f1)"
if [ -n "$tip" ]; then
  g fetch -q origin e2e-evidence
  g -c advice.detachedHead=false checkout -q -B e2e-evidence FETCH_HEAD
else
  g checkout -q --orphan e2e-evidence
  g rm -rfq . 2>/dev/null || true
fi
echo other > "other-$RANDOM.png"
g add -A
g commit -qm "competing publisher"
g push -q origin HEAD:refs/heads/e2e-evidence
STUB
export ORIG_PATH="$PATH" COMPETE="$T/compete.sh"

# new_fixture <name> — bare remote + feature repo whose origin reads as GitHub.
new_fixture() {
  BARE="$T/$1/remote.git"; WORK="$T/$1/work"; OTHER="$T/$1/other"; export OTHER
  RACE_MARK="$T/$1/race.mark"; export RACE_MARK
  mkdir -p "$T/$1"
  "$REAL_GIT" init -q --bare "$BARE"
  "$REAL_GIT" init -q -b main "$WORK"
  printf 'tasks/e2e-artifacts/\n' > "$WORK/.gitignore"
  ( cd "$WORK" && echo hi > app.txt && "$REAL_GIT" add -A && "$REAL_GIT" commit -qm init \
    && "$REAL_GIT" remote add origin https://github.com/acme/widgets.git \
    && "$REAL_GIT" config "url.$BARE.insteadOf" https://github.com/acme/widgets.git )
  "$REAL_GIT" clone -q "$BARE" "$OTHER" 2>/dev/null
  SHA="$(cd "$WORK" && "$REAL_GIT" rev-parse --short HEAD)"
}

# add_png <ac-id> — a distinguishable PNG-ish file for the current short sha.
add_png() {
  mkdir -p "$WORK/tasks/e2e-artifacts/$SHA"
  printf 'PNG-%s' "$1" > "$WORK/tasks/e2e-artifacts/$SHA/$1.png"
}

# run_pub [args] — sets OUT, ERR, RC; the shim dir is opt-in via SHIM_ON.
# Passes `--sha $SHA`, as wrap-up does, unless NO_SHA is set.
run_pub() {
  local path="$STUBS:$PATH"
  [ -n "${SHIM_ON:-}" ] && path="$SHIM:$path"
  local sha_args=(--sha "$SHA"); [ -n "${NO_SHA:-}" ] && sha_args=()
  RC=0
  PATH="$path" "$TEST_PYTHON" "$PUB" --repo "$WORK" "${sha_args[@]}" "$@" >"$T/out" 2>"$T/err" </dev/null || RC=$?
  OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}

remote_tip() { "$REAL_GIT" -C "$BARE" rev-parse --verify -q refs/heads/e2e-evidence || true; }

echo "§ publish"
new_fixture pub; add_png AC-1
head_before="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
index_before="$(cksum < "$WORK/.git/index")"
run_pub
tip1="$(remote_tip)"
assert_eq 0 "$RC" "first publish exits 0"
assert_contains "$OUT" "## Visual evidence" "stdout carries the section heading"
assert_contains "$OUT" "![AC-1](https://github.com/acme/widgets/blob/$tip1/$SHA/AC-1.png?raw=true)" "image link pinned to the evidence commit"
assert_eq "" "$("$REAL_GIT" -C "$BARE" rev-list --parents -n1 "$tip1" | cut -s -d' ' -f2)" "first commit is an orphan root"
assert_eq "$SHA/AC-1.png" "$("$REAL_GIT" -C "$BARE" ls-tree -r --name-only "$tip1")" "evidence tree holds <sha>/<AC-id>.png"
assert_eq "PNG-AC-1" "$("$REAL_GIT" -C "$BARE" show "$tip1:$SHA/AC-1.png")" "PNG bytes survive the round trip"
assert_eq "$head_before" "$("$REAL_GIT" -C "$WORK" rev-parse HEAD)" "feature HEAD untouched"
assert_eq "$index_before" "$(cksum < "$WORK/.git/index")" "feature index untouched"
assert_eq "" "$("$REAL_GIT" -C "$WORK" status --porcelain)" "feature working tree clean"
assert_eq "main" "$("$REAL_GIT" -C "$WORK" branch --show-current)" "feature branch still checked out"
assert_eq "evidence: published 1 to acme/widgets" "$ERR" "stderr is exactly one status line"

add_png AC-2
run_pub
tip2="$(remote_tip)"
assert_eq 0 "$RC" "second publish exits 0"
assert_eq "$tip1" "$("$REAL_GIT" -C "$BARE" rev-parse "$tip2^")" "second commit is a child of the first (no force-push)"
assert_eq "2" "$("$REAL_GIT" -C "$BARE" ls-tree -r --name-only "$tip2" | wc -l | tr -d ' ')" "child tree holds both PNGs"
assert_contains "$OUT" "![AC-2](https://github.com/acme/widgets/blob/$tip2/$SHA/AC-2.png?raw=true)" "links point at the new commit"
assert_contains "$("$REAL_GIT" -C "$BARE" log -1 --format=%s "$tip2")" "evidence: $SHA (2 screenshots)" "commit message names sha and count"

echo "  -- unchanged tree is not re-committed"
run_pub
assert_eq "$tip2" "$(remote_tip)" "identical rebuild leaves the tip alone"
assert_contains "$OUT" "/blob/$tip2/$SHA/AC-1.png?raw=true" "and links the existing tip"

echo "  -- public repo marker"
GH_PRIVATE=false run_pub
assert_contains "$ERR" "evidence: published 2 to acme/widgets — public repo" "public repo is never silent"
GH_PRIVATE= run_pub
assert_eq 0 "$RC" "gh failing does not fail the publish"
assert_not_contains "$ERR" "public repo" "gh failing omits the marker"
assert_contains "$ERR" "— visibility unknown" "gh failing says visibility is unknown, never implies private"

echo "  -- the sha is the walkthrough's, not HEAD's"
# Wrap-up commits and pushes before it writes the PR, so HEAD has moved past
# the sha the PNGs were saved under. Defaulting to HEAD would publish nothing.
( cd "$WORK" && echo more >> app.txt && "$REAL_GIT" commit -qam "wrap-up commit" )
run_pub
assert_contains "$OUT" "/$SHA/AC-1.png?raw=true" "a commit after the walkthrough still publishes its PNGs"
NO_SHA=1 run_pub
assert_eq 2 "$RC" "no --sha is a usage error, never a silent HEAD guess"
assert_contains "$ERR" "--sha" "the usage error names --sha"

echo "  -- scp-style origin parses"
"$REAL_GIT" -C "$WORK" config remote.origin.url git@github.com:acme/widgets.git
"$REAL_GIT" -C "$WORK" config "url.$BARE.insteadOf" git@github.com:acme/widgets.git
run_pub
assert_contains "$OUT" "https://github.com/acme/widgets/blob/" "scp-style origin yields https links"

echo "§ skip paths"
new_fixture none
run_pub
assert_eq 0 "$RC" "no PNGs exits 0"
assert_eq "" "$OUT" "no PNGs prints nothing on stdout"
assert_contains "$ERR" "evidence: none" "no PNGs says so on stderr"
assert_eq "" "$(remote_tip)" "no PNGs pushes nothing"

new_fixture opt; add_png AC-1
printf '# Agents\n<!-- jplugin-agentic-development:end -->\nE2E evidence: local\n' > "$WORK/AGENTS.md"
run_pub
assert_eq 0 "$RC" "opt-out exits 0"
assert_contains "$OUT" "## Visual evidence (local only)" "opt-out uses the local-only heading"
assert_contains "$OUT" "tasks/e2e-artifacts/$SHA/AC-1.png" "opt-out lists the local path"
assert_contains "$OUT" "E2E evidence: local" "opt-out explains why"
assert_eq "" "$(remote_tip)" "opt-out pushes nothing"
assert_contains "$ERR" "evidence: local 1" "opt-out status line"

new_fixture above; add_png AC-1
printf 'E2E evidence: local\n<!-- jplugin-agentic-development:end -->\n' > "$WORK/AGENTS.md"
run_pub
assert_not_contains "$OUT" "(local only)" "the opt-out line above the end marker does not count"
assert_contains "$OUT" "https://github.com/acme/widgets/blob/" "and the evidence is published"

new_fixture nomark; add_png AC-1
printf '# Agents\nE2E evidence: local\n' > "$WORK/AGENTS.md"
run_pub
assert_contains "$OUT" "## Visual evidence (local only)" "without markers the line counts anywhere in AGENTS.md"
assert_eq "" "$(remote_tip)" "and nothing is pushed"

new_fixture gitlab; add_png AC-1
"$REAL_GIT" -C "$WORK" config remote.origin.url https://gitlab.com/acme/widgets.git
"$REAL_GIT" -C "$WORK" config "url.$BARE.insteadOf" https://gitlab.com/acme/widgets.git
run_pub
assert_eq 0 "$RC" "non-GitHub origin exits 0"
assert_contains "$OUT" "## Visual evidence (local only)" "non-GitHub origin uses the local-only heading"
assert_contains "$OUT" "not a GitHub" "non-GitHub origin says why"
assert_eq "" "$(remote_tip)" "non-GitHub origin pushes nothing"

echo "§ race"
SHIM_ON=1
new_fixture race1; add_png AC-1
RACE_MODE=once run_pub
tip="$(remote_tip)"
assert_eq 0 "$RC" "one lost race is retried and succeeds"
assert_eq "true" "$([ -e "$RACE_MARK" ] && echo true || echo false)" "the competing publisher really pushed first"
assert_contains "$("$REAL_GIT" -C "$BARE" ls-tree -r --name-only "$tip")" "$SHA/AC-1.png" "our PNG is on the tip"
assert_contains "$("$REAL_GIT" -C "$BARE" ls-tree -r --name-only "$tip")" "other-" "the competitor's file survived"
assert_eq "competing publisher" "$("$REAL_GIT" -C "$BARE" log -1 --format=%s "$tip^")" "our commit sits on the competitor's tip"
assert_contains "$OUT" "/blob/$tip/$SHA/AC-1.png?raw=true" "links point at the rebuilt commit"

new_fixture race2; add_png AC-1
RACE_MODE=always run_pub
assert_eq "true" "$([ "$RC" -ne 0 ] && echo true || echo false)" "a second rejection exits non-zero"
assert_contains "$ERR" "evidence: publish failed" "and says publish failed on stderr"
assert_eq "" "$OUT" "and prints no evidence section"

# git words a rejection in the user's language, so the classifier is only as
# stable as the locale the push runs under: the push must pin LC_ALL=C itself,
# whatever the caller's environment says.
new_fixture locale; add_png AC-1
export PUSH_ENV_LOG="$T/locale/push-env.log"
LANG=pt_BR.UTF-8 LC_ALL=pt_BR.UTF-8 RACE_MODE=once run_pub
assert_eq 0 "$RC" "a lost race is retried under a non-English caller locale"
assert_eq "LC_ALL=C
LC_ALL=C" "$(cat "$PUSH_ENV_LOG")" "every push ran with LC_ALL=C, twice for one retried race"
unset PUSH_ENV_LOG

# Only a rejected push is a lost race. A broken remote fails on the first
# attempt with its own message, so the caller can tell the two apart.
new_fixture broken; add_png AC-1
"$REAL_GIT" -C "$WORK" config --unset "url.$BARE.insteadOf"
"$REAL_GIT" -C "$WORK" config "url.$T/nowhere.git.insteadOf" https://github.com/acme/widgets.git
export CALL_LOG="$T/broken/calls.log"
RACE_MODE= run_pub
assert_eq 1 "$RC" "a broken remote exits 1"
assert_eq 1 "$(grep -c '^-C .* ls-remote' "$CALL_LOG")" "a broken remote is not retried"
assert_contains "$ERR" "evidence: publish failed (git ls-remote" "and the first error is the one reported"
unset CALL_LOG
unset SHIM_ON

# --- one owner for the artifact layout ---------------------------------------
# e2e_evidence.py owns tasks/e2e-artifacts/<sha>/<AC-id>.png; the publisher
# imports it. A copy of both scripts whose checker names another directory must
# publish from that directory, and a publisher without its checker must refuse.
assert_eq 0 "$(grep -c 'tasks/e2e-artifacts' "$PUB" || true)" "layout: the publisher does not spell the artifact directory"
new_fixture layout
LAYOUT_TREE="$T/layout/tree"; mkdir -p "$LAYOUT_TREE/wrap-up-session/scripts" "$LAYOUT_TREE/verify-evidence/scripts"
cp "$PUB" "$LAYOUT_TREE/wrap-up-session/scripts/"
sed 's#tasks/e2e-artifacts#custom/shots#' "$REPO/.agents/skills/verify-evidence/scripts/e2e_evidence.py" \
  > "$LAYOUT_TREE/verify-evidence/scripts/e2e_evidence.py"
mkdir -p "$WORK/custom/shots/$SHA"; printf 'PNG-X' > "$WORK/custom/shots/$SHA/AC-9.png"
RC=0; OUT="$(PATH="$STUBS:$PATH" "$TEST_PYTHON" "$LAYOUT_TREE/wrap-up-session/scripts/publish_evidence.py" \
  --repo "$WORK" --sha "$SHA" 2>/dev/null </dev/null)" || RC=$?
assert_eq 0 "$RC" "layout: the publisher follows the checker's layout"
assert_contains "$OUT" "/$SHA/AC-9.png?raw=true" "layout: a PNG under the checker's directory is published"

# The leaf naming (file name <-> AC-id) is the checker's too: a checker that
# names files `<AC-id>-after.png` and strips the suffix must set the link text.
NAMING_CHECKER="$LAYOUT_TREE/verify-evidence/scripts/e2e_evidence.py"
python3 - "$NAMING_CHECKER" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('f"{ARTIFACT_DIR}/{sha}/{ac_id}.png"', 'f"{ARTIFACT_DIR}/{sha}/{ac_id}-after.png"')
old = 'return [(png.stem, png) for png in sorted((root / ARTIFACT_DIR / sha).glob("*.png"))]'
assert old in s
s = s.replace(old, 'return [(p.stem.removesuffix("-after"), p) for p in sorted((root / ARTIFACT_DIR / sha).glob("*-after.png"))]')
open(p, "w").write(s)
PY
rm -f "$WORK/custom/shots/$SHA/AC-9.png"; printf 'PNG-Y' > "$WORK/custom/shots/$SHA/AC-7-after.png"
RC=0; OUT="$(PATH="$STUBS:$PATH" "$TEST_PYTHON" "$LAYOUT_TREE/wrap-up-session/scripts/publish_evidence.py" \
  --repo "$WORK" --sha "$SHA" 2>/dev/null </dev/null)" || RC=$?
assert_eq 0 "$RC" "layout: a checker with its own leaf naming publishes"
assert_contains "$OUT" "![AC-7](" "layout: link text is the checker's AC-id"
assert_contains "$OUT" "/$SHA/AC-7.png?raw=true" "layout: the evidence branch path uses the checker's AC-id"

# The checker missing is an ordinary publish failure, not an import-time death.
PUB_COPY="$LAYOUT_TREE/wrap-up-session/scripts/publish_evidence.py"
rm "$NAMING_CHECKER"
RC=0; PATH="$STUBS:$PATH" "$TEST_PYTHON" "$PUB_COPY" --help >/dev/null 2>&1 </dev/null || RC=$?
assert_eq 0 "$RC" "layout: --help works with the checker absent"
RC=0; ERR="$(PATH="$STUBS:$PATH" "$TEST_PYTHON" "$PUB_COPY" --repo "$WORK" --sha "$SHA" 2>&1 >/dev/null </dev/null)" || RC=$?
assert_eq 1 "$RC" "layout: a missing checker exits 1, no copied constant"
assert_contains "$ERR" "evidence: publish failed (layout owner" "layout: the failure is the normal publish-failed line"
assert_contains "$ERR" "e2e_evidence.py not found)" "layout: the failure names the missing checker"
assert_eq "False" "$("$TEST_PYTHON" -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('pe', '$PUB_COPY')
mod = importlib.util.module_from_spec(spec); sys.modules['pe'] = mod
spec.loader.exec_module(mod)
print('e2e_evidence' in sys.modules)")" "layout: importing the publisher loads nothing"

# --- wrap-up wiring (AC 10) --------------------------------------------------
# The publisher reaches a reviewer only through the PR body, so wrap-up must run
# it before `gh pr create` AND on every re-sync, and the report must say where
# the screenshots went — a public repo is never published to silently.
WRAP="$REPO/.agents/skills/wrap-up-session/SKILL.md"
PR_SECTION="$(awk '/^### The Pull Request/{f=1;next} f&&/^### /{exit} f' "$WRAP" | tr '\n' ' ' | tr -s ' ')"
assert_contains "$PR_SECTION" "publish_evidence.py" "wrap-up: § The Pull Request runs the publisher"
assert_precedes "$PR_SECTION" "publish_evidence.py" "gh pr create" \
  "wrap-up: the publisher runs before gh pr create"
assert_contains "$PR_SECTION" "every re-sync" "wrap-up: the publisher runs on every re-sync"
assert_contains "$PR_SECTION" "publish_evidence.py --sha <the short-sha § E2E coverage checked>" \
  "wrap-up: the publisher gets the walkthrough's sha, not HEAD after the wrap-up commit"
assert_contains "$PR_SECTION" "never blocks the PR" "wrap-up: a publish failure never blocks the PR"
REPORT="$(awk '/^### Report/{f=1;next} f' "$WRAP" | grep -F -- '- Evidence:')"
for form in "published <n> to <owner/repo>" "public repo" "local <n>" "none" "publish failed"; do
  assert_contains "$REPORT" "$form" "wrap-up: the report's evidence: line has '$form'"
done
assert_contains "$REPORT" "- Evidence:" "wrap-up: the report carries an Evidence line"

finish
