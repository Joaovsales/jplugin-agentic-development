#!/usr/bin/env bash
# Browser proof for the visual plan page (specs/readable-visual-plans.md AC23):
# every generic fixture, rendered, is driven at 1440 and 390 px in light and
# dark by .agents/skills/visual-plan/scripts/check_plan_page.py, which writes a
# screenshot per view for the owner's review.
#
# Needs the `playwright` Python package and a Chromium-family browser. Without
# them the file prints a loud SKIP and passes, unless REQUIRE_BROWSER=1 makes
# the missing browser a failure. PLAN_PAGE_PYTHON picks the interpreter that
# has playwright, PLAN_PAGE_CHANNEL a browser channel (msedge, chrome), and
# PLAN_PAGE_SHOTS keeps the screenshots (default: a temp dir, removed on exit).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO_ROOT/.agents/skills/visual-plan/scripts"
FIX="$REPO_ROOT/tests/fixtures/plan-render"
PY="${PLAN_PAGE_PYTHON:-$TEST_PYTHON}"
CHANNEL=()
[ -n "${PLAN_PAGE_CHANNEL:-}" ] && CHANNEL=(--channel "$PLAN_PAGE_CHANNEL")

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SHOTS="${PLAN_PAGE_SHOTS:-$TMP/shots}"

if ! "$PY" -c 'import playwright' >/dev/null 2>&1; then
  if [ "${REQUIRE_BROWSER:-0}" = "1" ]; then
    assert_eq "playwright importable" "missing" "browser: REQUIRE_BROWSER=1 but $PY cannot import playwright"
  else
    printf '\n  SKIP browser: %s cannot import playwright — the page is NOT browser-checked (set PLAN_PAGE_PYTHON, or REQUIRE_BROWSER=1 to fail)\n\n' "$PY"
  fi
  finish
  exit $?
fi

printf '\n--- pages: every rendering fixture, beside its spec so the source link resolves ---\n'
mkdir -p "$TMP/site"
count=0
for spec in "$FIX"/*.md; do
  name="$(basename "$spec" .md)"
  case "$name" in fail-*) continue ;; esac
  cp "$spec" "$TMP/site/$name.md"
  (cd "$TMP/site" && "$TEST_PYTHON" "$SCRIPTS/plan_render.py" "$name.md" -o "$name.plan.html" >/dev/null 2>&1)
  assert_eq "0" "$?" "pages: $name.md renders"
  count=$((count + 1))
done
# full.md is deliberately not ready; this variant settles D2 and unblocks Q1 so
# its prompt is executable and the copy path is driven too.
sed -e 's/| Rows grow past 2 KB each | open |/| Rows grow past 2 KB each | settled |/' \
    -e 's/| Which bucket region holds part files? | 2 |/| Which bucket region holds part files? | none |/' \
    "$FIX/full.md" > "$TMP/site/ready.md"
(cd "$TMP/site" && "$TEST_PYTHON" "$SCRIPTS/plan_render.py" ready.md -o ready.plan.html >/dev/null 2>&1)
assert_eq "0" "$?" "pages: the ready variant renders"
assert_not_contains "$(cat "$TMP/site/ready.plan.html")" 'data-copy-from="build-prompt-text" disabled' "pages: the ready variant's copy is enabled"
count=$((count + 1))

printf '\n--- browser: disclosures, keyboard, deep links, menu, copy, source, review, errors, overflow ---\n'
OUT="$("$PY" "$SCRIPTS/check_plan_page.py" "$TMP/site" --shots "$SHOTS" "${CHANNEL[@]}" 2>&1)"
CODE=$?
[ "$CODE" -eq 0 ] || printf '%s\n' "$OUT"
assert_eq "0" "$CODE" "browser: every view of every fixture passes"
assert_eq "$((count * 4))" "$(find "$SHOTS" -name '*.png' | wc -l | tr -d ' ')" "browser: one screenshot per page, viewport and theme"

printf '\n--- sabotage: the checker fails a page that overflows and logs errors ---\n'
mkdir -p "$TMP/broken"
cp "$TMP/site/full.md" "$TMP/broken/full.md"
sed 's#</main>#<div style="width:3000px">wide</div><script>console.error("boom")</script></main>#' \
  "$TMP/site/full.plan.html" > "$TMP/broken/full.plan.html"
cp "$TMP/site/ready.md" "$TMP/broken/ready.md"
sed 's#copyText(source.textContent, button)#copyText(source.textContent + " ", button)#' \
  "$TMP/site/ready.plan.html" > "$TMP/broken/ready.plan.html"
BROKEN="$("$PY" "$SCRIPTS/check_plan_page.py" "$TMP/broken" --shots "$TMP/broken-shots" "${CHANNEL[@]}" 2>&1)"
assert_eq "1" "$?" "sabotage: a broken page fails the check"
assert_contains "$BROKEN" "full.plan.html 390 light: page overflows horizontally" "sabotage: overflow is named with its view"
assert_contains "$BROKEN" "console errors: boom" "sabotage: console errors are named"
assert_contains "$BROKEN" "ready.plan.html 1440 light: Copy build prompt did not copy the prompt text exactly" "sabotage: a copy that drifts from the prompt is caught"

finish
