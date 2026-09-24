#!/usr/bin/env bash
# Tests for the html-presentation base generator (generate-presentation.py).
# Pins the `--markdown -` (stdin) path, which the skill's own docs advertise at
# generate-presentation.py:15 but no test exercised.
#
# Method: PYTHONIOENCODING forces a non-UTF-8 default on every platform, so these
# are real regression pins on Linux CI too, not just on Windows. It reaches
# `sys.stdin` (a TextIOWrapper) and NOT `sys.stdin.buffer` (the raw layer the fix
# reads) -- that asymmetry IS the test, so § 0 asserts it rather than assuming it.
# Without that guard, a stripped variable would make every pin below pass against
# the broken code.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL="$REPO_ROOT/.agents/skills/html-presentation/scripts/generate-presentation.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Runs the generator under the hostile default encoding, piping $2 in on stdin.
# Dumps the child's own output when it exits non-zero, so a red CI run carries
# the traceback instead of a bare exit code. Sets $RC; never aborts under set -u.
run_stdin() {
  local script="$1" input="$2" out="$3" log="$TMP/run.log"
  PYTHONIOENCODING=cp1252 "$TEST_PYTHON" "$script" --markdown - -o "$out" \
    <"$input" >"$log" 2>&1
  RC=$?
  [ "$RC" -eq 0 ] || { printf '       --- generator output ---\n'; sed 's/^/       /' "$log"; }
  LOG_TEXT="$(cat "$log")"
}

# --- 0. The method itself, asserted -------------------------------------------
# If PYTHONIOENCODING ever stops reaching sys.stdin, every assertion below goes
# vacuous: they would all pass against `sys.stdin.read()`. Fail loudly instead.
STDIN_ENC="$(PYTHONIOENCODING=cp1252 "$TEST_PYTHON" -c 'import sys; print(sys.stdin.encoding)' </dev/null 2>&1)"
assert_eq "cp1252" "$STDIN_ENC" "PYTHONIOENCODING reaches sys.stdin (guards every pin below from going vacuous)"

# --- 1. The reported defect: UTF-8 markdown piped in on stdin ------------------
# Box rules, an arrow and an em-dash: what the html-presentation skill routinely
# emits. `┐` (U+2510) matters specifically -- its UTF-8 byte 0x90 is UNDEFINED in
# cp1252, so a reverted generator rejects this input outright rather than mangling.
MD="$TMP/deck.md"
cat >"$MD" <<'MD_EOF'
# Prêt à rendre

Box rules, arrows and em-dashes — the common case, not an edge one.

## Diagramme

┌──────────────┐
│ stdin → HTML │
└──────────────┘
MD_EOF

# The canonical tree is the only copy: Claude Code loads it through the jplugin
# plugin, so this run is what catches a drift in generate-presentation.py's output.
for TREE in ".agents"; do
  OUT="$TMP/stdin-$TREE.html"
  run_stdin "$REPO_ROOT/$TREE/skills/html-presentation/scripts/generate-presentation.py" "$MD" "$OUT"
  assert_eq "0" "$RC" "($TREE) stdin path exits 0 under a non-UTF-8 default encoding"

  assert_file_contains "$OUT" "┌──────────────┐" "($TREE) stdin: box rule survives verbatim"
  assert_file_contains "$OUT" "stdin → HTML" "($TREE) stdin: arrow survives verbatim"
  assert_file_contains "$OUT" "em-dashes — the common case" "($TREE) stdin: em-dash survives verbatim"
  assert_file_contains "$OUT" "Prêt à rendre" "($TREE) stdin: accented title survives verbatim"
done

# Control: the `--markdown <file>` branch renders the same needles. Without it, a
# needle that stopped rendering at all would satisfy the absence check in § 2 for
# the wrong reason.
FILE_OUT="$TMP/file.html"
PYTHONIOENCODING=cp1252 "$TEST_PYTHON" "$CANONICAL" --markdown "$MD" -o "$FILE_OUT" >"$TMP/file.log" 2>&1
FILE_RC=$?
[ "$FILE_RC" -eq 0 ] || sed 's/^/       /' "$TMP/file.log"
assert_eq "0" "$FILE_RC" "file path exits 0 under a non-UTF-8 default encoding"
assert_file_contains "$FILE_OUT" "┌──────────────┐" "file path: box rule survives verbatim"
assert_file_contains "$FILE_OUT" "stdin → HTML" "file path: arrow survives verbatim"

# --- 2. The mangling path, with a fixture that can actually reach it -----------
# § 1 cannot exercise mojibake: its 0x90 byte makes a reverted generator abort
# instead. Every byte here IS cp1252-decodable (C3 AA / C3 A0 / E2 80 94), so a
# reverted generator exits 0 and writes mangled text -- which is the silent
# failure mode this assertion exists to catch.
MOJI="$TMP/moji.md"
printf '# Pr\xc3\xaat \xc3\xa0 rendre\n\nUn tiret \xe2\x80\x94 cadratin.\n' >"$MOJI"
MOJI_OUT="$TMP/moji.html"
run_stdin "$CANONICAL" "$MOJI" "$MOJI_OUT"
assert_eq "0" "$RC" "mojibake fixture: exits 0"
assert_file_contains "$MOJI_OUT" "Prêt à rendre" "mojibake fixture: accented text survives verbatim"
assert_file_contains "$MOJI_OUT" "tiret — cadratin" "mojibake fixture: em-dash survives verbatim"
assert_not_contains "$(cat "$MOJI_OUT")" "Ãª" "mojibake fixture: no cp1252-mangled ê in output"
assert_not_contains "$(cat "$MOJI_OUT")" "â€" "mojibake fixture: no cp1252-mangled em-dash in output"

# --- 3. A BOM must not swallow the document -----------------------------------
# decode("utf-8") retains U+FEFF, which defeats the `^#\s+` H1 match and drops the
# title AND every section -- exit 0, no warning. utf-8-sig defines that away.
BOM="$TMP/bom.md"
printf '\xef\xbb\xbf# Titre avec BOM\n\nCorps du document.\n\n## Section Un\n\nContenu.\n' >"$BOM"
BOM_OUT="$TMP/bom.html"
run_stdin "$CANONICAL" "$BOM" "$BOM_OUT"
assert_eq "0" "$RC" "BOM fixture: exits 0"
assert_file_contains "$BOM_OUT" "<title>Titre avec BOM</title>" "BOM fixture: BOM'd H1 becomes the title"
assert_file_contains "$BOM_OUT" "Section Un" "BOM fixture: sections after a BOM'd H1 survive"
assert_not_contains "$(cat "$BOM_OUT")" "<title>Presentation</title>" \
  "BOM fixture: title does not silently fall back to the default"

# --- 4. Genuinely non-UTF-8 stdin fails loudly --------------------------------
# The only new branch the fix adds beyond the happy path. decode() is strict by
# design: a fallback here would be silent mojibake, which AGENTS.md § No Silent
# Failures forbids. Pin the loud contract -- non-zero, named cause, no artifact.
BAD="$TMP/bad.md"
printf '# Titre\n\nCaf\xe9 en latin-1.\n' >"$BAD"
BAD_OUT="$TMP/bad.html"
PYTHONIOENCODING=cp1252 "$TEST_PYTHON" "$CANONICAL" --markdown - -o "$BAD_OUT" \
  <"$BAD" >"$TMP/bad.log" 2>&1
BAD_RC=$?
assert_eq "1" "$BAD_RC" "invalid UTF-8 on stdin: exits non-zero rather than mangling"
assert_contains "$(cat "$TMP/bad.log")" "UnicodeDecodeError" \
  "invalid UTF-8 on stdin: failure names the decoding problem"
if [ -f "$BAD_OUT" ]; then BAD_ARTIFACT="present"; else BAD_ARTIFACT="absent"; fi
assert_eq "absent" "$BAD_ARTIFACT" "invalid UTF-8 on stdin: wrote no artifact"

finish
