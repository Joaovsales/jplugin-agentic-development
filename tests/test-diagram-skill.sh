#!/bin/bash
# tests/test-diagram-skill.sh — /diagram over an installed Archify tool
# (specs/diagram-skill.md). Archify is a pinned tool under $ARCHIFY_HOME, never
# a skill or a vendored copy, so the skill is one page plus a resolver script;
# the sections below pin what that page says and what the resolver does.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SKILL=.agents/skills/diagram/SKILL.md
RESOLVER=.agents/skills/diagram/scripts/archify.sh
BASH_BIN="$(command -v bash)"

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

frontmatter() {
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm { print }' "$1" 2>/dev/null
}

# ── § frontmatter (AC 1) ─────────────────────────────────────────────────────
fm="$(frontmatter "$SKILL")"
assert_contains "$fm" "name: diagram" "frontmatter: the skill is named diagram"
assert_contains "$fm" "harness: universal" "frontmatter: /diagram registers for every harness"
desc="$(printf '%s\n' "$fm" | grep '^description:' | tr '[:upper:]' '[:lower:]')"
for phrase in diagram draw visualize archify; do
  assert_contains "$desc" "$phrase" "frontmatter: the description triggers on '$phrase'"
done
assert_file_matches README.md '^\| `/diagram` \|' "README: the skills table carries the /diagram row"
assert_eq "0" "$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" scripts/render-skills-table.py --check >/dev/null 2>&1; echo $?)" \
  "README: render-skills-table.py --check is silent with the /diagram row"
assert_eq "0" "$(bash tests/test-skill-frontmatter.sh >/dev/null 2>&1; echo $?)" \
  "frontmatter: tests/test-skill-frontmatter.sh passes with the new skill"

# ── Resolver harness ─────────────────────────────────────────────────────────
# A PATH holding only what each case puts there, so the machine's own node and
# browsers never decide a verdict. `env -i` drops ARCHIFY_CHROME and Playwright's
# variables the way a clean shell would.
# The stub's shebang is the absolute bash: the fixture PATH has no `env` or `bash`.
make_node_stub() { # <bin dir> <version>
  printf '#!%s\n[ "${1:-}" = "--version" ] && echo "v%s"\nexit 0\n' "$BASH_BIN" "$2" > "$1/node"
  chmod +x "$1/node"
}
make_fixture_install() { # <home>
  mkdir -p "$1/archify/bin"
  : > "$1/archify/bin/archify.mjs"
  : > "$1/archify/SKILL.md"
}
# run_resolver <ARCHIFY_HOME> <PATH> [ENV=VAL...] — stdout in $RES_OUT, stderr
# in $RES_ERR, exit status in $RES_STATUS (set in this shell, never echoed from
# a subshell). Runs from a scratch cwd so a stray write shows.
run_resolver() {
  local home="$1" path="$2"; shift 2
  mkdir -p "$box/work"
  ( cd "$box/work" && env -i HOME="$box/home" PATH="$path" ARCHIFY_HOME="$home" "$@" \
      "$BASH_BIN" "$REPO/$RESOLVER" resolve ) > "$box/out" 2> "$box/err"
  RES_STATUS=$?
  RES_OUT="$(cat "$box/out")"; RES_ERR="$(cat "$box/err")"
}
html_written() { find "$box" -name '*.html' 2>/dev/null | wc -l | tr -d ' '; }

# ── § resolver (AC 2) ────────────────────────────────────────────────────────
# Tool absent: exactly one install command, nothing exported, no HTML, non-zero.
mkdir -p "$box/empty-home" "$box/bin-a"
make_node_stub "$box/bin-a" "20.11.0"
run_resolver "$box/empty-home" "$box/bin-a"
assert_eq "1" "$RES_STATUS" "resolver: an empty ARCHIFY_HOME exits non-zero"
assert_eq "1" "$(printf '%s\n' "$RES_ERR" | grep -c '^git clone ')" \
  "resolver: exactly one install command is printed"
install_line="$(printf '%s\n' "$RES_ERR" | grep '^git clone ')"
assert_contains "$install_line" "--branch v3.2.0" "resolver: the install command pins the tag"
assert_contains "$install_line" "https://github.com/tt-a1i/archify" "resolver: the install command names upstream"
assert_contains "$install_line" "$box/empty-home" "resolver: the install command targets the resolved ARCHIFY_HOME"
assert_eq "" "$RES_OUT" "resolver: a missing tool exports nothing"
assert_eq "0" "$(html_written)" "resolver: a missing tool writes no HTML"

# Node too old: the requirement is named, nothing exported, no HTML, non-zero.
mkdir -p "$box/bin-b"
make_fixture_install "$box/fixture-home"
make_node_stub "$box/bin-b" "16.20.2"
run_resolver "$box/fixture-home" "$box/bin-b"
assert_eq "1" "$RES_STATUS" "resolver: node v16 exits non-zero"
assert_contains "$RES_ERR" "Node >= 18" "resolver: node v16 names the Node >= 18 requirement"
assert_eq "" "$RES_OUT" "resolver: an old node exports nothing"
assert_eq "0" "$(html_written)" "resolver: an old node writes no HTML"

# Node absent: named too — the tool cannot run without it (D3).
mkdir -p "$box/bin-empty"
run_resolver "$box/fixture-home" "$box/bin-empty"
assert_eq "1" "$RES_STATUS" "resolver: no node exits non-zero"
assert_contains "$RES_ERR" "Node >= 18" "resolver: no node names the Node >= 18 requirement"

# ── § browser (AC 3) ─────────────────────────────────────────────────────────
# No browser on PATH, but playwright-cli installed one: ARCHIFY_CHROME is exported
# pointing at the newest Chromium it holds.
mkdir -p "$box/pw/chromium-1100/chrome-linux" "$box/pw/chromium-1194/chrome-linux"
: > "$box/pw/chromium-1100/chrome-linux/chrome"; chmod +x "$box/pw/chromium-1100/chrome-linux/chrome"
: > "$box/pw/chromium-1194/chrome-linux/chrome"; chmod +x "$box/pw/chromium-1194/chrome-linux/chrome"
run_resolver "$box/fixture-home" "$box/bin-a" PLAYWRIGHT_BROWSERS_PATH="$box/pw"
assert_eq "0" "$RES_STATUS" "browser: a fixture install with node >= 18 resolves"
assert_contains "$RES_OUT" "export ARCHIFY_CHROME=$box/pw/chromium-1194/chrome-linux/chrome" \
  "browser: playwright-cli's newest Chromium is exported when PATH has none"
assert_contains "$RES_OUT" "export ARCHIFY_BIN=$box/fixture-home/archify/bin/archify.mjs" \
  "browser: the CLI entry point is exported"
assert_contains "$RES_OUT" "export ARCHIFY_SKILL=$box/fixture-home/archify/SKILL.md" \
  "browser: upstream's SKILL.md path is exported for the run-time read"
assert_eq "chrome=$box/pw/chromium-1194/chrome-linux/chrome" \
  "$(eval "$RES_OUT"; echo "chrome=$ARCHIFY_CHROME")" "browser: stdout is eval-safe export lines"

# A Chrome on PATH wins over playwright-cli's copy (resolution order).
mkdir -p "$box/bin-c"; make_node_stub "$box/bin-c" "20.11.0"
: > "$box/bin-c/chromium"; chmod +x "$box/bin-c/chromium"
run_resolver "$box/fixture-home" "$box/bin-c" PLAYWRIGHT_BROWSERS_PATH="$box/pw"
assert_contains "$RES_OUT" "export ARCHIFY_CHROME=$box/bin-c/chromium" \
  "browser: a Chromium on PATH is preferred to playwright-cli's"

# An existing ARCHIFY_CHROME is kept as given.
run_resolver "$box/fixture-home" "$box/bin-c" ARCHIFY_CHROME=/opt/chrome/custom
assert_contains "$RES_OUT" "export ARCHIFY_CHROME=/opt/chrome/custom" \
  "browser: a preset ARCHIFY_CHROME is kept"

# Neither: nothing is exported for the browser and the marker the reply must carry is printed.
run_resolver "$box/fixture-home" "$box/bin-a"
assert_eq "0" "$RES_STATUS" "browser: no browser still resolves — the non-browser gates run"
assert_not_contains "$RES_OUT" "ARCHIFY_CHROME" "browser: no browser exports no ARCHIFY_CHROME"
assert_contains "$RES_ERR" "without browser evidence" \
  "browser: no browser prints the without-browser-evidence marker"
assert_eq "0" "$(html_written)" "browser: resolving writes no HTML"

finish
