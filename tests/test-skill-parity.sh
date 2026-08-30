# tests/test-skill-parity.sh — full-tree .agents/skills ↔ .claude/skills parity.
#
# Convention: .agents/skills/ is canonical; .claude/skills/ is a byte-identical
# backwards-compat copy, EXCEPT an explicit allowlist of Claude-only extras.
# Any drift fails this test. Edit skills in .agents/skills/ first, then copy.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CANONICAL=".agents/skills"
COMPAT=".claude/skills"

# Entries allowed to exist only in .claude/skills (Claude Code-specific tooling
# or human-facing notes). Everything else must be byte-identical across trees.
ALLOWLIST="README.md setup-deployment verify-deployment"

# Git-ignored files are build residue, not skill content: a __pycache__ written
# by running one tree's scripts is not drift the author can fix by copying. They
# are skipped in both directions so this guard reports authored divergence only.
is_ignored() {
  git check-ignore -q "$1" 2>/dev/null
}

is_allowlisted() {
  local rel="$1"
  local entry
  for entry in $ALLOWLIST; do
    case "$rel" in
      "$entry"|"$entry"/*) return 0 ;;
    esac
  done
  return 1
}

# 1. Every canonical file must exist in compat, byte-identical
while IFS= read -r -d '' f; do
  is_ignored "$f" && continue
  rel="${f#"$CANONICAL"/}"
  assert_files_identical "$f" "$COMPAT/$rel" "Parity: $rel identical across trees"
done < <(find "$CANONICAL" -type f -print0 | sort -z)

# 2. No non-allowlisted compat-only entries
while IFS= read -r -d '' f; do
  is_ignored "$f" && continue
  rel="${f#"$COMPAT"/}"
  if [ ! -e "$CANONICAL/$rel" ] && ! is_allowlisted "$rel"; then
    _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
    printf '  FAIL Parity: %s exists only in %s (port to canonical or add to allowlist)\n' "$rel" "$COMPAT"
  fi
done < <(find "$COMPAT" -type f -print0 | sort -z)

# 3. Allowlisted entries still exist (guards against stale allowlist)
for entry in $ALLOWLIST; do
  assert_eq "present" "$([ -e "$COMPAT/$entry" ] && echo present || echo missing)" \
    "Parity: allowlisted Claude-only entry $entry still present"
done

finish
