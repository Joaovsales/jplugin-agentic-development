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
        print(f"read {r.kind} truncated={r.truncated} large={r.is_large(rt.Thresholds())} "
              f"large1k={r.is_large(rt.Thresholds(1000, 10000))} bytes={r.bytes} lines={r.total_lines} "
              f"sidechain={r.tool_use.sidechain} {r.norm_path.rsplit('/', 1)[-1]}")
    for p in s.subagent_paths:
        a = rt.parse_transcript(p, is_subagent=True)
        print(f"agent {a.session_id} subagent={a.is_subagent} final_context={a.final_context}")
        for r in a.reads():
            print(f"agent-read {r.kind} large={r.is_large(rt.Thresholds())} "
                  f"bytes={r.bytes} sidechain={r.tool_use.sidechain} {r.norm_path.rsplit('/', 1)[-1]}")
print("norm-equal", rt.normalize_path(r"C:\work\app\Big_Module.py") == rt.normalize_path("C:/work/app/big_module.py"))
PY
)"; rc=$?
assert_eq "0" "$rc" "parser: the clean fixture root parses with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$out" | head -20

# Whole-file reads: no offset, no limit. Large by lines (900 >= 800) at the
# defaults; not large by bytes (2000 < 32768). At --bytes 1000 the same read
# is large by bytes.
assert_contains "$out" "read whole truncated=False large=False large1k=False bytes=349 lines=20 sidechain=False small.py" \
  "parser: a small whole-file read is whole, not truncated, not large"
assert_contains "$out" "read whole truncated=False large=True large1k=True bytes=2357 lines=900 sidechain=False big_module.py" \
  "parser: a whole-file read of a 900-line file is large by lines at the defaults"
# AC2: a ranged read is never counted as whole-file.
assert_contains "$out" "read ranged truncated=False large=True large1k=True bytes=1357 lines=900 sidechain=False big_module.py" \
  "parser: offset/limit makes a read ranged whatever the file's size"
# AC2: numLines < totalLines with no limit is a whole-file read the tool cut.
assert_contains "$out" "read whole truncated=True large=True large1k=True bytes=4357 lines=1400 sidechain=False huge.log" \
  "parser: a read the tool truncated at its cap is whole-file and flagged truncated"
# AC2: non-text results are excluded, not zero-byte text reads.
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False shot.png" \
  "parser: an image result is excluded"
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False missing.py" \
  "parser: an error result is excluded"
assert_eq "13" "$(printf '%s\n' "$out" | grep -c '^read ')" "parser: the root holds thirteen parent-file Read tool uses: six in s1, seven in s3"

# AC2: sub-agent reads raise the sub-agent column only — a subagents/ file...
assert_contains "$out" "agent agent-a1 subagent=True final_context=7062" \
  "parser: a subagents/ transcript is marked sub-agent with its own final context"
assert_contains "$out" "agent-read whole large=True bytes=6707 sidechain=True big_module.py" \
  "parser: a read inside a subagents/ transcript is a sidechain read"
# ...and a legacy inline sidechain line in the parent's own file.
assert_contains "$out" "read whole truncated=False large=True large1k=True bytes=1487 lines=850 sidechain=True loader.py" \
  "parser: an inline isSidechain line marks its read sidechain"
assert_contains "$out" "read whole truncated=False large=False large1k=False bytes=92 lines=5 sidechain=False tiny.cfg" \
  "parser: the parent's own read beside it stays the parent's"
# Older transcripts carry no toolUseResult beside a Read: the numbered block
# text is the record, so its line count stands in for the total.
assert_contains "$out" "read whole truncated=False large=False large1k=True bytes=1117 lines=31 sidechain=False legacy_reader.py" \
  "parser: a Read with a null toolUseResult is classified from its numbered block text"
# The harness prefixes some of those blocks (memory files) with a
# <system-reminder>; the numbered text behind it is still the record, and the
# bytes stay what entered the context, reminder included.
assert_contains "$out" "read whole truncated=False large=False large1k=False bytes=120 lines=4 sidechain=False memo.md" \
  "parser: a reminder-prefixed null-result Read is classified from the numbered text behind the reminder"
# A Read the harness could not parse (`__unparsedToolInput`, an error result)
# never ran: it has no file_path and is excluded, not drift.
assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False $')" \
  "parser: an unparsed-input Read is excluded, with no path, rather than reported as drift"
# Two more null-result notes the harness writes in place of file text: the
# unchanged-file note and a bare reminder for an empty file. Nothing of the
# file entered the context, so both are excluded.
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False memo.md" \
  "parser: the unchanged-file note is excluded, not drift"
assert_contains "$out" "read excluded truncated=False large=False large1k=False bytes=0 lines=0 sidechain=False empty.md" \
  "parser: a bare empty-file reminder is excluded, not drift"

# Session-level metadata the report and the grader both consume.
assert_contains "$out" "session proj-a/s1 reads=6 malformed=1 compactions=1 final_context=51500 subagents=1" \
  "parser: s1 counts its malformed line, its compaction, its final context and its sub-agent"
assert_contains "$out" "session proj-a/s2 reads=0 malformed=0 compactions=0 final_context=910 subagents=0" \
  "parser: a session with no tool use is a zero row, not an error"
assert_contains "$out" "session proj-b/s3 reads=7 malformed=1 compactions=0 final_context=2505 subagents=0" \
  "parser: a JSON line that is not an object counts as malformed"
assert_contains "$out" "norm-equal True" \
  "parser: backslash and forward-slash spellings of one path normalise equal"

# Tool-result bytes are the share's denominator: text parts only, so an
# image's base64 never enters it. A Read's bytes are the same measure — the
# numbered block the parent received, not the bare file content — so the share
# divides like by like.
assert_contains "$out" "result_bytes=" "parser: every session reports its tool-result bytes"
s1_bytes="$(printf '%s\n' "$out" | sed -n 's/^session proj-a\/s1 .*result_bytes=\([0-9]*\)$/\1/p')"
[ -n "$s1_bytes" ] && [ "$s1_bytes" -gt 10000 ] && [ "$s1_bytes" -lt 20000 ] \
  && big_ok=in-range || big_ok="out-of-range:$s1_bytes"
assert_eq "in-range" "$big_ok" "parser: s1's tool-result bytes are the text parts of every result block"
# The denominator is the parent's bytes: s3's inline sidechain result (toolu_w1,
# 1487 bytes) is the sub-agent's, so the parent's 3100 - 1487 = 1613.
assert_eq "1613" "$(printf '%s\n' "$out" | sed -n 's/^session proj-b\/s3 .*result_bytes=\([0-9]*\)$/\1/p')" \
  "parser: s3's tool-result bytes leave out its inline sidechain result"

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

# parse_transcript returning is proof the transcript is readable: Reads are
# classified at parse time, so drift raises there and `reads()` is free after.
err="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/drift/proj-d/s9.jsonl" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2])))
PY
)"; rc=$?
assert_eq "2" "$rc" "drift: parse_transcript alone raises on a Read result whose file block moved"
assert_contains "$err" "s9.jsonl:3" "drift: the parse-time message names the file and the line"

out="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root/proj-a/s1.jsonl" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
t = rt.parse_transcript(sys.argv[2])
print("immutable", type(t.reads()) is tuple, len(t.reads()))
PY
)"
assert_contains "$out" "immutable True 6" "parser: reads() hands out what parse time classified, in a tuple a caller cannot extend"

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

# A completed Agent result without the counters the grader sums is drift; an
# unanswered Agent call is not.
AGENT_DRIFT="$TMP/agent-drift.jsonl"
"$TEST_PYTHON" - "$AGENT_DRIFT" "$TMP/agent-unanswered.jsonl" <<'PY'
import json, sys
def line(**rec): return json.dumps(rec)
use = line(type="assistant", message={"role": "assistant", "content": [
    {"type": "tool_use", "id": "t1", "name": "Agent", "input": {"prompt": "read big.py"}}]})
user = line(type="user", message={"role": "user", "content": "go"})
done = line(type="user", message={"role": "user", "content": [
    {"type": "tool_result", "tool_use_id": "t1", "content": "done"}]},
    toolUseResult={"status": "completed", "content": [{"type": "text", "text": "done"}]})
open(sys.argv[1], "w").write("\n".join([user, use, done]) + "\n")
open(sys.argv[2], "w").write("\n".join([user, use]) + "\n")
PY
err="$("$TEST_PYTHON" - "$SCRIPTS" "$AGENT_DRIFT" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2])))
PY
)"; rc=$?
assert_eq "2" "$rc" "drift: a completed Agent result without totalTokens and totalToolUseCount exits 2"
assert_contains "$err" "agent-drift.jsonl:3" "drift: the Agent message names the file and the line"
err="$("$TEST_PYTHON" - "$SCRIPTS" "$TMP/agent-unanswered.jsonl" <<'PY' 2>&1 >/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
sys.exit(rt.run(lambda: rt.parse_transcript(sys.argv[2])))
PY
)"; rc=$?
assert_eq "0" "$rc" "drift: an Agent call with no result is not drift"

# --- § shell --------------------------------------------------------------
printf '\n--- shell: a bare read delivers the file; a pipe or a redirect does not ---\n'

out="$("$TEST_PYTHON" - "$SCRIPTS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
cases = [
    "cat f", "head f", "tail f", "less f", "more f", "sed -n '1,$p' f", "sed -n 1,200p f",
    "cat a; cat b", "head -n 20 a && tail -c 100 b", "cat f | grep x", "cat f > g", "cat < f",
    "echo $(cat f)", "cat <<'EOF'\nf\nEOF", "sed -i 's/a/b/' f", "sed -n '1,$p' f | head",
    'cat "C:\\work\\my file.txt"', "python3 -c 'print(open(\"f\").read())'",
    "cat -n f", "cat -s a b", "tail -n 5 f", "head -c 10 f",
]
for c in cases:
    print(repr(c.replace("\n", " NL ")), "->", rt.bare_shell_reads(c))
PY
)"; rc=$?
assert_eq "0" "$rc" "shell: the classifier runs"
assert_contains "$out" "'cat f' -> ['f']" "shell: cat f is a bare read"
assert_contains "$out" "'head f' -> ['f']" "shell: head f is a bare read"
assert_contains "$out" "'tail f' -> ['f']" "shell: tail f is a bare read"
assert_contains "$out" "'less f' -> ['f']" "shell: less f is a bare read"
assert_contains "$out" "'more f' -> ['f']" "shell: more f is a bare read"
assert_contains "$out" "\"sed -n '1,\$p' f\" -> ['f']" "shell: sed -n with a print range is a bare read"
assert_contains "$out" "'sed -n 1,200p f' -> ['f']" "shell: an unquoted sed print range is a bare read"
assert_contains "$out" "'cat a; cat b' -> ['a', 'b']" "shell: every file in a chained command counts"
assert_contains "$out" "'head -n 20 a && tail -c 100 b' -> ['a', 'b']" "shell: count options do not swallow the file"
assert_contains "$out" "'cat -n f' -> ['f']" "shell: cat's -n is a bare flag, so the file stays"
assert_contains "$out" "'cat -s a b' -> ['a', 'b']" "shell: cat's -s is a bare flag, so both files stay"
assert_contains "$out" "'tail -n 5 f' -> ['f']" "shell: tail's -n takes the count"
assert_contains "$out" "'head -c 10 f' -> ['f']" "shell: head's -c takes the count"
assert_contains "$out" "'cat f | grep x' -> []" "shell: a piped read is not a read into the context"
assert_contains "$out" "'cat f > g' -> []" "shell: a redirected read is not a read into the context"
assert_contains "$out" "'cat < f' -> []" "shell: an input redirect is not a bare read"
assert_contains "$out" "'echo \$(cat f)' -> []" "shell: a substituted read is not a bare read"
assert_contains "$out" "\"cat <<'EOF' NL f NL EOF\" -> []" "shell: a heredoc is not a bare read"
assert_contains "$out" "\"sed -i 's/a/b/' f\" -> []" "shell: sed without a print range is not a read"
assert_contains "$out" "\"sed -n '1,\$p' f | head\" -> []" "shell: a piped sed is not a bare read"
assert_contains "$out" "'cat \"C:\\\\work\\\\my file.txt\"' -> ['C:\\\\work\\\\my file.txt']" \
  "shell: a quoted Windows path keeps its backslashes and its space"
assert_contains "$out" "-> []" "shell: python -c open() is not a shell read"

# --- § report -------------------------------------------------------------
printf '\n--- report: the incidence table, its JSON twin, and basenames by default ---\n'

INCIDENCE="$SCRIPTS/read-incidence.py"
md="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/root" 2>&1)"; rc=$?
assert_eq "0" "$rc" "report: the fixture root renders with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$md" | head -5

# s1: four text reads (small, big whole, big ranged, huge); two whole-file
# large (big by lines, huge truncated) = 2357 + 4357 block bytes; one truncated;
# five bare shell reads (cat, head, cat, tail, sed) over four commands whose
# results are 600 + 700 + 200 + 900 bytes; re-reads: big_module ranged after
# whole, a.txt by tail and by sed after head = 3; one sub-agent read, large.
assert_contains "$md" "| proj-a/s1 | 4 | 2 | 6714 |" "report: s1 reads, whole-file large reads and their bytes"
assert_file_matches_text() { printf '%s\n' "$1" | grep -Eq "$2"; }
assert_eq "yes" "$(assert_file_matches_text "$md" '^\| proj-a/s1 \| 4 \| 2 \| 6714 \| [0-9]+\.[0-9]%' && echo yes || echo no)" \
  "report: s1 carries a percentage share"
assert_contains "$md" "| 1 | 5 | 2400 |" "report: s1's truncated count, shell reads and shell bytes"
assert_contains "$md" "(huge.log) | 3 | 51500 | 1 | 1 | 1 | 2 | 1 |" \
  "report: s1's largest result is huge.log; re-reads, final context, compactions, sub-agent reads and large, excluded, malformed"
assert_contains "$md" "| proj-a/s2 | 0 | 0 | 0 | 0.0% | 0 | 0 | 0 | 0 | 0 | 910 | 0 | 0 | 0 | 0 | 0 |" \
  "report: a session with no tool use is a zero row"
assert_contains "$md" "| proj-b/s3 | 3 | 0 | 0 | 0.0% | 0 | 0 | 0 |" "report: s3's inline sidechain read is not the parent's"
assert_contains "$md" "(legacy_reader.py) | 0 | 2505 | 0 | 1 | 1 | 3 | 1 |" \
  "report: s3's sidechain read lands in the sub-agent columns and its malformed line is counted"
assert_contains "$md" "## Aggregate" "report: an aggregate section follows the per-session table"
assert_contains "$md" "| all sessions | 7 | 2 | 6714 |" "report: the aggregate sums reads, whole-file large reads and bytes"
assert_contains "$md" "Sessions: 3 · median share 0.0% · quarter share" "report: the go rule's inputs are stated"
assert_contains "$md" "Verdict: gate" "report: a quarter of fixture sessions above 25% is a gate verdict"
assert_not_contains "$md" "C:\\work" "report: paths are basenames by default"
assert_not_contains "$md" "aaaaaaaaaa" "report: file contents never appear"

full="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/root" --paths 2>&1)"
assert_contains "$full" "work\\app\\huge.log" "report: --paths shows the full path"

big="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/root" --bytes 100000 --lines 100000 2>&1)"
assert_contains "$big" "| proj-a/s1 | 4 | 0 | 0 | 0.0% |" "report: --bytes and --lines move the threshold"
assert_contains "$big" "Verdict: not worth gating" "report: nothing large is a not-worth-gating verdict"

js="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/root" --json 2>&1)"; rc=$?
assert_eq "0" "$rc" "report: --json renders with exit 0"
keys="$(printf '%s\n' "$js" | "$TEST_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
s1 = [s for s in d["sessions"] if s["session"] == "proj-a/s1"][0]
print(" ".join(f"{k}={s1[k]}" for k in ("reads", "whole_large", "whole_large_bytes", "truncated", "shell_reads", "shell_bytes", "rereads", "final_context", "compactions", "subagent_reads", "subagent_large", "excluded", "malformed", "largest_path")))
print("share", round(s1["share"], 3) == round(s1["whole_large_bytes"] / s1["result_bytes"], 3))
print("s3-denominator", [s for s in d["sessions"] if s["session"] == "proj-b/s3"][0]["result_bytes"])
a = d["aggregate"]
print("agg", a["sessions"], a["reads"], a["whole_large"], a["verdict"], "median_share" in a, "quarter_share" in a)
')"
assert_contains "$keys" "reads=4 whole_large=2 whole_large_bytes=6714 truncated=1 shell_reads=5 shell_bytes=2400 rereads=3 final_context=51500 compactions=1 subagent_reads=1 subagent_large=1 excluded=2 malformed=1 largest_path=huge.log" \
  "report: --json carries the same per-session keys as the table"
assert_contains "$keys" "share True" "report: --json's share is bytes over the parent's tool-result bytes"
assert_contains "$keys" "s3-denominator 1613" "report: the share's denominator leaves out a sidechain result"
assert_contains "$keys" "agg 3 7 2 gate True True" "report: --json carries the aggregate and the go rule's inputs"

err="$("$TEST_PYTHON" "$INCIDENCE" --root "$TMP/empty-root" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "report: an empty root exits 2 through the CLI"
assert_contains "$err" "empty-root" "report: the CLI names the empty root"
assert_contains "$err" "read-incidence: " "report: an error names the CLI that raised it"
err="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/drift" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "report: a drifted Read block exits 2 through the CLI"
assert_contains "$err" "s9.jsonl:3" "report: the CLI names the file and line"

# --- § structure ----------------------------------------------------------
printf '\n--- structure: one declaration per fact, so none can be left out ---\n'

# The parser owns the gate-log name: a shunt.jsonl beside a transcript is a
# decision log, not a zero-read session.
SHUNTROOT="$TMP/shunt-root"; mkdir -p "$SHUNTROOT"
cp -r "$FIX/root/." "$SHUNTROOT/"
printf '%s\n' '{"decision":"allow","tool":"Read","input":{}}' > "$SHUNTROOT/proj-a/shunt.jsonl"
out="$("$TEST_PYTHON" - "$SCRIPTS" "$SHUNTROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
names = sorted(s.path.replace("\\", "/").rsplit("/", 1)[-1] for s in rt.iter_sessions(sys.argv[2]))
print("log-name", rt.SHUNT_LOG)
print("sessions", " ".join(names))
PY
)"
assert_contains "$out" "log-name shunt.jsonl" "structure: the parser exports the gate-log name"
assert_contains "$out" "sessions s1.jsonl s2.jsonl s3.jsonl" "structure: iter_sessions skips a shunt.jsonl beside a transcript"
assert_eq "$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/root" --json 2>&1 | sed 's/"root": .*/"root"/')" \
  "$("$TEST_PYTHON" "$INCIDENCE" --root "$SHUNTROOT" --json 2>&1 | sed 's/"root": .*/"root"/')" \
  "structure: the report is the same with a gate log beside a transcript"
assert_eq "0" "$(grep -c 'SHUNT_LOG = ' "$SCRIPTS/grade-read-shunt.py")" \
  "structure: the grader imports the gate-log name instead of spelling its own"

# The parser's predicates replace the kind comparisons at every call site.
out="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root/proj-a/s1.jsonl" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
t = rt.parse_transcript(sys.argv[2])
th = rt.Thresholds()
reads = t.reads()
print("defaults", th.bytes, th.lines)
print("whole", sum(r.is_whole for r in reads), "excluded", sum(r.is_excluded for r in reads),
      "whole-large", sum(r.is_whole_large(th) for r in reads))
PY
)"
assert_contains "$out" "defaults 32768 800" "structure: Thresholds defaults to the spec's 32768 bytes and 800 lines"
assert_contains "$out" "whole 3 excluded 2 whole-large 2" \
  "structure: s1's reads split into whole, excluded and whole-large through the Read predicates"
for cli in "$INCIDENCE" "$SCRIPTS/grade-read-shunt.py"; do
  assert_eq "0" "$(grep -cE '\.kind (==|!=)' "$cli")" "$cli: no call site compares Read.kind — the predicates own that"
  assert_eq "0" "$(grep -cE 'input\.get|\.result\.get|result\.result|bare_shell_reads' "$cli")" \
    "$cli: reads no tool input or result shape — the parser classifies Bash, Grep and Agent calls"
done

# Bash, Grep and Agent uses are classified at parse time beside Read, for the
# parent loop only: one definition of the parent serves both CLIs.
out="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root/proj-a/s1.jsonl" "$FIX/results/shunt/task-a/run-1/transcript.jsonl" "$FIX/root/proj-b/s3.jsonl" "$TMP/agent-unanswered.jsonl" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
s1 = rt.parse_transcript(sys.argv[2])
print("shell", [(s.paths, s.bytes) for s in s1.shell_reads()])
print("grep", [(g.target, g.context_lines, g.head_limit, g.bytes) for g in s1.grep_calls()])
print("agent", [(a.total_tokens, a.tool_use_count, "big_module.py" in a.named_text) for a in s1.agent_calls()])
print("immutable", *(type(c()) is tuple for c in (s1.shell_reads, s1.grep_calls, s1.agent_calls)))
shunt = rt.parse_transcript(sys.argv[3])
print("completed", [(a.total_tokens, a.tool_use_count, "big.py:120-160" in a.named_text) for a in shunt.agent_calls()])
s3 = rt.parse_transcript(sys.argv[4])
print("parent-uses", len(s3.tool_uses), len(s3.parent_tool_uses()),
      all(not u.sidechain for u in s3.parent_tool_uses()))
print("largest", s1.largest_parent_result(), s3.largest_parent_result(),
      rt.parse_transcript(sys.argv[5]).largest_parent_result())
PY
)"
assert_contains "$out" "shell [(('c:/work/app/notes.txt',), 600), (('c:/work/app/a.txt', 'c:/work/app/b.txt'), 700), (('c:/work/app/a.txt',), 200), (('c:/work/app/a.txt',), 900)]" \
  "structure: shell_reads() keeps the bare reads only, paths normalized, one entry per command with its result bytes"
assert_contains "$out" "grep [('c:/work/app/big_module.py', 60, None, 800)]" \
  "structure: grep_calls() carries the normalized target, -C, head_limit and result bytes"
assert_contains "$out" "agent [(None, None, True)]" \
  "structure: an async-launched Agent has the prompt's text and no counters, and that is not drift"
assert_contains "$out" "completed [(12000, 7, True)]" \
  "structure: a completed Agent carries its counters and the paths its result text names"
assert_contains "$out" "immutable True True True" "structure: the three classifications are made at parse time and handed out as tuples"
assert_contains "$out" "parent-uses 7 6 True" "structure: parent_tool_uses() leaves out the inline sidechain use"
assert_contains "$out" "largest (4357, 'C:\\\\work\\\\app\\\\huge.log') (1117, 'C:\\\\work\\\\lib\\\\legacy_reader.py') (0, '')" \
  "structure: largest_parent_result() is the parent's biggest result and its subject, (0, '') when nothing was answered"

# The parent/sidechain split and the call order are the parser's, so neither
# CLI re-derives them.
out="$("$TEST_PYTHON" - "$SCRIPTS" "$FIX/root/proj-a/s1.jsonl" "$FIX/root/proj-b/s3.jsonl" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
s1 = rt.parse_transcript(sys.argv[2])
s3 = rt.parse_transcript(sys.argv[3])
print("s1-split", len(s1.reads()), len(s1.parent_reads()), len(s1.sidechain_reads()))
print("s3-split", len(s3.reads()), len(s3.parent_reads()), len(s3.sidechain_reads()),
      [r.norm_path.rsplit("/", 1)[-1] for r in s3.sidechain_reads()])
print("counted-sidechain", len(s1.counted_sidechain_reads()), [r.norm_path.rsplit("/", 1)[-1] for r in s3.counted_sidechain_reads()],
      all(not r.is_excluded and r.tool_use.sidechain for r in s3.counted_sidechain_reads()))
print("order", [type(c).__name__ for c in s1.parent_calls()])
lines = [c.tool_use.line_no for c in s1.parent_calls()]
print("order-ids", len(lines), lines == sorted(lines))
print("parent-calls-s3", len(s3.parent_calls()), all(not c.tool_use.sidechain for c in s3.parent_calls()))
print("immutable", type(s1.parent_calls()) is tuple)
PY
)"
assert_contains "$out" "s1-split 6 6 0" "structure: s1 has no sidechain read, so its parent reads are all its reads"
assert_contains "$out" "s3-split 7 6 1 ['loader.py']" \
  "structure: s3's inline sidechain read is in sidechain_reads() and out of parent_reads(); reads() stays the union"
assert_contains "$out" "counted-sidechain 0 ['loader.py'] True" "structure: counted_sidechain_reads() is the sidechain reads that entered a context"
assert_contains "$out" "order-ids 12 True" "structure: parent_calls() follows the order of the tool uses"
assert_contains "$out" "parent-calls-s3 6 True" "structure: parent_calls() leaves out the inline sidechain read"
assert_contains "$out" "immutable True" "structure: parent_calls() is built at parse time and handed out as a tuple"

# A session is its parent transcript plus its sub-agent files: parse_session
# is the one place that assembles it, so both CLIs count the same sidechain.
SESSROOT="$TMP/session-root"; mkdir -p "$SESSROOT/proj/s1/subagents"
cp "$FIX/root/proj-a/s1.jsonl" "$SESSROOT/proj/s1.jsonl"
cp "$FIX/root/proj-a/s1/subagents/agent-a1.jsonl" "$SESSROOT/proj/s1/subagents/"
cp "$FIX/root/proj-b/s3.jsonl" "$SESSROOT/proj/s3.jsonl"
"$TEST_PYTHON" - "$SESSROOT/proj/s1/subagents/agent-e1.jsonl" <<'PY'
import json, sys
use = {"type": "assistant", "isSidechain": True, "message": {"content": [
    {"type": "tool_use", "id": "r1", "name": "Read", "input": {"file_path": "/work/missing.py"}}]}}
err = {"type": "user", "isSidechain": True, "message": {"content": [
    {"type": "tool_result", "tool_use_id": "r1", "is_error": True, "content": "File does not exist."}]}}
open(sys.argv[1], "w").write("not json\n" + "\n".join(json.dumps(r) for r in (use, err)) + "\n")
PY
out="$("$TEST_PYTHON" - "$SCRIPTS" "$SESSROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
for s in rt.iter_sessions(sys.argv[2]):
    ss = rt.parse_session(s.path, s.subagent_paths)
    print("session", ss.parent.session_id, len(ss.agents), all(a.is_subagent for a in ss.agents), ss.malformed,
          [r.norm_path.rsplit("/", 1)[-1] for r in ss.counted_sidechain_reads])
PY
)"
assert_contains "$out" "session s1 2 True 2 ['big_module.py']" \
  "structure: parse_session parses every sub-agent file, sums malformed lines, and drops an excluded sidechain read"
assert_contains "$out" "session s3 0 True 1 ['loader.py']" \
  "structure: parse_session counts the parent's inline sidechain reads beside the agents'"
for cli in "$INCIDENCE" "$SCRIPTS/grade-read-shunt.py"; do
  assert_eq "0" "$(grep -cE 'tool_use\.(id|sidechain)|\.results(\.get|\[)' "$cli")" "$cli: no join on tool-use ids and no sidechain branch — the parser owns the split and the order"
  assert_eq "0" "$(grep -c 'parse_transcript' "$cli")" "$cli: reads a session through parse_session, never assembling one from per-file transcripts"
  assert_eq "0" "$(grep -c -- '---' "$cli")" "$cli: builds no Markdown rule — the parser module's table helper owns it"
  assert_eq "0" "$(grep -c 'type: ignore' "$cli")" "$cli: needs no type ignore"
  assert_eq "0" "$(grep -cE 'field\(metadata=' "$cli")" "$cli: every column is declared through its one column helper, key columns included"
done

out="$("$TEST_PYTHON" - "$SCRIPTS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import read_transcript as rt
print(rt.markdown_table(["A", "B"], [["1", "2"], ["3", "4"]]).replace("\n", "/"))
PY
)"
assert_contains "$out" "| A | B |/|---|---|/| 1 | 2 |/| 3 | 4 |" "structure: markdown_table() is a header line, a rule line and the rows"

# One Row declaration drives the columns and the aggregate: a field added to
# it is a column and summed unless it is declared otherwise.
out="$("$TEST_PYTHON" - "$INCIDENCE" <<'PY'
import importlib.util, sys
from dataclasses import fields
spec = importlib.util.spec_from_file_location("read_incidence", sys.argv[1])
ri = importlib.util.module_from_spec(spec)
sys.modules["read_incidence"] = ri
spec.loader.exec_module(ri)
names = {f.name for f in fields(ri.Row)}
print("columns-known", all(key in names or key == "share" for key, _ in ri.COLUMNS))
rows = [ri.Row("a"), ri.Row("b")]
summable = [f.name for f in fields(ri.Row) if f.metadata["summable"]]
for i, row in enumerate(rows, 1):
    for name in summable:
        setattr(row, name, i)
total = ri.aggregate(rows).total
print("summed", all(getattr(total, name) == 3 for name in summable), len(summable))
print("unsummed", sorted(names - set(summable)))
PY
)"
assert_contains "$out" "columns-known True" "structure: every column is a Row field or the derived share"
assert_contains "$out" "summed True 13" "structure: aggregate() sums every summable Row field"
assert_contains "$out" "unsummed ['final_context', 'largest', 'largest_path', 'session']" \
  "structure: the fields that are not summed are the ones declared so"

finish
