#!/bin/bash
# tests/affected.sh — the test files a change since <base> touches, so /build
# verifies each task and slice without paying for the full suite
# (specs/fewer-full-suite-runs.md). This repository's `Affected tests:`
# command, declared below the AGENTS.md end marker.
#
#   bash tests/affected.sh [--run] <base>
#
# Prints one tests/test-*.sh path per line, sorted and unique:
#   - every test file changed or added since <base> — committed, staged,
#     unstaged or untracked;
#   - every test file whose text contains a changed path verbatim.
# A change to a runner file (tests/run.sh, tests/lib.sh, tests/affected.sh)
# prints every test file. With nothing selected it prints `affected: none` and
# exits 0. `--run` hands the list to tests/run.sh and exits with its status.
#
# A test that builds paths dynamically is not selected by a verbatim match;
# the pre-push full run and PR CI catch what this misses.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  printf 'usage: bash tests/affected.sh [--run] <base>\n' >&2
  exit 2
}

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
{ git -c core.safecrlf=false diff --name-only "$base" --; git ls-files --others --exclude-standard; } | sort -u > "$changed"

shopt -s nullglob
all=(tests/test-*.sh)
if grep -qxE 'tests/(run|lib|affected)\.sh' "$changed"; then
  selected="$(printf '%s\n' "${all[@]}")"
else
  selected="$(
    { grep -xE 'tests/test-[^/]*\.sh' "$changed"
      [ -s "$changed" ] && [ ${#all[@]} -gt 0 ] && grep -lF -f "$changed" -- "${all[@]}"
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
mapfile -t files <<<"$selected"
rm -f "$changed"
exec bash tests/run.sh "${files[@]}"
