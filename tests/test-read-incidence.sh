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
assert_eq "9" "$(printf '%s\n' "$out" | grep -c '^read ')" "parser: the root holds nine parent-file Read tool uses: six in s1, three in s3"

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

# Session-level metadata the report and the grader both consume.
assert_contains "$out" "session proj-a/s1 reads=6 malformed=1 compactions=1 final_context=51500 subagents=1" \
  "parser: s1 counts its malformed line, its compaction, its final context and its sub-agent"
assert_contains "$out" "session proj-a/s2 reads=0 malformed=0 compactions=0 final_context=910 subagents=0" \
  "parser: a session with no tool use is a zero row, not an error"
assert_contains "$out" "session proj-b/s3 reads=3 malformed=1 compactions=0 final_context=2505 subagents=0" \
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
assert_contains "$md" "| proj-b/s3 | 2 | 0 | 0 | 0.0% | 0 | 0 | 0 |" "report: s3's inline sidechain read is not the parent's"
assert_contains "$md" "(legacy_reader.py) | 0 | 2505 | 0 | 1 | 1 | 0 | 1 |" \
  "report: s3's sidechain read lands in the sub-agent columns and its malformed line is counted"
assert_contains "$md" "## Aggregate" "report: an aggregate section follows the per-session table"
assert_contains "$md" "| all sessions | 6 | 2 | 6714 |" "report: the aggregate sums reads, whole-file large reads and bytes"
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
a = d["aggregate"]
print("agg", a["sessions"], a["reads"], a["whole_large"], a["verdict"], "median_share" in a, "quarter_share" in a)
')"
assert_contains "$keys" "reads=4 whole_large=2 whole_large_bytes=6714 truncated=1 shell_reads=5 shell_bytes=2400 rereads=3 final_context=51500 compactions=1 subagent_reads=1 subagent_large=1 excluded=2 malformed=1 largest_path=huge.log" \
  "report: --json carries the same per-session keys as the table"
assert_contains "$keys" "share True" "report: --json's share is bytes over the parent's tool-result bytes"
assert_contains "$keys" "agg 3 6 2 gate True True" "report: --json carries the aggregate and the go rule's inputs"

err="$("$TEST_PYTHON" "$INCIDENCE" --root "$TMP/empty-root" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "report: an empty root exits 2 through the CLI"
assert_contains "$err" "empty-root" "report: the CLI names the empty root"
err="$("$TEST_PYTHON" "$INCIDENCE" --root "$FIX/drift" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "report: a drifted Read block exits 2 through the CLI"
assert_contains "$err" "s9.jsonl:3" "report: the CLI names the file and line"

finish
