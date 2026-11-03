#!/bin/bash
# tests/affected.sh — the test files a change since <base> touches, so /build
# verifies each task and slice without paying for the full suite
# (specs/fewer-full-suite-runs.md). This repository's `Affected tests:`
# command, declared below the AGENTS.md end marker.
#
#   bash tests/affected.sh [--run] <base>
#   bash tests/affected.sh --declared <test file>...
#   bash tests/affected.sh --covering <path> -- <test file>...
#
# Prints one tests/test-*.sh path per line, sorted and unique:
#   - every test file changed or added since <base> — committed, staged,
#     unstaged or untracked;
#   - every test file whose text contains a changed path verbatim;
#   - every test file that declares the artefact it covers — an
#     `under_test <path>` or `py_module <dir>` argument in the file — when a
#     changed path equals that argument or lies under it (a directory covers
#     every file beneath it).
# A change to a runner file (tests/run.sh, tests/lib.sh, tests/affected.sh)
# prints every test file. With nothing selected it prints `affected: none` and
# exits 0. `--run` hands the list to tests/run.sh and exits with its status.
# `--declared` prints `<file> <literal>` for each declaration in the given test
# files; `--covering` prints those among them whose declaration covers <path>.
# They keep the grammar here, so no test reads a declaration with a regex.
#
# A test that builds paths dynamically and declares no artefact is not
# selected; the pre-push full run and PR CI catch what this misses.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  printf 'usage: bash tests/affected.sh [--run] <base>\n' >&2
  printf '       bash tests/affected.sh --declared <test file>...\n' >&2
  printf '       bash tests/affected.sh --covering <path> -- <test file>...\n' >&2
  exit 2
}

# declared_pairs <test file...> — `<file> <literal>` for every declaration made
# through under_test or py_module: the first token after the word, quotes
# stripped. The one place that reads the declaration grammar; a test that needs
# it asks through --declared or --covering below.
declared_pairs() {
  grep -HoE '(under_test|py_module)[[:space:]]+["'"'"']?[^[:space:])"'"'"';]+' -- "$@" \
    | sed -E "s/^([^:]+):(under_test|py_module)[[:space:]]+[\"']?/\1 /"
}

# declared_matches <changed-list-file> <test file...> — each file declaring,
# through under_test or py_module, a path that a changed path (one per line in
# the list file) equals or lies under. A trailing slash is optional and a
# sibling sharing only the name prefix does not match.
declared_matches() {
  local changed_list="$1"; shift
  declared_pairs "$@" \
    | awk 'NR == FNR { changed[$0] = 1; next }
           { dir = $2; sub(/\/+$/, "", dir)
             if (dir == "") next
             for (c in changed) if (c == dir || index(c, dir "/") == 1) { print $1; break } }' "$changed_list" -
}

# Query modes: what a test file declares, and which declarations cover a path.
case "${1:-}" in
  --declared)
    shift; [ $# -gt 0 ] || usage
    declared_pairs "$@" || true
    exit 0 ;;
  --covering)
    [ $# -ge 4 ] && [ "$3" = "--" ] || usage
    changed="$(mktemp)"
    trap 'rm -f "$changed"' EXIT
    printf '%s\n' "$2" > "$changed"
    shift 3
    declared_matches "$changed" "$@" | sort -u
    exit 0 ;;
esac

run=0
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) run=1; shift ;;
    -*) usage ;;
    *) [ -z "$base" ] || usage; base="$1"; shift ;;
  esac
done
[ -n "$base" ] || usage
git rev-parse --verify --quiet "$base^{commit}" >/dev/null \
  || { printf 'tests/affected.sh: unknown base: %s\n' "$base" >&2; exit 2; }

changed="$(mktemp)"
trap 'rm -f "$changed"' EXIT
# --no-renames lists a rename as its old and new path, so a test that still
# names the old one is selected.
{ git -c core.safecrlf=false diff --no-renames --name-only "$base" -- \
    && git ls-files --others --exclude-standard; } | sort -u > "$changed" \
  || { printf 'tests/affected.sh: git could not list the changes since %s\n' "$base" >&2; exit 2; }

shopt -s nullglob
all=(tests/test-*.sh)
if grep -qxE 'tests/(run|lib|affected)\.sh' "$changed"; then
  selected="$(printf '%s\n' "${all[@]}")"
else
  selected="$(
    { grep -xE 'tests/test-[^/]*\.sh' "$changed"
      [ -s "$changed" ] && [ ${#all[@]} -gt 0 ] && grep -lF -f "$changed" -- "${all[@]}"
      [ -s "$changed" ] && [ ${#all[@]} -gt 0 ] && declared_matches "$changed" "${all[@]}"
    } | while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done | sort -u
  )"
fi

if [ -z "$selected" ]; then
  printf 'affected: none\n'
  exit 0
fi
if [ "$run" -eq 0 ]; then
  printf '%s\n' "$selected"
  exit 0
fi
files=()
while IFS= read -r f; do files+=("$f"); done <<<"$selected"
rm -f "$changed"
exec bash tests/run.sh "${files[@]}"
