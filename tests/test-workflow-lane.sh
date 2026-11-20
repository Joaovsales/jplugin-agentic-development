#!/bin/bash
# tests/test-workflow-lane.sh — the `workflow` producer routine
# (specs/claude-mem-retention.md § Proposed routine: workflow producer).
#
# Three things are pinned:
#
#   1. THE LANE — workflow.md is a producer lane: its frontmatter carries
#      `routine: producer` and nothing a consumer would (no selector, no cues, no
#      deferral), its chain is /sweep -> /wrap-up-session, and the lens carries
#      the spec's evidence bar verbatim rather than a softened one.
#
#   2. THE CURSOR — the engine never silently advances past unread input: scan
#      leaves the cursor where it is, advance moves it only to the last session a
#      report examined, a stale report is refused, a capped run names what it left
#      unexamined, an unreadable transcript is a named coverage gap, and an open
#      session is never read.
#
#   3. NO NEW COLLECTOR — the engine reads transcripts only through
#      read_transcript.py and measures through read-incidence.py, counts parent
#      and sub-agent contexts apart, and prints no absolute home path.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

LANE=".agents/skills/task-registry/lanes/workflow.md"
LENS=".agents/skills/sweep/references/lens-workflow.md"
ENGINE=".agents/skills/eval/scripts/workflow-incidence.py"
PROMPT=".agents/skills/wrap-up-session/references/routine-prompts/workflow.md"
CANON=".agents/skills/wrap-up-session/references/routines.md"
py_module .agents/skills/task-registry/scripts >/dev/null

# ============================================================================
# 1. the lane, its selector frontmatter, and the evidence bar
# ============================================================================
printf '\n-- lane --\n'
assert_file_exists "$LANE" "lane: $LANE exists"
front="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$LANE" 2>/dev/null)"
assert_eq "routine: producer" "$(printf '%s\n' "$front" | grep '^routine:')" \
  "lane: frontmatter declares routine: producer"
assert_contains "$front" "ends: " "lane: frontmatter states what the lane ends with"
for key in selects cues deferred; do
  assert_not_contains "$front" "$key:" "lane: a producer carries no $key: key"
done
view="$("$TEST_PYTHON" - <<'PY' 2>&1
from registry.lanes import catalogue
c = catalogue()
lane = c.lane("workflow")
print("producer:", "workflow" in c.producers)
print("selector:", "workflow" in c.selectors)
print("chain:", " -> ".join(lane.chain))
print("deferred:", "workflow" in c.deferred)
print("interactive:", lane.is_interactive)
PY
)"
assert_contains "$view" "producer: True" "lane: the catalogue lists workflow among the producers"
assert_contains "$view" "selector: False" "lane: workflow selects no label — a producer files, it never selects"
assert_contains "$view" "chain: /sweep -> /wrap-up-session" "lane: the chain is /sweep then /wrap-up-session"
assert_contains "$view" "deferred: False" "lane: workflow is not deferred"
assert_contains "$view" "interactive: False" "lane: workflow is reachable by no /go cue"
assert_file_contains "$LANE" "/sweep --routine workflow" "lane: step 1 runs the workflow lens through /sweep"
assert_file_contains "$LANE" "non-skippable" "lane: its gates are non-skippable"

printf '\n-- lens: the evidence bar as written --\n'
assert_file_exists "$LENS" "lens: $LENS exists"
lens="$(flatten "$LENS" 2>/dev/null)"
for token in "workflow-incidence.py" "file:line" "source digest" "severity" "confidence" "autofix_class" "owner" \
  "75" "NITPICK" "single-agent agreement" "two distinct completed sessions" "Mode C" "Unverified" \
  "Coverage gaps" "advance" "parent and sub-agent" "read-incidence" "grade-read-shunt" "claude-mem"; do
  assert_contains "$lens" "$token" "lens: names '$token'"
done
assert_file_contains ".agents/skills/sweep/SKILL.md" "references/lens-workflow.md" \
  "sweep: the shared spine routes --routine workflow to its lens file"
assert_file_matches "$CANON" '^### `workflow` — steps' "contract: workflow has a step section"
assert_file_matches "$CANON" '^\| `routine/workflow/<YYYYMMDD>-sweep` \|' "contract: the linkage table has the workflow row"
assert_file_exists "$PROMPT" "prompt: the routine prompt exists"
assert_prose_contains "$PROMPT" "manual" "prompt: the first run is manual"
assert_prose_contains ".agents/skills/wrap-up-session/references/routine-prompts/README.md" "manual run" \
  "prompt README: scheduling waits for a reviewed manual run"
assert_eq "routine/workflow/20261120-sweep" \
  "$("$TEST_PYTHON" .agents/skills/wrap-up-session/scripts/routine_branch.py format workflow 20261120 sweep 2>&1)" \
  "branch: routine_branch.py formats the workflow run-stamp branch"

# ============================================================================
# 2. the cursor never advances past unread input
# ============================================================================
printf '\n-- cursor --\n'
TMP="$(fixture_dir)"
export HOME="$TMP/home"
ROOT="$HOME/.claude/projects"
CUR="$HOME/.local/state/cursor.json"
REP="$HOME/.local/state/report.json"
mkdir -p "$ROOT"

# Synthetic sessions: no real transcript content. s1..s3 are settled (a day
# old, one minute apart), `live` is open (now), and `bad` cannot be parsed.
"$TEST_PYTHON" - "$ROOT" <<'PY'
import json, os, sys, time
root = sys.argv[1]
n = [0]
def rec(kind, content, side=False, usage=None, structured=None):
    n[0] += 1
    msg = {"role": kind, "content": content}
    if kind == "assistant":
        msg["id"] = f"m{n[0]}"
        msg["usage"] = usage or {"input_tokens": 10, "output_tokens": 5}
    r = {"type": kind, "isSidechain": side, "timestamp": f"2026-11-01T00:00:{n[0] % 60:02d}Z", "message": msg}
    if structured is not None:
        r["toolUseResult"] = structured
    return r
def use(i, name, inp, side=False, usage=None):
    return rec("assistant", [{"type": "tool_use", "id": i, "name": name, "input": inp}], side, usage)
def res(i, text="ok", err=False, structured=None, side=False):
    return rec("user", [{"type": "tool_result", "tool_use_id": i, "content": text, "is_error": err}], side,
               structured=structured)
def read(i, path, side=False):
    f = {"type": "text", "file": {"filePath": path, "content": "x\n", "numLines": 1, "startLine": 1, "totalLines": 1}}
    return [use(i, "Read", {"file_path": path}, side), res(i, "     1\tx\n", structured=f, side=side)]
def session(name, extra=(), big=False):
    first = {"input_tokens": 90000 if big else 10, "output_tokens": 1}
    lines = [rec("assistant", [{"type": "text", "text": "hi"}], usage=first)]
    lines += read(f"{name}r1", "/w/a.py") + read(f"{name}r2", "/w/a.py")            # duplicated read
    lines += [use(f"{name}d1", "Bash", {"command": "rm -rf build"}), res(f"{name}d1", "denied", err=True, structured="denied"),
              use(f"{name}d2", "Bash", {"command": "rm -rf build"}), res(f"{name}d2", "denied", err=True, structured="denied")]
    return lines + list(extra)
def write(path, lines, age):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(json.dumps(l) for l in lines) + "\n")
    t = time.time() - age
    os.utime(path, (t, t))
day = 86400
loop = [use("q1", "mcp__h__headroom_retrieve", {"hash": "abc"}), res("q1", "gone", err=True, structured="gone"),
        use("q2", "mcp__h__headroom_retrieve", {"hash": "abc"}), res("q2", "gone", err=True, structured="gone")]
suite = []
for k in range(3):
    suite += [use(f"t{k}", "Bash", {"command": "bash tests/run.sh"}), res(f"t{k}", "RESULT ok")]
handover = [use("h1", "Edit", {"file_path": "/w/tasks/todo.md", "old_string": "a", "new_string": "> Handover: slice 1 done"}),
            res("h1"), use("g1", "Agent", {"prompt": "build slice 2"}),
            res("g1", "done", structured={"status": "completed", "content": [{"type": "text", "text": "ok"}],
                                         "totalTokens": 5, "totalToolUseCount": 1, "agentId": "x1"})]
write(f"{root}/proj-a/s1.jsonl", session("s1", loop + suite + handover), 3 * day)
# s1's sub-agent re-reads too: counted in its own context, never the parent's.
write(f"{root}/proj-a/s1/subagents/agent-x1.jsonl",
      read("x1r1", "/w/b.py", True) + read("x1r2", "/w/b.py", True), 3 * day)
write(f"{root}/proj-a/s2.jsonl", session("s2", big=True), 3 * day - 60)
bad = [use("b1", "Read", {"file_path": "/w/c.py"}), res("b1", "?", structured={"type": "text"})]
write(f"{root}/proj-a/bad.jsonl", bad, 3 * day - 120)
write(f"{root}/-x-observer-sessions/s3.jsonl", session("s3"), 3 * day - 180)
write(f"{root}/proj-a/live.jsonl", session("live"), 0)
PY

eng() { "$TEST_PYTHON" "$ENGINE" "$@" --root "$ROOT" --cursor "$CUR"; }

out="$(eng pending 2>&1)"; code=$?
assert_eq "0" "$code" "pending: exits 0 when settled sessions wait after the cursor"
assert_contains "$out" "4 settled" "pending: counts the four settled sessions and not the open one"

out="$(eng scan --report "$REP" --max-sessions 2 2>&1)"; code=$?
assert_eq "0" "$code" "scan: exits 0"
assert_file_absent "$CUR" "scan: a scan never moves the cursor — the report is written, the cursor is not"
assert_contains "$out" "Examined 2 session(s)" "scan: --max-sessions 2 examines two sessions"
assert_contains "$out" "unexamined 2 (stopped by max-sessions)" "scan: a capped run names what it left unexamined"
assert_contains "$out" "open sessions skipped 1" "scan: the open session is skipped, not read"
assert_not_contains "$out" "$HOME" "scan: no absolute path under the home directory is printed"
json() { "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$REP" "$1"; }
assert_eq "proj-a/s2.jsonl" "$(json 'd["cursor_to"]["through"]["path"]')" \
  "scan: the proposed cursor is the last session examined, not the last session found"
assert_eq "proj-a/bad.jsonl" "$(json 'd["unexamined_first"]')" "scan: the report names the first unexamined session"
assert_not_contains "$(cat "$REP")" "$HOME" "report: the JSON report carries no absolute home path"

pat() { json "[p for p in d['patterns'] if p['kind']=='$1'][0]['$2'] if [p for p in d['patterns'] if p['kind']=='$1'] else 'absent'"; }
assert_eq "2" "$(pat duplicated-read distinct_sessions)" "rank: a duplicated read in two sessions counts two distinct sessions"
assert_eq "True" "$(pat duplicated-read meets_repeat_bar)" "rank: two distinct sessions meet the repeat bar"
assert_eq "2" "$(pat duplicated-read parent)" "rank: the parent contexts' duplicated reads are counted as parent"
assert_eq "1" "$(pat duplicated-read subagent)" "rank: the sub-agent's re-read is counted apart, as subagent"
assert_eq "2" "$(pat repeated-denied-call distinct_sessions)" "rank: a call denied twice is a repeated-denied-call"
assert_eq "False" "$(pat expired-retrieval-loop meets_repeat_bar)" "rank: a one-session pattern does not meet the repeat bar"
assert_eq "1" "$(pat repeated-full-suite parent)" "rank: the third full suite in one context is a candidate"
assert_eq "1" "$(pat forgotten-handover parent)" "rank: an Agent dispatched after a handover with no handover named"
assert_eq "1" "$(pat excessive-fixed-context distinct_sessions)" "rank: a first turn over the fixed-context threshold"
assert_contains "$(json 'd["patterns"][0]["occurrences"][0]["anchor"]')" ".jsonl:" \
  "rank: an anchor is a transcript:line"
assert_true "scan: every examined session carries a digest and the read-incidence row" -- \
  "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(e["digest"] and "whole_large" in e["read_incidence"] for e in d["examined"])' "$REP"

out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "0" "$code" "advance: exits 0"
assert_contains "$out" "2 session(s) remain" "advance: says how many sessions remain after the cursor"
out="$(eng pending 2>&1)"
assert_contains "$out" "2 settled" "advance: the cursor moved exactly past the two examined sessions"

out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "2" "$code" "advance: a report scanned from a cursor that has since moved is refused"
assert_contains "$out" "rescan" "advance: the refusal says to rescan"

out="$(eng scan --report "$REP" --token-budget 1 2>&1)"; code=$?
assert_eq "0" "$code" "scan: a budget of 1 still exits 0"
assert_contains "$out" "coverage gaps 1" "scan: the first session is read even over budget, so one session cannot wedge the cursor"
assert_contains "$out" "stopped by token-budget" "scan: the token budget stops the run and says so"
assert_contains "$out" "proj-a/bad.jsonl" "scan: the unreadable transcript is a named coverage gap"
assert_not_contains "$out" "Examined 1" "scan: a gap is not counted as an examined session"
eng advance --report "$REP" >/dev/null 2>&1
eng scan --report "$REP" >/dev/null 2>&1
eng advance --report "$REP" >/dev/null 2>&1
out="$(eng pending 2>&1)"; code=$?
assert_eq "1" "$code" "pending: exits 1 once only the open session is left — the precheck skips a run with nothing to do"
assert_contains "$(cat "$CUR")" "s3.jsonl" "cursor: stops at the last settled session, before the open one"

out="$(eng scan --report "$REP" 2>&1)"
assert_contains "$out" "Examined 0 session(s)" "scan: nothing after the cursor examines nothing"
out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "0" "$code" "advance: an empty report advances nothing and exits 0"
assert_contains "$out" "stays where it is" "advance: an empty report leaves the cursor in place"

printf '{"version": 9}' > "$TMP/badcursor.json"
out="$("$TEST_PYTHON" "$ENGINE" pending --root "$ROOT" --cursor "$TMP/badcursor.json" 2>&1)"; code=$?
assert_eq "2" "$code" "cursor: an unreadable cursor is exit 2, never a silent rescan or skip"

# ============================================================================
# 3. one parser: the engine extracts nothing itself
# ============================================================================
printf '\n-- shared parser --\n'
assert_eq "1" "$(grep -c '^import read_transcript as rt' "$ENGINE")" "engine: imports the shared parser once"
assert_file_contains "$ENGINE" "measure_session" "engine: reuses read-incidence's per-session row"
for marker in 'toolUseResult' '"tool_use"' '"tool_result"' '"usage"' 'cache_read_input_tokens' 'isSidechain' 'compact_boundary' '"message"'; do
  assert_eq "0" "$(grep -cF "$marker" "$ENGINE")" "engine: never touches $marker — the parser owns that block"
done

finish
