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
  python3 - "$1" "$2" <<'PY'
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
  python3 - "$1" <<'PY'
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
assert_eq "1" "$(json_get "$MARKETPLACE" plugins | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)" \
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
# Synced to every project by /sync and the CI mirror, so a fresh clone is
# offered the plugin on first open. No `ref` here: the template itself floats;
# /sync Step 5 writes the checked-out sha into each project's copy.
SETTINGS=".claude/settings.json"
MARKET="extraKnownMarketplaces.jplugin-agentic-development.source"
assert_eq "github" "$(json_get "$SETTINGS" "$MARKET.source")" \
  "settings.json: the marketplace is declared as a github source"
assert_eq "Joaovsales/jplugin-agentic-development" "$(json_get "$SETTINGS" "$MARKET.repo")" \
  "settings.json: ... of this repository"
assert_eq "<missing>" "$(json_get "$SETTINGS" "$MARKET.ref")" \
  "settings.json: the template copy carries no ref (it floats; /sync pins each project's copy)"
assert_eq "true" "$(json_get "$SETTINGS" "enabledPlugins.jplugin@jplugin-agentic-development")" \
  "settings.json: the plugin is enabled under its install id"
for kept in hooks.Stop hooks.PreCompact env.CLAUDE_CODE_AUTO_COMPACT_WINDOW; do
  assert_not_contains "$(json_get "$SETTINGS" "$kept")" "<missing>" \
    "settings.json: the existing $kept block survives the declaration"
done

finish
