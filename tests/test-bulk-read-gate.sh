# tests/test-bulk-read-gate.sh — the PreToolUse bulk-read gate behaviour matrix.
#
# Spec: specs/bulk-read-gate.md. The gate denies a read that would put more
# than BULK_READ_MIN_LINES lines (default 350) of one file into the calling
# model's context, and points at the two allowed alternatives: dispatch
# `bulk-reader` with a question, or read only the range an edit needs. It never
# rewrites the call and never reads the content itself — it counts lines.
#
# Every case feeds the hook the JSON a harness would (`tool_name` +
# `tool_input`) and asserts exit code, stdout shape, and reason text. Fixtures
# are generated under a temp dir so the test never depends on the size of a
# real repo file.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

HOOK=".claude/hooks/bulk-read-gate.py"

if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi

assert_eq "present" "$([ -f "$HOOK" ] && echo present || echo missing)" \
  "Gate: $HOOK exists"

BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/with space"
seq 1 400 > "$BOX/big.txt"
seq 1 100 > "$BOX/small.txt"
seq 1 400 > "$BOX/with space/big.txt"
printf 'a\0b\n' > "$BOX/binary.bin"
mkdir -p "$BOX/a-dir"

# Python on Windows is native and cannot open a /tmp/... Git Bash path. Mixed
# form (C:/...) is understood by Python, by the shell, and by JSON without any
# backslash escaping, so every path below goes through it.
if command -v cygpath >/dev/null 2>&1; then FIX="$(cygpath -m "$BOX")"; else FIX="$BOX"; fi
BIG="$FIX/big.txt"
SMALL="$FIX/small.txt"
SPACED="$FIX/with space/big.txt"
MISSING="$FIX/does-not-exist.txt"
BINARY="$FIX/binary.bin"
ADIR="$FIX/a-dir"

# run_hook <json> — sets OUT, ERR, RC. Extra env goes through the caller's
# environment (`BULK_READ_GATE=off run_hook ...`).
run_hook() {
  OUT="$(printf '%s' "$1" | "$PY" "$HOOK" 2>"$BOX/stderr")"
  RC=$?
  ERR="$(cat "$BOX/stderr")"
}

read_json()  { printf '{"tool_name": "Read", "tool_input": {"file_path": "%s"%s}}' "$1" "${2:-}"; }
shell_json() { printf '{"tool_name": "%s", "tool_input": {"command": "%s"}}' "$1" "$2"; }

# expect_deny <label> <line-count> — the deny contract: exit 0, Claude/Codex
# deny JSON on stdout, reason names bulk-reader, the line count, the threshold.
expect_deny() {
  assert_eq "0" "$RC" "Gate: $1 exits 0 (deny is a decision, not an error)"
  assert_contains "$OUT" '"hookEventName": "PreToolUse"' "Gate: $1 emits a PreToolUse decision"
  assert_contains "$OUT" '"permissionDecision": "deny"' "Gate: $1 is denied"
  printf '%s' "$OUT" | "$PY" -c 'import json, sys; json.load(sys.stdin)' >/dev/null 2>&1
  assert_eq "0" "$?" "Gate: $1 deny payload is one valid JSON object"
  assert_contains "$OUT" 'bulk-reader' "Gate: $1 reason names the bulk-reader alternative"
  assert_contains "$OUT" "$2 lines" "Gate: $1 reason states the line count ($2)"
  assert_contains "$OUT" "${BULK_READ_MIN_LINES:-350}" "Gate: $1 reason states the threshold"
  assert_eq "" "$ERR" "Gate: $1 writes nothing to stderr"
}

# expect_allow <label> — the silent success path: exit 0, no output at all.
expect_allow() {
  assert_eq "0" "$RC" "Gate: $1 exits 0"
  assert_eq "" "$OUT" "Gate: $1 is allowed silently (no stdout)"
  assert_eq "" "$ERR" "Gate: $1 writes nothing to stderr"
}

# expect_error <label> — internal error: exit 1, one structured line on stderr,
# nothing on stdout (a silent allow here would hide a broken gate).
expect_error() {
  assert_eq "1" "$RC" "Gate: $1 exits 1"
  assert_eq "" "$OUT" "Gate: $1 emits no decision on stdout"
  assert_contains "$ERR" "bulk-read-gate" "Gate: $1 names itself on stderr"
}

# --- 1. Read tool -------------------------------------------------------------
run_hook "$(read_json "$BIG")";                              expect_deny  "Read whole 400-line file" 400
run_hook "$(read_json "$BIG" ', "offset": 1, "limit": 50')"; expect_allow "Read ranged limit 50"
run_hook "$(read_json "$BIG" ', "offset": 1, "limit": 400')"; expect_deny "Read ranged limit 400" 400
run_hook "$(read_json "$SMALL")";                            expect_allow "Read whole 100-line file"
run_hook "$(read_json "$MISSING")";                          expect_allow "Read missing path"
run_hook "$(read_json "$BINARY")";                           expect_allow "Read binary file"
run_hook "$(read_json "$ADIR")";                             expect_allow "Read directory"

# Exactly at the threshold is allowed; strictly greater denies.
seq 1 350 > "$BOX/edge.txt"
run_hook "$(read_json "$FIX/edge.txt")";                     expect_allow "Read 350-line file (at threshold)"
seq 1 351 > "$BOX/edge.txt"
run_hook "$(read_json "$FIX/edge.txt")";                     expect_deny  "Read 351-line file (over threshold)" 351

# --- 2. Bash tool: final pipeline stage decides --------------------------------
run_hook "$(shell_json Bash "cat $BIG")";                    expect_deny  "Bash cat big" 400
run_hook "$(shell_json Bash "cat $BIG | grep x")";           expect_allow "Bash cat big | grep x"
run_hook "$(shell_json Bash "sed -n '1,50p' $BIG")";         expect_allow "Bash sed -n 1,50p"
run_hook "$(shell_json Bash "sed -n '1,400p' $BIG")";        expect_deny  "Bash sed -n 1,400p" 400
run_hook "$(shell_json Bash "head -n 400 $BIG")";            expect_deny  "Bash head -n 400" 400
run_hook "$(shell_json Bash "head -n 20 $BIG")";             expect_allow "Bash head -n 20"
run_hook "$(shell_json Bash "cat $SMALL")";                  expect_allow "Bash cat small"
run_hook "$(shell_json Bash "cat $MISSING")";                expect_allow "Bash cat missing"
run_hook "$(shell_json Bash "wc -l $BIG")";                  expect_allow "Bash unrecognised command"
run_hook "$(shell_json Bash "cd $FIX && cat big.txt | wc -l")"; expect_allow "Bash compound command ending in a pipe"
run_hook "$(shell_json Bash "cat \\\"$SPACED\\\"")";         expect_deny  "Bash cat quoted path with spaces" 400
run_hook "$(shell_json Bash "cd $FIX && cat $BIG")";         expect_deny  "Bash compound command ending in a read" 400
# Every `;`/`&&`/`||`/`&`/newline-separated list prints into the tool result, so
# each list's final pipe stage is gated — not only the last one on the line.
run_hook "$(shell_json Bash "cat $BIG && echo ok")";         expect_deny  "Bash cat big && echo ok" 400
run_hook "$(shell_json Bash "cat $BIG; true")";              expect_deny  "Bash cat big; true" 400
run_hook "$(shell_json Bash "cat $BIG &")";                  expect_deny  "Bash cat big & (background list)" 400
run_hook "$(shell_json Bash "ls\\ncat $BIG")";               expect_deny  "Bash newline-separated cat big" 400
run_hook "$(shell_json Bash "echo hi; cat $BIG | grep x")";  expect_allow "Bash list whose final stage is a pipe"
# Redirections are not separators and not paths: stderr merges keep stdout in the
# tool result, stdout to a file takes it out, `< path` is the path being printed.
run_hook "$(shell_json Bash "cat $BIG 2>&1")";               expect_deny  "Bash cat big 2>&1" 400
run_hook "$(shell_json Bash "cat $BIG 2> $FIX/err.txt")";    expect_deny  "Bash cat big 2> file" 400
run_hook "$(shell_json Bash "cat $BIG > $FIX/out.txt")";     expect_allow "Bash cat big > file (nothing reaches the model)"
run_hook "$(shell_json Bash "cat >> $BIG <<EOF\\nline\\nEOF")"; expect_allow "Bash heredoc append to a big file is a write"
run_hook "$(shell_json Bash "cat < $BIG")";                  expect_deny  "Bash cat < big" 400
# Ranges are judged by lines delivered, not by the range's width.
run_hook "$(shell_json Bash "sed -n '300,700p' $BIG")";      expect_allow "Bash sed range past EOF delivers 101 lines"
run_hook "$(shell_json Bash "sed -n '100,\$p' $BIG")";       expect_allow "Bash sed 100,\$p delivers 301 lines"
run_hook "$(shell_json Bash "sed -n '1,\$p' $BIG")";         expect_deny  "Bash sed 1,\$p" 400
# Known limit, pinned so it stays deliberate: the gate does not run the shell,
# so an unexpanded variable is not a file.
run_hook "$(shell_json Bash "cat \\\"\$FILE\\\"")";          expect_allow "Bash unexpanded variable (documented limit)"
# Known limit, pinned so it stays deliberate: the gate has no shell state, so a
# relative path after a `cd` in the same command resolves against the hook's own
# cwd and is not found there. The tool still runs; the read is simply ungated.
run_hook "$(shell_json Bash "cd $FIX && cat big.txt")";      expect_allow "Bash relative path after cd (documented limit)"
# Codex registers the hook with no tool matcher and names its shell tool
# differently, so admission is by input shape: any tool carrying `command`.
run_hook "$(shell_json shell "cat $BIG")";                   expect_deny  "Codex shell tool cat big" 400
run_hook '{"tool_name": "shell", "tool_input": {"command": ["cat", "'"$BIG"'"]}}'; expect_deny "Codex argv command cat big" 400

# --- 3. PowerShell tool ---------------------------------------------------------
run_hook "$(shell_json PowerShell "Get-Content $BIG")";                expect_deny  "PowerShell Get-Content big" 400
run_hook "$(shell_json PowerShell "Get-Content $BIG -TotalCount 20")"; expect_allow "PowerShell Get-Content -TotalCount"
run_hook "$(shell_json PowerShell "Get-Content $BIG -Tail 5")";        expect_allow "PowerShell Get-Content -Tail"
run_hook "$(shell_json PowerShell "type $BIG")";                       expect_deny  "PowerShell type big" 400

# --- 4. Environment -------------------------------------------------------------
BULK_READ_GATE=off run_hook "$(shell_json Bash "cat $BIG")";        expect_allow "BULK_READ_GATE=off"
BULK_READ_MIN_LINES=500 run_hook "$(shell_json Bash "cat $BIG")";   expect_allow "BULK_READ_MIN_LINES=500 lifts the threshold"
BULK_READ_MIN_LINES=100 run_hook "$(read_json "$SMALL" ', "limit": 100')"; expect_allow "limit at a lowered threshold is allowed"
BULK_READ_MIN_LINES=abc run_hook "$(read_json "$BIG")";             expect_error "BULK_READ_MIN_LINES=abc"
assert_contains "$ERR" "abc" "Gate: bad threshold error names the bad value"
BULK_READ_MIN_LINES=0 run_hook "$(read_json "$BIG")";               expect_error "BULK_READ_MIN_LINES=0"

# --- 5. Malformed input ---------------------------------------------------------
run_hook "not json";                                                 expect_error "malformed stdin"
run_hook "";                                                         expect_error "empty stdin"
run_hook '["a", "list"]';                                            expect_error "non-object stdin"
run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "x"}}';  expect_allow "unrelated tool"
run_hook '{"tool_name": "Read"}';                                    expect_error "Read event without tool_input"
run_hook '{"tool_name": "Read", "tool_input": null}';                expect_error "null tool_input"

# --- 5b. The shim settings.json registers resolves the interpreter and runs the gate
SHIM=".claude/hooks/bulk-read-gate.sh"
BASH_BIN="$(command -v bash)"
run_shim() {  # run_shim <json> — run_hook through the shim; PATH comes from the caller
  OUT="$(printf '%s' "$1" | "$BASH_BIN" "$SHIM" 2>"$BOX/stderr")"; RC=$?; ERR="$(< "$BOX/stderr")"
}
run_shim "$(read_json "$BIG")";                           expect_deny "shim: whole 400-line Read through bulk-read-gate.sh" 400
# The shim exists for the python-only host: a PATH carrying only `python` must
# still reach the gate, and a PATH carrying neither must fail loudly, not allow.
mkdir -p "$BOX/python-only" "$BOX/no-python"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$PY")" > "$BOX/python-only/python"
chmod +x "$BOX/python-only/python"
PATH="$BOX/python-only" run_shim "$(read_json "$BIG")";  expect_deny  "shim: python-only PATH still runs the gate" 400
PATH="$BOX/no-python" run_shim "$(read_json "$BIG")";    expect_error "shim: no interpreter on PATH"
assert_contains "$ERR" "Python 3 is required" "Gate: shim names the missing interpreter"

# --- 6. Pi mirror: static contract only -----------------------------------------
# TODO(shortcut): these assertions pin the mirror's shape — event, block/reason
# return, threshold, env names, read range rule, shell pattern list — not its
# behaviour. The upgrade path is a live Pi run: install the extension, ask Pi to
# `cat` a 400-line file, and record the block in tasks/e2e-log.md. No Pi is
# available in this test environment, so behaviour is pinned on the Python
# reference above and the mirror is held to the same contract by inspection.
PI_EXT="pi/extensions/bulk-read-gate.ts"
assert_eq "present" "$([ -f "$PI_EXT" ] && echo present || echo missing)" \
  "PiGate: $PI_EXT exists"
assert_file_contains "$PI_EXT" 'pi.on("tool_call"' "PiGate: subscribes to tool_call"
assert_file_contains "$PI_EXT" "block: true, reason" "PiGate: returns { block, reason }"
assert_file_contains "$PI_EXT" "DEFAULT_THRESHOLD = 350" "PiGate: mirrors the 350-line threshold"
assert_file_contains "$PI_EXT" '"BULK_READ_MIN_LINES"' "PiGate: reads BULK_READ_MIN_LINES"
assert_file_contains "$PI_EXT" '"BULK_READ_GATE"' "PiGate: honours BULK_READ_GATE"
assert_file_contains "$PI_EXT" 'toLowerCase() === "off"' "PiGate: BULK_READ_GATE=off disables it"
assert_file_contains "$PI_EXT" 'event.toolName === "read"' "PiGate: gates the read tool"
assert_file_contains "$PI_EXT" 'event.toolName === "bash"' "PiGate: gates the bash tool"
assert_file_contains "$PI_EXT" "input.offset" "PiGate: read range rule reads offset"
assert_file_contains "$PI_EXT" "input.limit" "PiGate: read range rule reads limit"
assert_file_contains "$PI_EXT" "delivered > limit" "PiGate: denies on lines delivered, not file size alone"
for pattern in '"cat"' '"type"' '"get-content"' '"head"' '"sed"' '"-totalcount"' '"-tail"'; do
  assert_file_contains "$PI_EXT" "$pattern" "PiGate: shell pattern list carries $pattern"
done
assert_file_contains "$PI_EXT" "finalStages" "PiGate: every command list's final pipe stage decides"
assert_file_contains "$PI_EXT" "stripRedirects" "PiGate: redirections are neither separators nor paths"
assert_file_contains "$PI_EXT" "deliveredLines" "PiGate: ranges are judged by lines delivered"
assert_file_contains "$PI_EXT" "bulk-reader" "PiGate: deny reason names the bulk-reader alternative"
# install.sh's copy step is exercised for real in tests/test-install-sh.sh (Case 10).

finish
