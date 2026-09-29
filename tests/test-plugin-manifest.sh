#!/bin/bash
# tests/test-plugin-manifest.sh — the Claude Code plugin manifest over the
# canonical skill tree (specs/claude-plugin-manifest.md).
#
# WHY THIS EXISTS
#
# Claude Code users of this workflow load skills through the `jplugin` plugin,
# whose manifest points at `.agents/skills/`. A broken manifest stops every
# skill for every Claude Code user and nothing else notices: Pi and Codex never
# read it, and the suite otherwise only ever looks at the skill bodies. This
# file is the pre-commit guard for the contract in the spec's § Component
# contracts — one plugin, one marketplace entry, one skills path, and the
# invariants that keep the skill bodies harness-neutral.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

PLUGIN=".claude-plugin/plugin.json"
MARKETPLACE=".claude-plugin/marketplace.json"

# Reads one JSON value by dotted path; prints `<missing>` for an absent key so
# a missing field fails the assertion instead of matching an empty expected.
json_get() {
  "$TEST_PYTHON" - "$1" "$2" <<'PY'
import json, sys
try:
    document = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError) as exc:
    print(f"<unreadable: {exc}>")
    sys.exit(0)
node = document
for part in sys.argv[2].split("."):
    if isinstance(node, list) and part.isdigit():
        node = node[int(part)] if int(part) < len(node) else None
    elif isinstance(node, dict):
        node = node.get(part)
    else:
        node = None
    if node is None:
        print("<missing>")
        sys.exit(0)
print(node if isinstance(node, str) else json.dumps(node, sort_keys=True))
PY
}

json_keys() {
  "$TEST_PYTHON" - "$1" <<'PY'
import json, sys
try:
    print(" ".join(sorted(json.load(open(sys.argv[1], encoding="utf-8")))))
except (OSError, ValueError) as exc:
    print(f"<unreadable: {exc}>")
PY
}

# --- 1. both manifests parse ------------------------------------------------
assert_not_contains "$(json_keys "$PLUGIN")" "<unreadable" \
  "plugin.json parses as JSON"
assert_not_contains "$(json_keys "$MARKETPLACE")" "<unreadable" \
  "marketplace.json parses as JSON"

# --- 2. the skills path is the canonical tree, written ./-relative ----------
assert_eq "./.agents/skills" "$(json_get "$PLUGIN" skills)" \
  "plugin.json: skills points at ./.agents/skills (never '.', which needed 2.1.221)"
assert_eq "yes" "$([ -d .agents/skills ] && echo yes || echo no)" \
  "plugin.json: the skills directory exists"

# --- 3. one plugin name, shared by both manifests ---------------------------
assert_eq "jplugin" "$(json_get "$PLUGIN" name)" \
  "plugin.json: name is jplugin (the typed prefix)"
assert_eq "jplugin" "$(json_get "$MARKETPLACE" plugins.0.name)" \
  "marketplace.json: plugins[0].name equals the plugin name"
assert_eq "1" "$(json_get "$MARKETPLACE" plugins | "$TEST_PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)" \
  "marketplace.json: exactly one plugin entry"
assert_eq "./" "$(json_get "$MARKETPLACE" plugins.0.source)" \
  "marketplace.json: the plugin is the marketplace root (source ./)"
assert_eq "jplugin-agentic-development" "$(json_get "$MARKETPLACE" name)" \
  "marketplace.json: name is the GitHub slug, so the install id is jplugin@jplugin-agentic-development"

# --- 4. agents and hooks stay project-level ---------------------------------
PLUGIN_KEYS="$(json_keys "$PLUGIN")"
for forbidden in commands agents hooks; do
  assert_not_contains " $PLUGIN_KEYS " " $forbidden " \
    "plugin.json: no '$forbidden' key — those stay project-level (spec § Decisions)"
done

# --- 5. version is semver ---------------------------------------------------
VERSION="$(json_get "$PLUGIN" version)"
assert_eq "semver" "$(printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo semver || echo "not-semver: $VERSION")" \
  "plugin.json: version is semver"

# --- 6. the template's own settings.json declares the marketplace and plugin --
# Synced to every project by /sync and the CI mirror, so a fresh clone installs
# the plugin when its folder is trusted (Spike S4). No `ref` anywhere: a
# marketplace ref must be a branch or tag, a sha does not clone, and the
# plugin's `version` is what pins a project's copy.
SETTINGS=".claude/settings.json"
MARKET="extraKnownMarketplaces.jplugin-agentic-development.source"
assert_eq "github" "$(json_get "$SETTINGS" "$MARKET.source")" \
  "settings.json: the marketplace is declared as a github source"
assert_eq "Joaovsales/jplugin-agentic-development" "$(json_get "$SETTINGS" "$MARKET.repo")" \
  "settings.json: ... of this repository"
assert_eq "<missing>" "$(json_get "$SETTINGS" "$MARKET.ref")" \
  "settings.json: no ref (the source floats; plugin.json version pins)"
assert_eq "true" "$(json_get "$SETTINGS" "enabledPlugins.jplugin@jplugin-agentic-development")" \
  "settings.json: the plugin is enabled under its install id"
for kept in env.CLAUDE_CODE_AUTO_COMPACT_WINDOW; do
  assert_not_contains "$(json_get "$SETTINGS" "$kept")" "<missing>" \
    "settings.json: the existing $kept block survives the declaration"
done

# --- 7. pinning is by version, never by ref (spec § Decisions, S4) ----------
# `git clone --branch <sha>` fails, so a /sync that wrote the checked-out sha as
# `ref` left every downstream project with a marketplace that never registers.
# Claude Code pins a plugin by its manifest version and refreshes only when it
# changes; the runbook has to say so or nobody bumps it.
SYNC_SKILL=".agents/skills/sync/SKILL.md"
assert_not_contains "$(cat "$SYNC_SKILL")" '["ref"]' \
  "sync Step 5: writes no ref into the project's marketplace source"
assert_file_contains "$SYNC_SKILL" '`version` pins' \
  "sync Step 5: names plugin.json version as the pin"
assert_file_contains README.md 'bump `version`' \
  "README § Keeping It Up to Date: tells the maintainer to bump version on release"

# --- 8. the verify skill is verify-evidence (spec § Decisions, S2) -----------
# Claude Code ships a bundled skill named `verify`; once no un-namespaced copy
# shadows it, a bare `/verify` routes to Anthropic's skill, whose contract
# ("don't run tests") contradicts this one. The name is retired and every
# reference outside the historical logs follows it. This file holds the pattern
# and is excluded; `verify-deployment`, `verify-e2e` and `verify-<app>`
# are a different family and stay.
assert_eq "no" "$([ -e .agents/skills/verify ] && echo yes || echo no)" \
  "rename: .agents/skills/verify/ no longer exists"
assert_file_contains .agents/skills/verify-evidence/SKILL.md "name: verify-evidence" \
  "rename: verify-evidence/SKILL.md carries its own name in the frontmatter"
BARE_VERIFY='(^|[^A-Za-z0-9_/-])/verify([^A-Za-z0-9_-]|$)'
assert_eq "" "$(git grep -l -E "$BARE_VERIFY" -- . ':!tasks' ':!specs' ':!tests/test-plugin-manifest.sh' 2>/dev/null | paste -sd' ' -)" \
  "rename: no bare /verify reference survives in any tracked file outside tasks/ and specs/"

# --- 9. one tree, one namespace sentence (spec § Decisions, AC 1, AC 9) -----
# The byte-identical `.claude/skills/` copy is gone: Claude Code loads
# `.agents/skills/` through the plugin. Skill bodies stay harness-neutral (no
# `jplugin:` literal — Pi and Codex have no namespace), and the AGENTS.md managed
# block states the mapping exactly once so a reader of `/name` knows what to type.
assert_eq "absent" "$([ -e .claude/skills ] && echo present || echo absent)" \
  "one tree: .claude/skills/ no longer exists in the template"
assert_eq "" "$(git grep -l 'jplugin:' -- .agents/skills .claude/agents PI_SETUP.md 2>/dev/null | paste -sd' ' -)" \
  "one tree: no skill body, agent persona or PI_SETUP.md hardcodes the jplugin: namespace"
assert_eq "1" "$(grep -cF 'is typed `/jplugin:name`' AGENTS.md)" \
  "one tree: AGENTS.md states the namespace mapping exactly once"

# --- 10. a payload change bumps version (specs/plugin-staleness-check.md D5-D7) --
# `claude plugin update` compares versions only (measured, spec § Why a bump is
# required): a merge that changes the payload without a bump never reaches any
# install. 1.1.0 shipped with #177 and six payload merges followed unbumped.
# The base is $PLUGIN_VERSION_BASE, else HEAD^1 when HEAD is already on
# origin/master (a push to master), else the merge base with origin/master (a
# pull_request merge checkout, or a local branch). CI checks out fetch-depth 0.
# Every directory a skill or hook reads through ${CLAUDE_PLUGIN_ROOT} is payload;
# the coverage assertion after the fixtures keeps this list from falling behind.
PAYLOAD_PATHS=(.agents/skills .agents/hooks .agents/references hooks)
version_base() {  # version_base -> the commit this tree's version is compared with
  if [ -n "${PLUGIN_VERSION_BASE:-}" ]; then printf '%s\n' "$PLUGIN_VERSION_BASE"; return 0; fi
  git rev-parse -q --verify 'refs/remotes/origin/master^{commit}' >/dev/null 2>&1 || return 1
  if git merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
    git rev-parse -q --verify 'HEAD^1^{commit}'
  else
    git merge-base HEAD origin/master
  fi
}
json_version() { "$TEST_PYTHON" -c 'import json, sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true; }
version_greater() {  # version_greater <new> <old>
  "$TEST_PYTHON" -c 'import sys; v = lambda s: tuple(int(p) for p in s.split(".")); sys.exit(0 if v(sys.argv[1]) > v(sys.argv[2]) else 1)' "$1" "$2" 2>/dev/null
}
version_verdict() {  # version_verdict -> "ok: ...", "fail: ..." or "skip: ..." for the repository in cwd
  local base old new
  if ! base=$(version_base 2>/dev/null) || [ -z "$base" ]; then
    echo "skip: no base resolves (no origin/master, no PLUGIN_VERSION_BASE)"; return
  fi
  if git diff --quiet "$base" -- "${PAYLOAD_PATHS[@]}" 2>/dev/null; then
    echo "ok: payload unchanged since ${base:0:7}"; return
  fi
  old=$(git show "$base:$PLUGIN" 2>/dev/null | json_version)
  new=$(json_version < "$PLUGIN")
  if version_greater "$new" "$old"; then echo "ok: $old -> $new"; return; fi
  echo "fail: payload changed since ${base:0:7} but $PLUGIN version went '$old' -> '$new' (README § Releasing skills)"
}

F=$(mktemp -d)
fixture_commit() {  # fixture_commit <version> <skill-text> -> commits both in $F
  ( cd "$F" && printf '{"name": "jplugin", "version": "%s"}\n' "$1" > "$PLUGIN" \
    && printf '%s\n' "$2" > .agents/skills/x/SKILL.md && git add -A && git commit -qm "$2" )
}
verdict_in_fixture() { ( cd "$F" && version_verdict ); }
if [ -n "$F" ] && ( cd "$F" && git init -q -b master && git config user.email t@t && git config user.name t \
     && mkdir -p .claude-plugin .agents/skills/x ) >/dev/null 2>&1; then
  fixture_commit 1.0.0 v1 >/dev/null 2>&1
  ( cd "$F" && git update-ref refs/remotes/origin/master HEAD && git checkout -qb feature \
    && printf 'docs\n' > NOTES.md && git add NOTES.md && git commit -qm docs ) >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "ok: payload unchanged" \
    "version guard: a change outside the payload needs no bump"
  fixture_commit 1.0.0 v2 >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "fail: payload changed" \
    "version guard: a branch that changes the payload without a bump fails"
  fixture_commit 1.0.1 v3 >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "ok: 1.0.0 -> 1.0.1" \
    "version guard: the same branch with the version increased passes"
  fixture_commit 0.9.0 v4 >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "fail: payload changed" \
    "version guard: a decreased version fails"
  ( cd "$F" && git update-ref refs/remotes/origin/master HEAD ) >/dev/null 2>&1
  fixture_commit 0.9.0 v5 >/dev/null 2>&1
  ( cd "$F" && git update-ref refs/remotes/origin/master HEAD ) >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "fail: payload changed" \
    "version guard: on a push to master, HEAD^1 is the base and an unbumped payload commit fails"
  assert_contains "$( cd "$F" && PLUGIN_VERSION_BASE=HEAD version_verdict )" "ok: payload unchanged" \
    "version guard: PLUGIN_VERSION_BASE overrides the base"
  ( cd "$F" && git update-ref -d refs/remotes/origin/master ) >/dev/null 2>&1
  assert_contains "$(verdict_in_fixture)" "skip: no base resolves" \
    "version guard: no origin/master and no PLUGIN_VERSION_BASE skips"
else
  assert_eq "created" "failed" "version guard: the fixture repository could not be created"
fi
rm -rf "$F"

RUNTIME_READS="$(git grep -hoE '\$\{?CLAUDE_PLUGIN_ROOT\}?/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?' -- "${PAYLOAD_PATHS[@]}" 2>/dev/null \
  | sed -E 's#^\$\{?CLAUDE_PLUGIN_ROOT\}?/##' | sort -u)"
assert_contains "$RUNTIME_READS" ".agents/references" "version guard: the runtime-read scan finds the plugin-root reads (non-vacuity)"
UNCOVERED=""
for read_path in $RUNTIME_READS; do
  covered=no
  for payload in "${PAYLOAD_PATHS[@]}"; do
    case "$read_path/" in "$payload"/*) covered=yes ;; esac
  done
  if [ "$covered" = no ]; then UNCOVERED="$UNCOVERED $read_path"; fi
done
assert_eq "" "$UNCOVERED" "version guard: every \${CLAUDE_PLUGIN_ROOT} read lies under PAYLOAD_PATHS"

REPO_VERDICT="$(version_verdict)"
case "$REPO_VERDICT" in skip:*) printf '  note %s\n' "version guard skipped on this checkout — $REPO_VERDICT" ;; esac
assert_not_contains "$REPO_VERDICT" "fail:" "version guard: this tree's payload changes carry a version bump — $REPO_VERDICT"
assert_prose_contains README.md '`claude plugin update` compares versions only' \
  "README § Releasing skills: states that plugin update ignores an unbumped commit"
assert_prose_contains README.md 'measured on Claude Code 2.1.277' \
  "README § Releasing skills: ... as a measured behaviour, not a belief"
assert_prose_contains README.md '`tests/test-plugin-manifest.sh` fails a change to the plugin payload that does not bump it' \
  "README § Releasing skills: names the suite as the enforcement"

finish
