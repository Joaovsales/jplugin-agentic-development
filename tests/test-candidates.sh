#!/bin/bash
# tests/test-candidates.sh — .agents/skills/build/scripts/candidates.py
# (specs/parallel-candidates.md AC1–AC4): N candidate worktrees for one slice,
# a deterministic lexicographic ranking from recorded measurements, failed
# candidates never selected, every worktree removed (cancellation included),
# and every candidate's place and reason recorded in the run ledger.
. "$(dirname "$0")/lib.sh"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh
SCRIPT="$(under_test .agents/skills/build/scripts/candidates.py)"
SCRIPTS_DIR="${SCRIPT%/*}"
BOX="$(fixture_dir)"
RUN_ID="feat-c-0123456789ab"

# make_repo — a repository whose spec's one implicit slice has Surface src/**,
# with an untracked .env the worktree bootstrap copies into every candidate.
make_repo() {
  local r; r="$(fixture_repo)"
  mkdir -p "$r/specs" "$r/src"
  printf -- '---\nimplementation_paths:\n  - src/**\n---\n\n# Spec: f\n' > "$r/specs/f.md"
  printf 'base\n' > "$r/src/base.txt"
  git -C "$r" add -A && git -C "$r" commit -qm init
  printf 'SECRET=1\n' > "$r/.env"
  printf '%s\n' "$r"
}

cand() { (cd "$REPO" && "$PY" "$SCRIPT" "$@" </dev/null 2>&1); }
wt_count() { git -C "$REPO" worktree list --porcelain | grep -c '^worktree '; }
path_of() { printf '%s\n' "$1" | awk -v c="candidates: $2 " 'index($0, c) == 1 { print $3 }'; }

# fill <open output> — c1: 3 src lines, passes; c2: 1 src line plus 1 line
# outside the Surface, passes; c3: 1 src line, fails (no src/ok marker).
fill() {
  local p1 p2 p3
  p1="$(path_of "$1" c1)"; p2="$(path_of "$1" c2)"; p3="$(path_of "$1" c3)"
  printf 'a\nb\nc\n' > "$p1/src/a.txt"; : > "$p1/src/ok"
  printf 'a\n' > "$p2/src/a.txt"; : > "$p2/src/ok"; mkdir -p "$p2/docs"; printf 'x\n' > "$p2/docs/x.txt"
  printf 'a\n' > "$p3/src/a.txt"
}

rank3() {  # rank3 <ledger> — the three-candidate rank call
  cand rank --spec specs/f.md --slice 1 --branch feat/c --base 0123456789abcdef --ledger "$1" \
    --agent c1=true --agent c2=true --agent c3=true -- sh -c 'test -f src/ok'
}

begin_case "rank"
REPO="$(make_repo)"
out="$(cand open --slice 1 --count 3)"; st=$?
assert_eq 0 "$st" "open creates the candidates"
assert_eq 4 "$(wt_count)" "open adds one worktree per candidate"
assert_contains "$out" "candidates: c3 " "open prints one line per candidate"
fill "$out"
out="$(rank3 "$BOX/l1")"; st=$?
assert_eq 0 "$st" "rank exits 0 when a winner is applied"
assert_contains "$out" "candidates: c2 rank=1 selected eligible checks=2/2 diff_lines=2 outside_surface=1 SUCCEEDED — selected: ahead of c1 on diff_lines (2 vs 3)" \
  "the smallest eligible diff wins and the reason names the deciding signal"
assert_contains "$out" "candidates: c1 rank=2 discarded eligible checks=2/2 diff_lines=3 outside_surface=0 SUCCEEDED — behind c2 on diff_lines (3 vs 2)" \
  "an eligible loser names the candidate above it and the signal"
assert_contains "$out" "candidates: c3 rank=3 discarded ineligible checks=1/2 diff_lines=1 outside_surface=0 VERIFICATION_FAILED — ineligible: VERIFICATION_FAILED" \
  "a failed candidate is ineligible even with the smallest diff"
assert_contains "$out" "candidates: applied c2" "rank reports the applied winner"
assert_eq "a" "$(cat "$REPO/src/a.txt")" "the winner's diff lands in the main tree"
assert_file_exists "$REPO/docs/x.txt" "the winner's file outside the Surface lands too"
assert_eq "SECRET=1" "$(cat "$REPO/.env")" "the bootstrap's copied .env is not part of the winner's diff"
assert_eq 1 "$(wt_count)" "rank removes every candidate worktree on success"
end_case

begin_case "deterministic"
order="$("$PY" - "$SCRIPTS_DIR" <<'EOF'
import itertools, sys
sys.path.insert(0, sys.argv[1])
from candidates import Candidate, rank_entries
pool = [
    Candidate(1, "True", "True", 3, 0), Candidate(2, "True", "True", 3, 0),
    Candidate(3, "True", "True", 2, 4), Candidate(4, "True", "False", 1, 0),
    Candidate(5, "Unknown", "True", 1, 0), Candidate(6, "True", "True", 2, 1),
]
seen = {tuple((e["candidate"], e["rank"], e["reason"]) for e in rank_entries(list(p)))
        for p in itertools.permutations(pool)}
print(len(seen))
print(" ".join(e["candidate"] for e in rank_entries(pool)))
print(next(e["reason"] for e in rank_entries(pool) if e["candidate"] == "c2"))
EOF
)"
assert_eq "1" "$(sed -n 1p <<<"$order")" "every input order of the same set gives one ranking"
assert_eq "c6 c3 c1 c2 c4 c5" "$(sed -n 2p <<<"$order")" "eligible first, then diff lines, outside-Surface paths and candidate number"
assert_eq "behind c1 on candidate number (c2 vs c1)" "$(sed -n 3p <<<"$order")" "a full tie is broken by the candidate number and says so"
REPO="$(make_repo)"
first="$(cand open --slice 1 --count 3)"; fill "$first"; run1="$(rank3 "$BOX/d1" | grep '^candidates: c')"
git -C "$REPO" checkout -q -- . && git -C "$REPO" clean -qfd -e .env
second="$(cand open --slice 1 --count 3)"; fill "$second"; run2="$(rank3 "$BOX/d2" | grep '^candidates: c')"
assert_eq "$run1" "$run2" "two rank runs over identically built candidates print identical lines"
end_case

begin_case "eligibility"
REPO="$(make_repo)"
out="$(cand open --slice 1 --count 2)"
p1="$(path_of "$out" c1)"; p2="$(path_of "$out" c2)"
printf 'a\n' > "$p1/src/a.txt"; : > "$p1/src/ok"
printf 'a\nb\n' > "$p2/src/a.txt"; : > "$p2/src/ok"
out="$(cand rank --spec specs/f.md --slice 1 --branch feat/c --base 0123456789abcdef --ledger "$BOX/e1" \
  --agent c1=false --agent c2=true -- sh -c 'test -f src/ok')"
assert_contains "$out" "candidates: c2 rank=1 selected" "a candidate whose agent check failed loses to a larger passing one"
assert_contains "$out" "candidates: c1 rank=2 discarded ineligible checks=1/2 diff_lines=1 outside_surface=0 AGENT_FAILED — ineligible: AGENT_FAILED" \
  "the failed agent check is the recorded reason"
REPO="$(make_repo)"
out="$(cand open --slice 1 --count 2)"
p1="$(path_of "$out" c1)"; p2="$(path_of "$out" c2)"
printf 'a\n' > "$p1/src/a.txt"; printf 'b\n' > "$p2/src/a.txt"
before="$(git -C "$REPO" status --porcelain)"
out="$(cand rank --spec specs/f.md --slice 1 --branch feat/c --base 0123456789abcdef --ledger "$BOX/e2" \
  --agent c1=true -- sh -c 'test -f src/ok')"; st=$?
assert_eq 1 "$st" "rank exits 1 when no candidate is eligible"
assert_contains "$out" "candidates: no eligible candidate — nothing applied" "and says nothing was applied"
assert_contains "$out" "candidates: c2 rank=2 discarded ineligible checks=0/2" "an agent with no claim is unknown, never a pass"
assert_eq "$before" "$(git -C "$REPO" status --porcelain)" "the main tree is unchanged"
assert_eq 1 "$(wt_count)" "rank removes every candidate worktree when nothing wins"
end_case

begin_case "cleanup"
REPO="$(make_repo)"
cand open --slice 2 --count 2 >/dev/null
assert_refused 1 "discard" "open refuses while the slice still has candidate worktrees" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' open --slice 2 --count 2"
out="$(cand discard --slice 2)"
assert_contains "$out" "candidates: removed c2 " "discard names each removed candidate"
assert_eq 1 "$(wt_count)" "discard removes every candidate worktree of the slice"
assert_refused 1 "no candidate worktrees" "rank with no candidate worktrees is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/f.md --slice 2 --branch b --base 0123456789abcdef -- true"
assert_refused 2 "at least 2" "a candidate count below 2 is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' open --slice 1 --count 1"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) skip "SIGTERM delivery to a native Python process is not POSIX here" ;;
  *)
    out="$(cand open --slice 1 --count 2)"
    mark="$BOX/started"
    (cd "$REPO" && exec "$PY" "$SCRIPT" rank --spec specs/f.md --slice 1 --branch b --base 0123456789abcdef \
      --ledger "$BOX/c1" -- sh -c "touch '$mark'; sleep 5" </dev/null >"$BOX/term.out" 2>&1) &
    pid=$!
    for _ in $(seq 1 100); do [ -e "$mark" ] && break; sleep 0.1; done
    assert_file_exists "$mark" "the verification started before cancellation"
    kill -TERM "$pid"; wait "$pid"; st=$?
    assert_true "a terminated rank exits non-zero" -- test "$st" -ne 0
    assert_eq 1 "$(wt_count)" "a terminated rank removes every candidate worktree"
    assert_file_absent "$(path_of "$out" c1)" "the candidate directory itself is gone"
    ;;
esac
end_case

begin_case "refusals"
REPO="$(make_repo)"
out="$(cand open --slice 1 --count 2)"
p1="$(path_of "$out" c1)"; printf 'theirs\n' > "$p1/src/base.txt"; : > "$p1/src/ok"
cand open --slice 7 --count 2 >/dev/null
assert_refused 1 "no slice 7" "a slice the spec does not have is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/f.md --slice 7 --branch b --base 0123456789abcdef -- true"
assert_eq 5 "$(wt_count)" "a refused slice keeps its candidates' work"
cand discard --slice 7 >/dev/null
assert_refused 1 "nope.md" "a spec that does not exist is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/nope.md --slice 1 --branch b --base 0123456789abcdef -- true"
assert_eq 3 "$(wt_count)" "a refused rank call keeps the candidates' work"
assert_refused 2 "run id" "a run id that is not a safe file name is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/f.md --slice 1 --branch b --base 0123456789abcdef --run-id ../escape -- true"
assert_refused 2 "--base" "a base that is not a commit SHA is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/f.md --slice 1 --branch b --base main -- true"
printf 'mine\n' > "$REPO/src/base.txt"
assert_refused 1 "does not apply" "a winner whose diff conflicts with the main tree is refused" -- \
  sh -c "cd '$REPO' && '$PY' '$SCRIPT' rank --spec specs/f.md --slice 1 --branch feat/c --base 0123456789abcdef --ledger '$BOX/r1' --agent c1=true -- sh -c 'test -f src/ok'"
assert_file_exists "$REPO/tasks/tmp/candidates-slice-1-c1.patch" "the conflicting winner's patch is kept"
assert_eq "mine" "$(cat "$REPO/src/base.txt")" "the main tree keeps its own change"
assert_file_exists "$BOX/r1/$RUN_ID.json" "the ranking is recorded even when the winner does not apply"
assert_eq 1 "$(wt_count)" "the worktrees are removed after a failed apply"
end_case

begin_case "ledger"
F="$BOX/l1/$RUN_ID.json"
assert_file_exists "$F" "rank writes the run record named by branch and base"
fields="$("$PY" -c 'import json,sys; r=json.load(open(sys.argv[1]))
print(r["schema"], r["branch"], len(r["candidates"]["1"]))
for e in r["candidates"]["1"]:
    print(e["candidate"], e["rank"], e["selected"], e["eligible"], e["agent_result"], e["verification_result"],
          e["slice_result"], e["label"], e["checks_passed"], e["diff_lines"], e["outside_surface"], "|", e["reason"])' "$F")"
assert_eq "run-ledger/1 feat/c 3
c2 1 True True True True True SUCCEEDED 2 2 1 | selected: ahead of c1 on diff_lines (2 vs 3)
c1 2 False True True True True SUCCEEDED 2 3 0 | behind c2 on diff_lines (3 vs 2)
c3 3 False False True False False VERIFICATION_FAILED 1 1 0 | ineligible: VERIFICATION_FAILED" \
  "$fields" "the record holds every candidate with rank, outcomes, measurements and reason"
run "$PY" "$SCRIPTS_DIR/run_ledger.py" record --ledger "$BOX/l1" --branch feat/c --base 0123456789abcdef \
  --slice "1 attempts=3 agent_result=True verification_result=True slice_result=True SUCCEEDED"
assert_exit 0 "Phase 6 records the same run"
kept="$("$PY" -c 'import json,sys; r=json.load(open(sys.argv[1])); print(len(r["candidates"]["1"]), r["slices"][0]["attempts"])' "$F")"
assert_eq "3 3" "$kept" "a later record keeps the candidates"
run "$PY" "$SCRIPTS_DIR/run_ledger.py" stats --ledger "$BOX/l1"
assert_exit 0 "stats reads a record that carries candidates"
lib() {  # lib <python body> — run_ledger imported, Path, `L` the ledger dir
  "$PY" -c "import sys; sys.path.insert(0, sys.argv[1]); import run_ledger as rl
from pathlib import Path; L = Path(sys.argv[2])
$1" "$SCRIPTS_DIR" "$BOX/l1" 2>&1
}
held="$(lib 'rl.LOCK_TIMEOUT = 0.2
with rl.run_lock(L / "held.json"):
    try:
        rl.add_candidates(L, "feat/c", "0123456789abcdef", "held", "1", [])
    except rl.Refused as exc:
        print(exc)')"
assert_contains "$held" "timed out waiting for run lock" "add_candidates waits on the same per-run lock as record"
printf '{"schema": "run-ledger/1", "run_id": "bad", "human_result": "maybe"}\n' > "$BOX/l1/bad.json"
before="$(cat "$BOX/l1/bad.json")"
bad="$(lib 'try:
    rl.add_candidates(L, "feat/c", "0123456789abcdef", "bad", "1", [])
except rl.Refused as exc:
    print(exc)')"
assert_contains "$bad" "bad.json: invalid" "add_candidates refuses a malformed stored record"
assert_eq "$before" "$(cat "$BOX/l1/bad.json")" "a refused add_candidates leaves the record untouched"
rm "$BOX/l1/bad.json"
"$PY" -c 'import json,sys; r=json.load(open(sys.argv[1])); r["candidates"]=[]; json.dump(r, open(sys.argv[1], "w"))' "$F"
run "$PY" "$SCRIPTS_DIR/run_ledger.py" stats --ledger "$BOX/l1"
assert_exit 1 "stats refuses a record whose candidates field is not an object"
assert_contains "$output" "invalid candidates" "the refusal names the candidates field"
end_case

finish
