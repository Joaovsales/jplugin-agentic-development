#!/usr/bin/env bash
# bump-plugin-version.sh — raise .claude-plugin/plugin.json above origin/master.
#
# tests/test-plugin-manifest.sh fails a payload change whose version does not
# rise above its base's. Merging master moves that base forward and can consume
# the number a branch already took, so the bump is re-derived here rather than
# chosen by hand: the version becomes one patch above max(origin/master, this
# tree). A tree already above origin/master is left alone, so a second run is a
# no-op. Run it after merging master (README § Releasing skills). It never
# fetches; the origin/master it compares with is whatever the last fetch left.
# PYTHON overrides the interpreter (default python3).
set -euo pipefail

PLUGIN=".claude-plugin/plugin.json"

fail() { printf 'bump-plugin-version: %s\n' "$1" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)" || fail "not inside a git repository"
[ -f "$PLUGIN" ] || fail "$PLUGIN not found"
git rev-parse -q --verify 'refs/remotes/origin/master^{commit}' >/dev/null \
  || fail "origin/master does not resolve — run 'git fetch origin' first"

base_manifest="$(git show "origin/master:$PLUGIN")" || fail "origin/master has no $PLUGIN"

"${PYTHON:-python3}" - "$PLUGIN" "$base_manifest" <<'PY'
import json, re, sys

path = sys.argv[1]
def semver(text, where):
    if not re.fullmatch(r"\d+\.\d+\.\d+", text):
        sys.exit(f"bump-plugin-version: {where} version {text!r} is not MAJOR.MINOR.PATCH")
    return tuple(int(part) for part in text.split("."))

base = json.loads(sys.argv[2]).get("version", "")
source = open(path, encoding="utf-8", newline="").read()
current = json.loads(source).get("version", "")
base_v, current_v = semver(base, "origin/master"), semver(current, path)
if current_v > base_v:
    print(f"{path} is {current}, already above origin/master's {base} — unchanged")
    sys.exit(0)
major, minor, patch = base_v  # the max: the tree is at or below origin/master here
target = f"{major}.{minor}.{patch + 1}"
updated, count = re.subn(r'("version"\s*:\s*")[^"]*(")', rf"\g<1>{target}\g<2>", source, count=1)
if count != 1:
    sys.exit(f"bump-plugin-version: no version field to rewrite in {path}")
open(path, "w", encoding="utf-8", newline="").write(updated)
print(f"{path}: {current} -> {target} (origin/master carries {base})")
PY
