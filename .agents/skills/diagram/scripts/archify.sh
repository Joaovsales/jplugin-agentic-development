#!/usr/bin/env bash
# archify.sh — /diagram's resolver for the installed Archify tool.
#
#   eval "$(bash .agents/skills/diagram/scripts/archify.sh resolve)"
#
# Archify is a pinned tool under $ARCHIFY_HOME (default
# ~/.local/share/jplugin/archify), installed by install.sh or by the one
# command this script prints — never a skill the harness can route to, never a
# copy in the repository (specs/diagram-skill.md D1, D11). `resolve` answers
# the three questions every /diagram run asks before it reads upstream's
# SKILL.md, and answers them the same way on every harness:
#
#   1. Is the tool there?        absent → the install command, exit 1
#   2. Is Node >= 18 on PATH?    absent or older → named, exit 1
#   3. Which browser runs the browser gate?  ARCHIFY_CHROME when set, else a
#      Chrome/Chromium on PATH, else the Chromium playwright-cli installed;
#      none → the non-browser gates still run and the reply must say so (D3).
#
# stdout carries only `export NAME=VALUE` lines, safe to `eval`; every note is
# on stderr. Nothing here writes a diagram: a non-zero exit means no HTML.
set -uo pipefail

ARCHIFY_REPO="https://github.com/tt-a1i/archify"
ARCHIFY_TAG="v3.2.0"
ARCHIFY_HOME="${ARCHIFY_HOME:-$HOME/.local/share/jplugin/archify}"
NODE_MIN=18
# The reply carries this phrase verbatim when no browser ran.
NO_BROWSER_MARKER="automated checks passed without browser evidence"

note() { printf 'archify: %s\n' "$1" >&2; }

# The install command, one line, identical to install.sh's step 6c. A sparse
# clone of the pinned tag keeps only the skill package and its licence (25 MB
# instead of 140 MB); `git rev-parse HEAD` on it is the tag's commit.
install_command() {
  printf 'git clone --depth 1 --branch %s --filter=blob:none --sparse %s "%s" && git -C "%s" sparse-checkout set --no-cone /archify/ /LICENSE\n' \
    "$ARCHIFY_TAG" "$ARCHIFY_REPO" "$ARCHIFY_HOME" "$ARCHIFY_HOME"
}

check_tool() {
  if [ -f "$ARCHIFY_HOME/archify/bin/archify.mjs" ] && [ -f "$ARCHIFY_HOME/archify/SKILL.md" ]; then
    return 0
  fi
  note "Archify is not installed under $ARCHIFY_HOME (set ARCHIFY_HOME for another root). Install it with:"
  install_command >&2
  return 1
}

check_node() {
  local version major
  if ! command -v node >/dev/null 2>&1; then
    note "node is not on PATH — Archify requires Node >= $NODE_MIN, so /diagram cannot run"
    return 1
  fi
  version="$(node --version 2>/dev/null)"
  major="${version#v}"; major="${major%%.*}"
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  if [ "$major" -lt "$NODE_MIN" ]; then
    note "node ${version:-(unknown version)} is too old — Archify requires Node >= $NODE_MIN, so /diagram cannot run"
    return 1
  fi
}

# The newest Chromium playwright-cli installed, or nothing. Playwright honours
# PLAYWRIGHT_BROWSERS_PATH and otherwise keeps one cache root per platform.
playwright_chromium() {
  local root candidate build best="" best_build=-1
  for root in "${PLAYWRIGHT_BROWSERS_PATH:-}" \
              "$HOME/.cache/ms-playwright" \
              "$HOME/Library/Caches/ms-playwright" \
              "${LOCALAPPDATA:-}/ms-playwright"; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    for candidate in "$root"/chromium-*/chrome-linux/chrome \
                     "$root"/chromium-*/chrome-mac*/Chromium.app/Contents/MacOS/Chromium \
                     "$root"/chromium-*/chrome-win/chrome.exe; do
      [ -x "$candidate" ] || continue
      build="${candidate#"$root"/chromium-}"; build="${build%%/*}"
      case "$build" in ''|*[!0-9]*) build=0 ;; esac
      if [ "$build" -gt "$best_build" ]; then best="$candidate"; best_build="$build"; fi
    done
  done
  printf '%s\n' "$best"
}

resolve_browser() {
  local name found
  if [ -n "${ARCHIFY_CHROME:-}" ]; then
    printf 'export ARCHIFY_CHROME=%q\n' "$ARCHIFY_CHROME"
    return 0
  fi
  for name in google-chrome google-chrome-stable chromium chromium-browser chrome; do
    if found="$(command -v "$name" 2>/dev/null)" && [ -n "$found" ]; then
      printf 'export ARCHIFY_CHROME=%q\n' "$found"
      return 0
    fi
  done
  found="$(playwright_chromium)"
  if [ -n "$found" ]; then
    printf 'export ARCHIFY_CHROME=%q\n' "$found"
    return 0
  fi
  note "no Chrome or Chromium found on PATH or from playwright-cli — finalize runs validate, deliver and check only; the reply must say: $NO_BROWSER_MARKER"
}

resolve() {
  check_tool || return 1
  check_node || return 1
  printf 'export ARCHIFY_HOME=%q\n' "$ARCHIFY_HOME"
  printf 'export ARCHIFY_BIN=%q\n' "$ARCHIFY_HOME/archify/bin/archify.mjs"
  printf 'export ARCHIFY_SKILL=%q\n' "$ARCHIFY_HOME/archify/SKILL.md"
  resolve_browser
}

# check-candidate <candidate.json> --repo-root <dir> — the pre-finalize evidence
# check for a codebase diagram (D8), in Node because that is what Archify needs
# anyway: meta.repository pinned to the repository's HEAD and `sources` on every
# primary element, which collection is primary read from the install's own
# schemas. Silent on success; each problem on stderr, exit 1.
check_candidate() {
  node "$(dirname "${BASH_SOURCE[0]}")/check-candidate.mjs" "$@" --schemas "$ARCHIFY_HOME/archify/schemas"
}

# finalize <type> <candidate.json> <output.html> [upstream arguments…] —
# upstream's finalize, forwarded unchanged, after the evidence check whenever
# --repo-root is among the arguments. The check→finalize order D8 rests on is
# structural here rather than prose, and this wrapper knows no upstream flag
# but that one (D17).
finalize() {
  local args=("$@") repo_root="" i
  check_tool || return 1
  check_node || return 1
  for ((i = 0; i < ${#args[@]}; i++)); do
    [ "${args[i]}" = "--repo-root" ] && repo_root="${args[i + 1]:-}"
  done
  if [ -n "$repo_root" ]; then
    check_candidate "${2:-}" --repo-root "$repo_root" || return 1
  fi
  exec node "$ARCHIFY_HOME/archify/bin/archify.mjs" finalize "$@"
}

case "${1:-resolve}" in
  resolve) resolve ;;
  install-command) install_command ;;
  check-candidate) shift; check_node && check_candidate "$@" ;;
  finalize) shift; finalize "$@" ;;
  *) note "usage: archify.sh [resolve|install-command|check-candidate <candidate.json> --repo-root <dir>|finalize <type> <candidate.json> <output.html> [args…]]"; exit 2 ;;
esac
