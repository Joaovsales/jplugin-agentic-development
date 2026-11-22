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
  "Coverage gaps" "advance" "parent and sub-agent" "read-incidence" "grade-read-shunt" "claude-mem" \
  "Scope and privacy" "this repository" "<session-id>" "never a transcript excerpt" "max-session-tokens"; do
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
# 2. scope and cursor: this repository's sessions only, never past unread input
# ============================================================================
printf '\n-- scope and cursor --\n'
TMP="$(fixture_dir)"
export HOME="$TMP/home"
ROOT="$HOME/.claude/projects"
CUR="$HOME/.local/state/cursor.json"
REP="$HOME/.local/state/report.json"
APP="$HOME/src/app"; OTHER="$HOME/src/other"; WT="$HOME/wt/app"
mkdir -p "$ROOT" "$APP" "$OTHER" "$WT" "$HOME/.claude-mem/observer-sessions"
g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
g -C "$APP" init && g -C "$APP" commit --allow-empty -m init
g -C "$OTHER" init && g -C "$OTHER" commit --allow-empty -m init
g -C "$APP" worktree add -b live "$WT/live" && g -C "$APP" worktree add -b gone "$WT/gone"
g -C "$APP" worktree remove --force "$WT/gone"
# A stale checkout whose registration git pruned still points into this
# repository's git directory: it must not disqualify the folder it sits in.
g -C "$APP" worktree add -b stale "$WT/stale" && rm -rf "$APP/.git/worktrees/stale"
mkdir -p "$WT/live/sub"
printf '# app\n\nFull suite: bash tests/run.sh\n' > "$APP/AGENTS.md"    # the live worktree declares none

# Synthetic sessions, no real transcript content. In scope (this repository):
# s1 (main checkout, with a sub-agent), s2 (a live worktree), bad (a deleted
# worktree under a directory holding only this repository's worktrees; its
# transcript cannot be parsed), s3 (main checkout), live (open, now). Out of
# scope: o1 (another repository), obs (claude-mem's observer). Unattributable:
# u1 (a deleted directory nothing attributes), u2 (no working directory). And
# one plugin log under a project directory, which is no session at all.
"$TEST_PYTHON" - "$ROOT" "$APP" "$WT" "$OTHER" "$HOME" <<'FIXTURE'
import json, os, sys, time
root, app, wt, other, home = sys.argv[1:]
n = [0]
CWD = [None]
def rec(kind, content, side=False, usage=None, structured=None):
    n[0] += 1
    msg = {"role": kind, "content": content}
    if kind == "assistant":
        msg["id"] = f"m{n[0]}"
        msg["usage"] = usage or {"input_tokens": 10, "output_tokens": 5}
    r = {"type": kind, "isSidechain": side, "timestamp": f"2026-11-01T00:00:{n[0] % 60:02d}Z", "message": msg}
    if CWD[0]:
        r["cwd"] = CWD[0]
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
def session(name, cwd, extra=(), big=False):
    CWD[0] = cwd
    first = {"input_tokens": 90000 if big else 10, "output_tokens": 1}
    lines = [rec("assistant", [{"type": "text", "text": "hi"}], usage=first)]
    lines += read(f"{name}r1", "/w/a.py") + read(f"{name}r2", "/w/a.py")            # duplicated read
    cmd = {"command": f"ls {cwd}/build"} if cwd else {"command": "ls build"}
    lines += [use(f"{name}d1", "Bash", cmd), res(f"{name}d1", "denied", err=True, structured="denied"),
              use(f"{name}d2", "Bash", cmd), res(f"{name}d2", "denied", err=True, structured="denied")]
    return lines + list(extra)
def write(path, lines, age):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(json.dumps(l) for l in lines) + "\n")
    t = time.time() - age
    os.utime(path, (t, t))
day = 86400
CWD[0] = app
loop = [use("q1", "mcp__h__headroom_retrieve", {"hash": "abc"}), res("q1", "gone", err=True, structured="gone"),
        use("q2", "mcp__h__headroom_retrieve", {"hash": "abc"}), res("q2", "gone", err=True, structured="gone")]
# Three real runs of the declared suite (one wrapped in env, flags and
# redirections), plus runs narrowed to a file and a commit message that only
# mentions the command — those two are not full-suite runs.
suite = []
for k, cmd in enumerate(["bash tests/run.sh", "env -u X bash tests/run.sh --jobs 8 </dev/null > log 2>&1",
                         "bash tests/run.sh tests/test-x.sh", "bash tests/run.sh tests/test-x.sh",
                         "git commit -m 'RESULT of bash tests/run.sh'", "cd sub && bash tests/run.sh"]):
    suite += [use(f"t{k}", "Bash", {"command": cmd}), res(f"t{k}", "RESULT ok")]
handover = [use("h1", "Edit", {"file_path": "/w/tasks/todo.md", "old_string": "a", "new_string": "> Handover: slice 1 done"}),
            res("h1"), use("g1", "Agent", {"prompt": "build slice 2"}),
            res("g1", "done", structured={"status": "completed", "content": [{"type": "text", "text": "ok"}],
                                         "totalTokens": 5, "totalToolUseCount": 1, "agentId": "x1"})]
write(f"{root}/proj-a/s1.jsonl", session("s1", app, loop + suite + handover), 3 * day)
# s1's sub-agent re-reads too: counted in its own context, never the parent's.
write(f"{root}/proj-a/s1/subagents/agent-x1.jsonl",
      read("x1r1", "/w/b.py", True) + read("x1r2", "/w/b.py", True), 3 * day)
write(f"{root}/proj-o/o1.jsonl", session("o1", other), 3 * day - 30)
write(f"{root}/proj-w/s2.jsonl", session("s2", f"{wt}/live/sub", big=True), 3 * day - 60)
write(f"{root}/obs/obs.jsonl", session("obs", f"{home}/.claude-mem/observer-sessions"), 3 * day - 90)
CWD[0] = f"{wt}/gone"
bad = [use("b1", "Read", {"file_path": "/w/c.py"}), res("b1", "?", structured={"type": "text"})]
write(f"{root}/proj-g/bad.jsonl", bad, 3 * day - 120)
write(f"{root}/proj-u/u1.jsonl", session("u1", f"{home}/nowhere/deleted"), 3 * day - 150)
write(f"{root}/proj-u/u2.jsonl", session("u2", None), 3 * day - 160)
write(f"{root}/proj-a/s3.jsonl", session("s3", app), 3 * day - 180)
write(f"{root}/proj-a/plugin/skill-injections.jsonl", [{"note": "not a session"}], 3 * day - 200)
write(f"{root}/proj-a/live.jsonl", session("live", app), 0)
FIXTURE

eng() { (cd "$APP" && "$TEST_PYTHON" "$REPO/$ENGINE" "$@" --root "$ROOT" --cursor "$CUR"); }

out="$(eng pending 2>&1)"; code=$?
assert_eq "0" "$code" "pending: exits 0 when settled sessions of this repository wait after the cursor"
assert_contains "$out" "4 settled session(s) of this repository" \
  "pending: counts this repository's four settled sessions — not other projects, observers, the open one or a plugin log"

out="$(eng scan --report "$REP" --max-sessions 2 2>&1)"; code=$?
assert_eq "0" "$code" "scan: exits 0"
assert_file_absent "$CUR" "scan: a scan never moves the cursor — the report is written, the cursor is not"
assert_contains "$out" "Examined 2 session(s)" "scan: --max-sessions 2 examines two sessions"
assert_contains "$out" "unexamined 2 (stopped by max-sessions)" "scan: a capped run names what it left unexamined"
assert_contains "$out" "open sessions skipped 1" "scan: the open session is skipped, not read"
assert_contains "$out" "Out of scope 2" "scope: another repository's session and the observer's are out of scope"
assert_contains "$out" "unattributable 2" "scope: a deleted directory nothing attributes and a session with no cwd are counted, not read"
assert_not_contains "$out" "$HOME" "scan: no absolute path under the home directory is printed"
assert_not_contains "$out" "proj-" "scan: no project directory name is printed"
json() { "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$REP" "$1"; }
assert_eq "s2" "$(json 'd["cursor_to"]["through"]["session"]')" \
  "scan: the proposed cursor is the last session examined (a live worktree's), not the last session found"
assert_eq "bad" "$(json 'd["unexamined_first"]')" \
  "scope: a deleted worktree under a directory of this repository's worktrees is in scope, named by session id"
assert_not_contains "$(json 'd["examined"]')" "proj-" "report: examined sessions are named by session id only"
assert_not_contains "$(cat "$REP")" "$HOME" "report: the JSON report carries no absolute home path"

pat() { json "[p for p in d['patterns'] if p['kind']=='$1'][0]['$2'] if [p for p in d['patterns'] if p['kind']=='$1'] else 'absent'"; }
assert_eq "2" "$(pat duplicated-read distinct_sessions)" "rank: a duplicated read in two sessions counts two distinct sessions"
assert_eq "True" "$(pat duplicated-read meets_repeat_bar)" "rank: two distinct sessions meet the repeat bar"
assert_eq "2" "$(pat duplicated-read parent)" "rank: the parent contexts' duplicated reads are counted as parent"
assert_eq "1" "$(pat duplicated-read subagent)" "rank: the sub-agent's re-read is counted apart, as subagent"
assert_eq "2" "$(pat repeated-denied-call distinct_sessions)" "rank: a call denied twice is a repeated-denied-call"
assert_eq "False" "$(pat expired-retrieval-loop meets_repeat_bar)" "rank: a one-session pattern does not meet the repeat bar"
assert_eq "1" "$(pat repeated-full-suite parent)" \
  "rank: the third declared full-suite run is a candidate; file-narrowed runs and mentions are not runs"
assert_contains "$out" 'Full suite: `bash tests/run.sh`' "full suite: read from the project's own Full suite: line"
assert_eq "1" "$(pat forgotten-handover parent)" "rank: an Agent dispatched after a handover with no handover named"
assert_eq "1" "$(pat excessive-fixed-context distinct_sessions)" "rank: a first turn over the fixed-context threshold"
assert_eq "absent" "$(pat observer-capture kind)" "rank: observer sessions are out of scope, so no observer kind is ranked"
anchors="$(json '" ".join(o["anchor"] for p in d["patterns"] for o in p["occurrences"])')"
assert_contains "$anchors" "s1:" "anchor: a parent anchor is <session-id>:<line>"
assert_contains "$anchors" "s1/agent-x1:" "anchor: a sub-agent anchor is <session-id>/<agent-id>:<line>"
assert_not_contains "$anchors" ".jsonl" "anchor: no anchor names a transcript file or project directory"
details="$(json '" ".join(o["detail"] for p in d["patterns"] for o in p["occurrences"])')"
assert_contains "$details" "ls ./build" "subject: the session's working directory is written ."
assert_not_contains "$details" "$HOME" "subject: no home path survives in a detail"
assert_true "scan: every examined session carries a digest and the read-incidence row" -- \
  "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(e["digest"] and "whole_large" in e["read_incidence"] for e in d["examined"])' "$REP"

out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "0" "$code" "advance: exits 0"
assert_contains "$out" "2 session(s) remain" "advance: says how many sessions remain after the cursor"
assert_not_contains "$out" "proj-" "advance: names the cursor by session id"
out="$(eng pending 2>&1)"
assert_contains "$out" "2 settled" "advance: the cursor moved exactly past the two examined sessions"

out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "2" "$code" "advance: a report scanned from a cursor that has since moved is refused"
assert_contains "$out" "rescan" "advance: the refusal says to rescan"

out="$( (cd "$OTHER" && "$TEST_PYTHON" "$REPO/$ENGINE" pending --root "$ROOT" --cursor "$CUR") 2>&1)"; code=$?
assert_eq "2" "$code" "cursor: a cursor belongs to one repository — another repository's run refuses it"
assert_contains "$out" "another" "cursor: the refusal says the cursor belongs to another scope"

out="$(eng scan --report "$REP" --token-budget 1 2>&1)"; code=$?
assert_eq "0" "$code" "scan: a budget of 1 still exits 0"
assert_contains "$out" "coverage gaps 1" "scan: the first session is read even over budget, so one session cannot wedge the cursor"
assert_contains "$out" "stopped by token-budget" "scan: the token budget stops the run and says so"
assert_contains "$out" "- bad:" "scan: the unreadable transcript is a coverage gap named by session id"
assert_contains "$out" "<project>/bad.jsonl:" "scan: a gap's reason names the transcript without its project directory"
assert_not_contains "$out" "Examined 1" "scan: a gap is not counted as an examined session"
eng advance --report "$REP" >/dev/null 2>&1
eng scan --report "$REP" >/dev/null 2>&1
eng advance --report "$REP" >/dev/null 2>&1
out="$(eng pending 2>&1)"; code=$?
assert_eq "1" "$code" "pending: exits 1 once only the open session is left — the precheck skips a run with nothing to do"
assert_contains "$(cat "$CUR")" '"session": "s3"' "cursor: stops at the last settled session, before the open one"
assert_not_contains "$(cat "$CUR")" "proj-" "cursor: the cursor stores a hash and a session id, never a project directory"

out="$(eng scan --report "$REP" 2>&1)"
assert_contains "$out" "Examined 0 session(s)" "scan: nothing after the cursor examines nothing"
out="$(eng advance --report "$REP" 2>&1)"; code=$?
assert_eq "0" "$code" "advance: an empty report advances nothing and exits 0"
assert_contains "$out" "stays where it is" "advance: an empty report leaves the cursor in place"

# The per-session cap: every session is charged at most --max-session-tokens,
# so an outsized one is read but cannot spend the whole budget alone.
CAP="$HOME/.local/state/cap.json"
out="$( (cd "$APP" && "$TEST_PYTHON" "$REPO/$ENGINE" scan --root "$ROOT" --cursor "$CAP" --report "$CAP.r" \
  --token-budget 4 --max-session-tokens 1) 2>&1)"; code=$?
assert_eq "0" "$code" "cap: a capped scan exits 0"
assert_contains "$out" "Examined 3 session(s); coverage gaps 1" \
  "cap: a budget of 4 at one token per session reads all four settled sessions"
assert_contains "$out" "oversized, charged at the cap 4" "cap: the report counts the sessions charged at the cap"
out="$( (cd "$APP" && "$TEST_PYTHON" "$REPO/$ENGINE" scan --root "$ROOT" --cursor "$CAP" --report "$CAP.r" \
  --token-budget 4 --max-session-tokens 1000000) 2>&1)"
assert_contains "$out" "stopped by token-budget" "cap control: without the cap the same budget stops after one session"

out="$( (cd "$WT/live" && "$TEST_PYTHON" "$REPO/$ENGINE" scan --root "$ROOT" --cursor "$HOME/.local/state/nofs.json" \
  --report "$HOME/.local/state/nofs.r") 2>&1)"
assert_contains "$out" "detector off" "full suite: a project that declares no Full suite: line turns that detector off, and says so"

printf '{"version": 9}' > "$TMP/badcursor.json"
out="$( (cd "$APP" && "$TEST_PYTHON" "$REPO/$ENGINE" pending --root "$ROOT" --cursor "$TMP/badcursor.json") 2>&1)"; code=$?
assert_eq "2" "$code" "cursor: an unreadable cursor is exit 2, never a silent rescan or skip"
out="$( (cd "$TMP" && "$TEST_PYTHON" "$REPO/$ENGINE" pending --root "$ROOT") 2>&1)"; code=$?
assert_eq "2" "$code" "scope: outside a git repository the engine refuses rather than guess a scope"

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
