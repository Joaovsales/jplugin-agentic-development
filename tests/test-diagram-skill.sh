#!/bin/bash
# tests/test-diagram-skill.sh — /diagram over an installed Archify tool
# (specs/diagram-skill.md). Archify is a pinned tool under $ARCHIFY_HOME, never
# a skill or a vendored copy, so the skill is one page plus a resolver script;
# the sections below pin what that page says and what the resolver does.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

DIAGRAM="$(under_test .agents/skills/diagram)"
SKILL="$DIAGRAM/SKILL.md"
RESOLVER="$DIAGRAM/scripts/archify.sh"
BASH_BIN="$(command -v bash)"

box="$(fixture_dir)"

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
assert_exit 0 "README: render-skills-table.py --check is silent with the /diagram row" -- \
  "$TEST_PYTHON" scripts/render-skills-table.py --check
assert_exit 0 "frontmatter: tests/test-skill-frontmatter.sh passes with the new skill" -- \
  bash tests/test-skill-frontmatter.sh

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
# _resolver <ARCHIFY_HOME> <PATH> [ENV=VAL...] — the resolver under a clean env,
# stdout and stderr as the process leaves them. Runs from a scratch cwd so a
# stray write shows. Judge it with `assert_refused ... -- _resolver ...`.
_resolver() {
  local home="$1" path="$2"; shift 2
  mkdir -p "$box/work"
  ( cd "$box/work" && env -i HOME="$box/home" PATH="$path" ARCHIFY_HOME="$home" "$@" \
      "$BASH_BIN" "$RESOLVER" resolve )
}
# resolve — _resolver with stderr kept in $box/err, so `output` after
# `run resolve ...` is stdout alone (the export lines) and stderr is read
# from the file by assert_file_contains.
resolve() { _resolver "$@" 2> "$box/err"; }
html_written() { find "$box" -name '*.html' 2>/dev/null | wc -l | tr -d ' '; }

# ── § resolver (AC 2) ────────────────────────────────────────────────────────
# Tool absent: exactly one install command, nothing exported, no HTML, non-zero.
mkdir -p "$box/empty-home" "$box/bin-a"
make_node_stub "$box/bin-a" "20.11.0"
assert_refused 1 "git clone " "resolver: an empty ARCHIFY_HOME exits non-zero" -- _resolver "$box/empty-home" "$box/bin-a"
run resolve "$box/empty-home" "$box/bin-a"
assert_eq "1" "$(grep -c '^git clone ' "$box/err")" \
  "resolver: exactly one install command is printed"
install_line="$(grep '^git clone ' "$box/err")"
# The registry is the oracle for the pin: a bump edits the consumer files, never a test literal.
ARCHIFY_TAG="$("$TEST_PYTHON" -c 'import json; s=[x for x in json.load(open(".github/upstreams.json"))["sources"] if x["id"]=="archify"][0]; print(s["ref"].rsplit("/", 1)[-1])')"
assert_eq "v" "${ARCHIFY_TAG:0:1}" "resolver: the registry names the pinned tag (oracle is not empty)"
assert_contains "$install_line" "--branch $ARCHIFY_TAG" "resolver: the install command pins the registry's tag"
assert_contains "$install_line" "https://github.com/tt-a1i/archify" "resolver: the install command names upstream"
assert_contains "$install_line" "$box/empty-home" "resolver: the install command targets the resolved ARCHIFY_HOME"
assert_eq "" "$output" "resolver: a missing tool exports nothing"
assert_eq "0" "$(html_written)" "resolver: a missing tool writes no HTML"
# The same command lives in install.sh step 6c; a user who follows either must
# land on the same checkout. Evaluate install.sh's template with the same home
# instead of pinning the text twice.
installer_cmd="$(ARCHIFY_HOME="$box/empty-home" bash -c "$(grep -E '^ARCHIFY_(REPO|TAG|HOME|INSTALL_CMD)=' install.sh); printf '%s\n' \"\$ARCHIFY_INSTALL_CMD\"")"
assert_eq "$installer_cmd" "$install_line" "resolver: the install command is install.sh's, verbatim"

# Node too old: the requirement is named, nothing exported, no HTML, non-zero.
mkdir -p "$box/bin-b"
make_fixture_install "$box/fixture-home"
make_node_stub "$box/bin-b" "16.20.2"
assert_refused 1 "Node >= 18" "resolver: node v16 exits non-zero" -- _resolver "$box/fixture-home" "$box/bin-b"
run resolve "$box/fixture-home" "$box/bin-b"
assert_file_contains "$box/err" "Node >= 18" "resolver: node v16 names the Node >= 18 requirement"
assert_eq "" "$output" "resolver: an old node exports nothing"
assert_eq "0" "$(html_written)" "resolver: an old node writes no HTML"

# Node absent: named too — the tool cannot run without it (D3).
mkdir -p "$box/bin-empty"
assert_refused 1 "Node >= 18" "resolver: no node exits non-zero" -- _resolver "$box/fixture-home" "$box/bin-empty"
assert_contains "$output" "Node >= 18" "resolver: no node names the Node >= 18 requirement"

# ── § browser (AC 3) ─────────────────────────────────────────────────────────
# No browser on PATH, but playwright-cli installed one: ARCHIFY_CHROME is exported
# pointing at the newest Chromium it holds.
mkdir -p "$box/pw/chromium-1100/chrome-linux" "$box/pw/chromium-1194/chrome-linux"
: > "$box/pw/chromium-1100/chrome-linux/chrome"; chmod +x "$box/pw/chromium-1100/chrome-linux/chrome"
: > "$box/pw/chromium-1194/chrome-linux/chrome"; chmod +x "$box/pw/chromium-1194/chrome-linux/chrome"
run resolve "$box/fixture-home" "$box/bin-a" PLAYWRIGHT_BROWSERS_PATH="$box/pw"
assert_exit 0 "browser: a fixture install with node >= 18 resolves"
assert_contains "$output" "export ARCHIFY_CHROME=$box/pw/chromium-1194/chrome-linux/chrome" \
  "browser: playwright-cli's newest Chromium is exported when PATH has none"
assert_contains "$output" "export ARCHIFY_BIN=$box/fixture-home/archify/bin/archify.mjs" \
  "browser: the CLI entry point is exported"
assert_contains "$output" "export ARCHIFY_SKILL=$box/fixture-home/archify/SKILL.md" \
  "browser: upstream's SKILL.md path is exported for the run-time read"
assert_eq "chrome=$box/pw/chromium-1194/chrome-linux/chrome" \
  "$(eval "$output"; echo "chrome=$ARCHIFY_CHROME")" "browser: stdout is eval-safe export lines"

# A Chrome on PATH wins over playwright-cli's copy (resolution order).
mkdir -p "$box/bin-c"; make_node_stub "$box/bin-c" "20.11.0"
: > "$box/bin-c/chromium"; chmod +x "$box/bin-c/chromium"
run resolve "$box/fixture-home" "$box/bin-c" PLAYWRIGHT_BROWSERS_PATH="$box/pw"
assert_contains "$output" "export ARCHIFY_CHROME=$box/bin-c/chromium" \
  "browser: a Chromium on PATH is preferred to playwright-cli's"

# An existing ARCHIFY_CHROME is kept as given.
run resolve "$box/fixture-home" "$box/bin-c" ARCHIFY_CHROME=/opt/chrome/custom
assert_contains "$output" "export ARCHIFY_CHROME=/opt/chrome/custom" \
  "browser: a preset ARCHIFY_CHROME is kept"

# Neither: nothing is exported for the browser and the marker the reply must carry is printed.
run resolve "$box/fixture-home" "$box/bin-a"
assert_exit 0 "browser: no browser still resolves — the non-browser gates run"
assert_not_contains "$output" "ARCHIFY_CHROME" "browser: no browser exports no ARCHIFY_CHROME"
assert_file_contains "$box/err" "without browser evidence" \
  "browser: no browser prints the without-browser-evidence marker"
# The marker is a contract between the resolver (prints it) and the reply (must
# carry it), so the page's copy is pinned to the resolver's constant.
marker="$(sed -n 's/^NO_BROWSER_MARKER="\(.*\)"$/\1/p' "$RESOLVER")"
assert_eq "1" "$(printf '%s' "$marker" | grep -c .)" "browser: the resolver declares one marker constant"
assert_eq "2" "$(grep -c -F -- "*$marker*" "$SKILL")" \
  "browser: both SKILL.md sites quote the resolver's marker verbatim"
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
assert_file_contains "$SKILL" 'check-candidate' "evidence: the skill names the pre-finalize check"
assert_file_contains "$SKILL" 'archify.sh finalize <type> <candidate.json> <output.html>' \
  "evidence: Step 3 finalizes through the resolver, which runs the check first"
assert_prose_contains "$SKILL" 'except `finalize`, which always goes through Step 3' \
  "evidence: the run-upstream-commands rule exempts finalize, so the check cannot be bypassed"

if command -v node > /dev/null 2>&1; then
  FIXTURE_REPO="$(fixture_repo)"
  mkdir -p "$FIXTURE_REPO/src"; printf 'echo a\n' > "$FIXTURE_REPO/src/a.sh"
  git -C "$FIXTURE_REPO" add src/a.sh
  git -C "$FIXTURE_REPO" commit -qm a
  REV="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
  write_candidate() { # <file> <revision-json-or-empty-meta> <components-json>
    printf '{"schema_version":1,"diagram_type":"architecture","meta":{"title":"t"%s},"components":%s}\n' "$2" "$3" > "$1"
  }
  # The check reads which collection is primary from the install's schema, so
  # the fixture install carries the one shape that matters: a top-level array
  # whose items have `sources`, beside the shared `cards` $ref.
  mkdir -p "$box/fixture-home/archify/schemas"
  printf '{"properties":{"components":{"type":"array","items":{"properties":{"id":{},"sources":{}}}},"cards":{"$ref":"common.schema.json#/$defs/cards"}}}\n' \
    > "$box/fixture-home/archify/schemas/architecture.schema.json"
  check_candidate() { # <candidate> — judge with `run check_candidate` or assert_refused
    ARCHIFY_HOME="$box/fixture-home" bash "$RESOLVER" check-candidate "$1" --repo-root "$FIXTURE_REPO"
  }
  REPO_META=",\"repository\":{\"url\":\"https://example.test/r.git\",\"revision\":\"$REV\"}"
  CITED='{"id":"a","label":"A","sources":[{"path":"src/a.sh","line":1}]}'
  write_candidate "$box/uncited.json" "$REPO_META" "[$CITED,{\"id\":\"b\",\"label\":\"B\"}]"
  assert_refused 1 '"b" has no sources' "evidence: a component without sources is rejected" -- check_candidate "$box/uncited.json"
  assert_contains "$output" '"b" has no sources' "evidence: the rejection names the uncited component and the missing field"

  # A path with no line is not a citation: --refresh has no range to re-read.
  write_candidate "$box/lineless.json" "$REPO_META" "[$CITED,{\"id\":\"b\",\"label\":\"B\",\"sources\":[{\"path\":\"src/a.sh\"}]}]"
  assert_refused 1 '"b" has no sources' "evidence: a source without a line is rejected" -- check_candidate "$box/lineless.json"
  assert_contains "$output" '"b" has no sources' "evidence: the line-less rejection names the component as uncited"

  write_candidate "$box/cited.json" "$REPO_META" "[$CITED,{\"id\":\"b\",\"label\":\"B\",\"sources\":[{\"path\":\"src/a.sh\",\"line\":1}]}]"
  run check_candidate "$box/cited.json"
  assert_exit 0 "evidence: a fully cited candidate at HEAD passes"
  assert_eq "" "$output" "evidence: a passing check is silent"

  STALE=",\"repository\":{\"url\":\"https://example.test/r.git\",\"revision\":\"0000000000000000000000000000000000000000\"}"
  write_candidate "$box/stale.json" "$STALE" "[$CITED]"
  assert_refused 1 "$REV" "evidence: a revision other than HEAD is rejected" -- check_candidate "$box/stale.json"
  assert_contains "$output" "$REV" "evidence: the rejection names the repository HEAD"

  write_candidate "$box/freehand.json" "" "[$CITED]"
  assert_refused 1 "meta.repository" "evidence: a codebase candidate without meta.repository is rejected" -- check_candidate "$box/freehand.json"
  assert_contains "$output" "meta.repository" "evidence: the rejection names meta.repository"

  # A type the install has no schema for is upstream's to add, not this check's to guess.
  sed 's/"diagram_type":"architecture"/"diagram_type":"c4"/' "$box/cited.json" > "$box/c4.json"
  assert_refused 1 'is not a diagram type name' "evidence: a diagram_type without a schema in the install is rejected" -- check_candidate "$box/c4.json"
  assert_contains "$output" '"c4"' "evidence: the rejection names the unknown type"

  # `finalize` is upstream's command forwarded unchanged, after the check
  # whenever --repo-root is present — the order D8 rests on is structural.
  # The fixture CLI records the arguments it received instead of drawing.
  printf 'import { writeFileSync } from "node:fs";\nwriteFileSync(process.env.ARGV_LOG, process.argv.slice(2).join(" "));\n' \
    > "$box/fixture-home/archify/bin/archify.mjs"
  finalize() { # <candidate> [args…] — the forwarded argv lands in $box/argv
    rm -f "$box/argv"
    ARCHIFY_HOME="$box/fixture-home" ARGV_LOG="$box/argv" bash "$RESOLVER" finalize architecture "$@" > /dev/null
  }
  assert_refused 1 '"b" has no sources' "finalize: an uncited codebase candidate stops before upstream runs" -- \
    finalize "$box/uncited.json" "$box/out.html" --repo-root "$FIXTURE_REPO" --out-dir "$box/review-1"
  assert_contains "$output" '"b" has no sources' "finalize: the refusal names the uncited component"
  assert_file_absent "$box/argv" "finalize: upstream never received the uncited candidate"
  run finalize "$box/cited.json" "$box/out.html" --repo-root "$FIXTURE_REPO" --out-dir "$box/review-1"
  assert_exit 0 "finalize: a cited candidate passes the check and runs upstream"
  assert_file_exists "$box/argv" "finalize: upstream ran and recorded the arguments it received"
  assert_eq "finalize architecture $box/cited.json $box/out.html --repo-root $FIXTURE_REPO --out-dir $box/review-1" \
    "$(<"$box/argv")" "finalize: upstream's arguments are forwarded unchanged"
  run finalize "$box/freehand.json" "$box/out.html" --out-dir "$box/review-1"
  assert_exit 0 "finalize: a described system (no --repo-root) skips the check"
  assert_file_exists "$box/argv" "finalize: upstream ran for the freehand candidate"
  assert_contains "$(<"$box/argv")" "freehand.json" "finalize: a freehand candidate reaches upstream"
  assert_eq "0" "$(html_written)" "finalize: the fixture run wrote no HTML"
else
  skip "evidence: node is absent on this machine; the candidate-check cases did not run"
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
