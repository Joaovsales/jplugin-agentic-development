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

# ── § upstream-read (AC 4) ───────────────────────────────────────────────────
# The drawing instructions are upstream's, read from the install at run time
# (D17): this page names the file and adds four conventions, and restates no
# type router, schema or finalize-repair contract — restating drifts every
# release.
assert_file_contains "$SKILL" '$ARCHIFY_HOME/archify/SKILL.md' \
  "upstream-read: the skill reads upstream's SKILL.md from the install"
for convention in "Evidence" "Output location" "Browser" "Diagrams only"; do
  assert_file_matches "$SKILL" "^#+ .*$convention" \
    "upstream-read: convention '$convention' has its own heading"
done
for restated in 'Type router' 'Mermaid input' 'Delivery' 'Setup and fallback' 'Update awareness' 'repair'; do
  assert_file_not_matches "$SKILL" "^#+ .*$restated" \
    "upstream-read: no '$restated' heading restated from upstream"
done
assert_file_not_matches "$SKILL" 'schemas/[a-z]+\.schema\.json' "upstream-read: no schema paths restated"
assert_file_not_matches "$SKILL" '^\| `(architecture|workflow|sequence|erd)` \|' \
  "upstream-read: no type-router table restated"

# ── § evidence (AC 5) ────────────────────────────────────────────────────────
# A codebase diagram is evidence or nothing (D8): the page requires the pinned
# revision, a source on every component and --repo-root, and the pre-finalize
# check refuses a candidate that lacks any of them.
assert_file_contains "$SKILL" 'meta.repository' "evidence: the skill names meta.repository"
assert_file_contains "$SKILL" '`HEAD`' "evidence: the skill pins the candidate to HEAD"
assert_file_contains "$SKILL" '`sources`' "evidence: the skill requires sources on every component"
assert_file_contains "$SKILL" '--repo-root' "evidence: finalize runs with --repo-root"
assert_file_contains "$SKILL" 'check-candidate' "evidence: the skill runs the pre-finalize check"

if command -v node > /dev/null 2>&1; then
  mkdir -p "$box/repo"
  git -C "$box/repo" init -q
  mkdir -p "$box/repo/src"; printf 'echo a\n' > "$box/repo/src/a.sh"
  git -C "$box/repo" add src/a.sh
  git -C "$box/repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm a
  REV="$(git -C "$box/repo" rev-parse HEAD)"
  write_candidate() { # <file> <revision-json-or-empty-meta> <components-json>
    printf '{"schema_version":1,"diagram_type":"architecture","meta":{"title":"t"%s},"components":%s}\n' "$2" "$3" > "$1"
  }
  run_check() { # <candidate> → CHK_STATUS, CHK_OUT, CHK_ERR
    bash "$RESOLVER" check-candidate "$1" --repo-root "$box/repo" > "$box/chk.out" 2> "$box/chk.err"
    CHK_STATUS=$?; CHK_OUT="$(cat "$box/chk.out")"; CHK_ERR="$(cat "$box/chk.err")"
  }
  REPO_META=",\"repository\":{\"url\":\"https://example.test/r.git\",\"revision\":\"$REV\"}"
  CITED='{"id":"a","label":"A","sources":[{"path":"src/a.sh","line":1}]}'
  write_candidate "$box/uncited.json" "$REPO_META" "[$CITED,{\"id\":\"b\",\"label\":\"B\"}]"
  run_check "$box/uncited.json"
  assert_eq "1" "$CHK_STATUS" "evidence: a component without sources is rejected"
  assert_contains "$CHK_ERR" "b" "evidence: the rejection names the uncited component"
  assert_contains "$CHK_ERR" "sources" "evidence: the rejection names the missing field"

  write_candidate "$box/cited.json" "$REPO_META" "[$CITED,{\"id\":\"b\",\"label\":\"B\",\"sources\":[{\"path\":\"src/a.sh\",\"line\":1}]}]"
  run_check "$box/cited.json"
  assert_eq "0" "$CHK_STATUS" "evidence: a fully cited candidate at HEAD passes"
  assert_eq "" "$CHK_OUT$CHK_ERR" "evidence: a passing check is silent"

  STALE=",\"repository\":{\"url\":\"https://example.test/r.git\",\"revision\":\"0000000000000000000000000000000000000000\"}"
  write_candidate "$box/stale.json" "$STALE" "[$CITED]"
  run_check "$box/stale.json"
  assert_eq "1" "$CHK_STATUS" "evidence: a revision other than HEAD is rejected"
  assert_contains "$CHK_ERR" "$REV" "evidence: the rejection names the repository HEAD"

  write_candidate "$box/freehand.json" "" "[$CITED]"
  run_check "$box/freehand.json"
  assert_eq "1" "$CHK_STATUS" "evidence: a codebase candidate without meta.repository is rejected"
  assert_contains "$CHK_ERR" "meta.repository" "evidence: the rejection names meta.repository"
else
  printf '  note evidence: node is absent on this machine; the candidate-check cases did not run\n'
fi

# ── § refresh (AC 14) ────────────────────────────────────────────────────────
# `--refresh` is the only regeneration path (D19): /wrap-up-session never
# learns about diagrams, so its page carries none of this feature's vocabulary.
assert_file_contains "$SKILL" '--refresh <' "refresh: the skill documents --refresh <path>"
assert_prose_contains "$SKILL" 'only regeneration path' "refresh: --refresh is named the only regeneration path"
assert_file_not_matches .agents/skills/wrap-up-session/SKILL.md 'archify|`/diagram`|--refresh' \
  "refresh: /wrap-up-session is untouched by this feature"

# ── § how (AC 10) ────────────────────────────────────────────────────────────
# /how offers, always, in one closing line; nothing renders until the user says
# yes (D18). Its explainer prompt stops drawing Mermaid or ASCII in chat — the
# standalone diagram is /diagram's job.
HOW=.agents/skills/how/SKILL.md
how_output="$(section_body "$HOW" "## Output Format")"
assert_contains "$how_output" '`/diagram' "how: the output contract offers a /diagram"
assert_contains "$how_output" "until the user says yes" "how: the offer renders nothing unasked"
assert_file_not_matches .agents/skills/how/references/explainer-prompt.md '[Mm]ermaid|ASCII' \
  "how: the explainer prompt no longer asks for Mermaid or ASCII diagrams"

# ── § plan (AC 11) ───────────────────────────────────────────────────────────
PLAN=.agents/skills/plan/SKILL.md
plan_present="$(section_body "$PLAN" "### 4. Present" "^### ")"
assert_contains "$plan_present" '`/diagram' "plan: § 4 Present offers a /diagram"
assert_contains "$plan_present" "more than one component" "plan: the offer is for multi-component features"

# ── § sdp (AC 12) ────────────────────────────────────────────────────────────
# /system-design-planning produces the architecture diagram beside its spec
# when the tool is installed; without it the spec and its DSL fences are
# produced as today plus one install-command line, and the session continues.
SDP=.agents/skills/system-design-planning/SKILL.md
assert_file_contains "$SDP" 'specs/<feature>.architecture.html' "sdp: the architecture diagram lands beside the spec"
assert_file_contains "$SDP" '`/diagram' "sdp: the diagram is produced through /diagram"
assert_prose_contains "$SDP" 'install command' "sdp: without the tool the install command is printed"
assert_prose_contains "$SDP" 'the session continues' "sdp: without the tool the session does not stop"
assert_prose_contains "$SDP" 'fenced `flow` / `sequence` blocks' "sdp: the flow and sequence fences are unchanged (D12)"

# ── § tidy (AC 13) ───────────────────────────────────────────────────────────
# /tidy's `tools` check compares the commit checked out under $ARCHIFY_HOME with
# the registry baseline: no install is inconclusive, another commit is Tier 1
# with the re-install command printed, never run (Law 7).
TIDY=.agents/skills/tidy/SKILL.md
tools_row="$(grep -E '^\| `tools` \|' "$TIDY")"
assert_contains "$tools_row" 'ARCHIFY_HOME' "tidy: the tools row reads \$ARCHIFY_HOME"
assert_contains "$tools_row" 'rev-parse HEAD' "tidy: the tools row compares the checked-out commit"
assert_contains "$tools_row" '.github/upstreams.json' "tidy: the tools row reads the registry baseline"
assert_contains "$tools_row" 'inconclusive' "tidy: no install is inconclusive, not a finding"
assert_contains "$tools_row" 'Tier 1' "tidy: another commit is a Tier 1 finding"
assert_contains "$tools_row" 'never' "tidy: the re-install remedy is printed, never applied"
assert_contains "$(section_body "$TIDY" "## Edge cases")" 'ARCHIFY_HOME' \
  "tidy: the edge-case table carries the tools cases"

finish
