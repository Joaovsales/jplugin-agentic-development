#!/bin/bash
# tests/test-read-incidence.sh — the read-shunt baseline's measurement half:
# the one transcript parser and the incidence report built on it
# (specs/read-shunt-baseline.md).
#
# The baseline decides whether a read gate is built at all, so the number it
# prints has to come from the transcript and nothing else. Three ways that
# number lies, each pinned here against hand-made transcripts under
# tests/fixtures/transcripts/ that carry today's JSONL shape:
#
#   1. CLASSIFICATION — a ranged read counted as whole-file inflates the share;
#      a truncated whole-file read counted as ranged deflates it; an image or
#      an error counted as a zero-byte text read pollutes both. A sub-agent's
#      read must never raise the parent's count, whether it sits in a
#      subagents/ transcript or on an inline sidechain line (D5).
#
#   2. DRIFT — the on-disk format is internal. A Read block the parser cannot
#      read, or a root with nothing in it, is exit 2 with the path, never a
#      silent zero that reads as "the parent never bulk-reads" (AC4).
#
#   3. REPORT — the incidence table and its JSON twin, the bare-shell-read
#      classifier, and basenames-by-default (AC1, AC3) — slice 2.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Importing the module from a probe must not drop __pycache__ into the tree.
export PYTHONDONTWRITEBYTECODE=1

SCRIPTS=".agents/skills/eval/scripts"
FIX="tests/fixtures/transcripts"
PARSER="$SCRIPTS/read_transcript.py"

TMP="$(mktemp -d)"
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf '  FAIL could not create fixture dir\n'; exit 1; }
trap 'rm -rf "$TMP"' EXIT

assert_eq "present" "$([ -f "$PARSER" ] && echo present || echo missing)" "parser: read_transcript.py exists"

# --- § parser --------------------------------------------------------------
printf '\n--- parser: every fixture read classified from tool_use input plus toolUseResult.file ---\n'

out="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt

for s in rt.iter_sessions(sys.argv[2]):
    t = rt.parse_transcript(s.path)
    reads = t.reads()
    print(f"session {s.project}/{t.session_id} reads={len(reads)} malformed={t.malformed} "
          f"compactions={t.compactions} final_context={t.final_context} subagents={len(s.subagent_paths)} "
          f"result_bytes={t.tool_result_bytes()}")
    for r in reads:
        print(f"read {r.kind} truncated={r.truncated} large={r.is_large(rt.DEFAULT_BYTES, rt.DEFAULT_LINES)} "
              f"large1k={r.is_large(1000, 10000)} bytes={r.bytes} lines={r.total_lines} "
              f"sidechain={r.tool_use.sidechain} {r.norm_path.rsplit('/', 1)[-1]}")
    for p in s.subagent_paths:
        a = rt.parse_transcript(p, is_subagent=True)
        print(f"agent {a.session_id} subagent={a.is_subagent} final_context={a.final_context}")
        for r in a.reads():
            print(f"agent-read {r.kind} large={r.is_large(rt.DEFAULT_BYTES, rt.DEFAULT_LINES)} "
                  f"bytes={r.bytes} sidechain={r.tool_use.sidechain} {r.norm_path.rsplit('/', 1)[-1]}")
print("norm-equal", rt.normalize_path(r"C:\work\app\Big_Module.py") == rt.normalize_path("C:/work/app/big_module.py"))
PY
)"; rc=$?
assert_eq "0" "$rc" "parser: the clean fixture root parses with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$out" | head -20

# Whole-file reads: no offset, no limit. Large by lines (900 >= 800) at the
# defaults; not large by bytes (2000 < 32768). At --bytes 1000 the same read
# is large by bytes.
assert_contains "$out" "read whole truncated=False large=False large1k=False bytes=300 lines=20 sidechain=False small.py" \
  "parser: a small whole-file read is whole, not truncated, not large"
assert_contains "$out" "read whole truncated=False large=True large1k=True bytes=2000 lines=900 sidechain=False big_module.py" \
  "parser: a whole-file read of a 900-line file is large by lines at the defaults"
# AC2: a ranged read is never counted as whole-file.
assert_contains "$out" "read ranged truncated=False large=True large1k=True bytes=1000 lines=900 sidechain=False big_module.py" \
  "parser: offset/limit makes a read ranged whatever the file's size"
# AC2: numLines < totalLines with no limit is a whole-file read the tool cut.
assert_contains "$out" "read whole truncated=True large=True large1k=True bytes=4000 lines=1400 sidechain=False huge.log" \
  "parser: a read the tool truncated at its cap is whole-file and flagged truncated"
# AC2: non-text results are excluded, not zero-byte text reads.
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False shot.png" \
  "parser: an image result is excluded"
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False missing.py" \
  "parser: an error result is excluded"
assert_eq "8" "$(printf '%s\n' "$out" | grep -c '^read ')" "parser: the root holds eight parent-file Read tool uses: six in s1, two in s3"

# AC2: sub-agent reads raise the sub-agent column only — a subagents/ file...
assert_contains "$out" "agent agent-a1 subagent=True final_context=7062" \
  "parser: a subagents/ transcript is marked sub-agent with its own final context"
assert_contains "$out" "agent-read whole large=True bytes=6000 sidechain=True big_module.py" \
  "parser: a read inside a subagents/ transcript is a sidechain read"
# ...and a legacy inline sidechain line in the parent's own file.
assert_contains "$out" "read whole truncated=False large=True large1k=True bytes=1200 lines=850 sidechain=True loader.py" \
  "parser: an inline isSidechain line marks its read sidechain"
assert_contains "$out" "read whole truncated=False large=False large1k=False bytes=50 lines=5 sidechain=False tiny.cfg" \
  "parser: the parent's own read beside it stays the parent's"

# Session-level metadata the report and the grader both consume.
assert_contains "$out" "session proj-a/s1 reads=6 malformed=1 compactions=1 final_context=51500 subagents=1" \
  "parser: s1 counts its malformed line, its compaction, its final context and its sub-agent"
assert_contains "$out" "session proj-a/s2 reads=0 malformed=0 compactions=0 final_context=910 subagents=0" \
  "parser: a session with no tool use is a zero row, not an error"
assert_contains "$out" "session proj-b/s3 reads=2 malformed=1 compactions=0 final_context=2505 subagents=0" \
  "parser: a JSON line that is not an object counts as malformed"
assert_contains "$out" "norm-equal True" \
  "parser: backslash and forward-slash spellings of one path normalise equal"

# Tool-result bytes are the share's denominator: text parts only, so an
# image's base64 never enters it. s1: 300+2000+1000+4000 file contents carry
# `cat -n` prefixes in the block; the count below is what the parser sees.
assert_contains "$out" "result_bytes=" "parser: every session reports its tool-result bytes"
s1_bytes="$(printf '%s\n' "$out" | sed -n 's/^session proj-a\/s1 .*result_bytes=\([0-9]*\)$/\1/p')"
[ -n "$s1_bytes" ] && [ "$s1_bytes" -gt 10000 ] && [ "$s1_bytes" -lt 20000 ] \
  && big_ok=in-range || big_ok="out-of-range:$s1_bytes"
assert_eq "in-range" "$big_ok" "parser: s1's tool-result bytes are the text parts of every result block"

# --- § drift ---------------------------------------------------------------
printf '\n--- drift: exit 2 names the root or the file and line; never a silent zero ---\n'

EMPTY="$TMP/empty-root"; mkdir -p "$EMPTY"
err="$("$TEST_PYTHON" - "$SCRIPTS" "$EMPTY" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.iter_sessions(sys.argv[2])))
PY
)"; rc=$?
assert_eq "2" "$rc" "drift: an empty root exits 2"
# MSYS rewrites a /tmp argv path to its Windows spelling before Python sees
# it, so the message is matched on the directory name, not the full path.
assert_contains "$err" "empty-root" "drift: the empty-root message names the root"

err="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/drift/proj-d/s9.jsonl" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2]).reads()))
PY
)"; rc=$?
assert_eq "2" "$rc" "drift: a Read result whose file block moved exits 2"
assert_contains "$err" "s9.jsonl:3" "drift: the message names the file and the line"
assert_contains "$err" "transcript format changed" "drift: the message says what broke"

err="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/drift-input/proj-d/s8.jsonl" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2]).reads()))
PY
)"; rc=$?
assert_eq "2" "$rc" "drift: a Read input without file_path exits 2"
assert_contains "$err" "s8.jsonl:2" "drift: the input-shape message names the file and the line"

# A clean run through the same guard is exit 0 and silent on stderr.
err="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root/proj-a/s1.jsonl" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2]).reads()))
PY
)"; rc=$?
assert_eq "0" "$rc" "drift: the guard returns 0 on a readable transcript"
assert_eq "" "$err" "drift: the guard prints nothing on success"

finish
