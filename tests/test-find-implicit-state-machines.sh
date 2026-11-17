#!/bin/bash
# tests/test-find-implicit-state-machines.sh — /find-implicit-state-machines.
#
# The skill's judgement (is this a machine? which transition is hidden?) is the
# agent's; what is tested here is the deterministic helper it leans on:
#   scan   ranks code files by state-like patterns, honouring .gitignore and
#          skipping vendor, generated, test and non-code files;
#   check  refuses a findings file that names a state, file or field that is
#          not there, and computes the Phase 3 flags;
#   tla    turns one finding into a TLA+ skeleton /statechart can check.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$(under_test .agents/skills/find-implicit-state-machines)"
SM="$SKILL/scripts/state_machines.py"
sm() { (cd "$1" && shift && "$TEST_PYTHON" "$SM" "$@"); }

# A git fixture: the seed plus an ignored copy of the machine that only a
# scanner deaf to .gitignore would report.
REPOFX="$(fixture_repo)"
fixture_copy "find-implicit-state-machines/repo/." "$REPOFX"
mkdir -p "$REPOFX/ignored"
cp "$REPOFX/src/order.js" "$REPOFX/ignored/order-copy.js"
printf 'ignored/\n' > "$REPOFX/.gitignore"
# Files that look like machines but must never rank: minified, binary, comments only.
{ printf 'let status = "a"; '; head -c 600 /dev/zero | tr '\0' 'x'; printf '\nswitch (status) {}\n'; } > "$REPOFX/src/bundle.js"
{ cat "$REPOFX/src/order.js"; printf '\0'; } > "$REPOFX/src/blob.js"
sed 's#^#// #' "$REPOFX/src/order.js" > "$REPOFX/src/commented.js"
git -C "$REPOFX" add -A && git -C "$REPOFX" commit -q -m init

if begin_case "scan"; then
  run sm "$REPOFX" scan
  assert_exit 0 "scan: exits 0"
  SCAN="$output"
  BOX="$(fixture_dir)"
  printf '%s' "$SCAN" > "$BOX/scan.json"
  CHECK="$(cd "$REPOFX" && "$TEST_PYTHON" - "$BOX/scan.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
paths = [c["path"] for c in data["candidates"]]
print("first", paths[0] if paths else None)
print("paths", " ".join(sorted(paths)))
print("head", bool(data["head"]))
print("sorted", data["candidates"] == sorted(data["candidates"], key=lambda c: (-c["score"], c["path"])))
for c in data["candidates"]:
    lines = open(c["path"], encoding="utf-8").read().splitlines()
    ok = all(lines[s["line"] - 1].strip() == s["text"] for s in c["samples"])
    print("verbatim", c["path"], ok, len(c["signals"]) >= 2)
PY
)"
  assert_contains "$CHECK" "first src/order.js" "scan: the file with the most state-like patterns ranks first"
  assert_contains "$CHECK" "paths src/mode.py src/order.js" \
    "scan: only code with state patterns ranks — no vendor, .gitignored, @generated, test, markdown or signal-free file"
  assert_contains "$CHECK" "head True" "scan: the output names the head commit"
  assert_contains "$CHECK" "sorted True" "scan: sorted by score desc, then path"
  assert_not_contains "$CHECK" " False" "scan: every sample quotes its line verbatim and every candidate shows two or more signal kinds"
  assert_eq "$SCAN" "$(sm "$REPOFX" scan 2>&1)" "scan: deterministic — a second run is byte-identical"

  run sm "$REPOFX" scan --path src/util.js
  assert_contains "$output" '"candidates": []' "scan --path: narrows the scope to the named path"
  run sm "$REPOFX/src" scan --path order.js
  assert_contains "$output" '"path": "src/order.js"' "scan --path from a subdirectory: the scope is relative to where it runs"
  assert_not_contains "$output" "src/mode.py" "scan --path from a subdirectory: only the named file ranks"
  run sm "$REPOFX" scan --limit 1
  assert_not_contains "$output" "src/mode.py" "scan --limit: caps the candidate list"

  PLAIN="$(fixture_dir)"
  fixture_copy "find-implicit-state-machines/repo/." "$PLAIN"
  mkdir -p "$PLAIN/.tools"
  cp "$PLAIN/src/order.js" "$PLAIN/.tools/machine.js"
  run sm "$PLAIN" scan
  assert_exit 0 "scan outside git: exits 0"
  assert_contains "$output" '"path": "src/order.js"' "scan outside git: walks the tree"
  assert_not_contains "$output" "vendor/" "scan outside git: still skips vendor directories"
  assert_contains "$output" '"head": null' "scan outside git: no head to name"
  mkdir -p "$PLAIN/dist"
  cp "$PLAIN/src/order.js" "$PLAIN/dist/order.js"
  run sm "$PLAIN" scan
  assert_not_contains "$output" "dist/" "scan outside git: build output is skipped by name"
  assert_contains "$output" '"path": ".tools/machine.js"' \
    "scan outside git: a dot-directory ranks the same as inside git — one exclusion rule for both modes"
fi; end_case

if begin_case "check"; then
  cp "$REPO/tests/fixtures/find-implicit-state-machines/findings.json" "$REPOFX/findings.json"
  BEFORE="$(cat "$REPOFX/findings.json")"
  run sm "$REPOFX" check findings.json
  assert_exit 0 "check: a valid findings file exits 0"
  assert_contains "$output" "Order lifecycle" "check: the summary names each machine"
  assert_eq "$BEFORE" "$(cat "$REPOFX/findings.json")" "check: read-only without --write"

  run sm "$REPOFX" check findings.json --write
  assert_exit 0 "check --write: exits 0"
  FLAGS="$(cd "$REPOFX" && "$TEST_PYTHON" -c '
import json
for f in json.load(open("findings.json"))["findings"]:
    print(f["name"], "|", ",".join(f["flags"]), "|", f["coverage"])
')"
  assert_contains "$FLAGS" "Order lifecycle | UNTESTED,HIDDEN_TRANSITIONS,WIDE_LOW_COVERAGE | 0.25" \
    "check --write: UNTESTED, hidden transitions and >3 states under 50% coverage are flagged"
  assert_contains "$FLAGS" "Player mode | LOW_CONFIDENCE | 1.0" \
    "check --write: a LOW-confidence machine says so; a tested two-state machine carries no gap flag"

  # bad <label> <reason> <python edit> — one broken copy, refused with exit 1.
  bad() {
    (cd "$REPOFX" && "$TEST_PYTHON" -c "
import json
d = json.load(open('findings.json'))
f = d['findings'][0]
$3
json.dump(d, open('bad.json', 'w'))
")
    assert_refused 1 "$2" "check: refuses $1" -- sm "$REPOFX" check bad.json
  }
  bad "a transition to an undeclared state" "'shipping' is not a declared state" \
    "f['transitions'][1]['to'] = 'shipping'"
  bad "a hidden transition from an undeclared state" "'draft' is not a declared state" \
    "f['hidden'][0]['from'] = 'draft'"
  bad "an entry outside the states" "entry 'new' is not a declared state" "f['entry'] = 'new'"
  bad "a file that does not exist" "src/missing.js does not exist" "f['files'].append('src/missing.js:3')"
  bad "a confidence outside HIGH/MEDIUM/LOW" "confidence must be one of" "f['confidence'] = 'MAYBE'"
  bad "a missing field" "missing field 'transitions'" "del f['transitions']"
  bad "TESTED with no test file" "TESTED needs at least one test" "f['tested'] = 'TESTED'; f['tests'] = []"
  bad "a duplicate machine name" "duplicate name" "d['findings'][1]['name'] = 'Order lifecycle'"
  bad "a cited line past the end of its file" "src/order.js:900 is past the end" \
    "f['files'].append('src/order.js:900')"
  bad "a stale line inside a transition's via" "src/order.js:400 is past the end" \
    "f['transitions'][0]['via'] = 'pay() at src/order.js:400'"
  bad "a stale line in a test citation" "tests/order.test.js:900 is past the end" \
    "f['tests'].append('tests/order.test.js:900')"
  bad "a test file that does not exist" "tests/missing.test.js does not exist" \
    "f['tests'].append('tests/missing.test.js')"
  bad "a stale line inside a hidden transition's via" "src/order.js:300 is past the end" \
    "f['hidden'][0]['via'] = 'ship() at src/order.js:300'"
  bad "fewer than two states" "at least two distinct states" "f['states'] = ['pending']"
  bad "duplicate states" "at least two distinct states" "f['states'] = ['pending', 'paid', 'paid', 'shipped', 'cancelled']"
  bad "a hidden transition without why" "needs from, to, via, tested, why" "del f['hidden'][0]['why']"
  bad "an exit that is not a list" "exit must be a list" "f['exit'] = 'shipped'"
  bad "an exit outside the states" "exit: 'gone' is not a declared state" "f['exit'] = ['gone']"
  bad "a non-boolean tested on an edge" "tested must be true or false" "f['transitions'][0]['tested'] = 'yes'"
  bad "a tested value outside TESTED/UNTESTED" "tested must be one of" "f['tested'] = 'PARTIAL'"
  bad "a top level that is not an object with findings" "must be an object with a \`findings\` list" "d = d['findings']"
  assert_refused 2 "cannot read" "check: a missing findings file is a usage error" -- sm "$REPOFX" check nowhere.json
  cp "$REPOFX/bad.json" "$REPOFX/bad.before"
  run sm "$REPOFX" check bad.json --write
  assert_exit 1 "check --write: an invalid file is refused"
  assert_files_identical "$REPOFX/bad.before" "$REPOFX/bad.json" "check --write: an invalid file is left untouched"
  printf 'all:\n\ttrue\n' > "$REPOFX/Makefile"
  bad "a stale line in an extensionless file cited by via" "Makefile:900 is past the end" \
    "f['transitions'][0]['via'] = 'rule at Makefile:900'"
  bad "a via with no path:line citation" "needs a path:line citation" \
    "f['transitions'][0]['via'] = 'pay() in order.js'"
  printf 'not json' > "$REPOFX/broken.json"
  assert_refused 2 "not valid JSON" "check: unreadable JSON is a usage error" -- sm "$REPOFX" check broken.json

  # The default path, resolved from the repository root wherever check runs.
  mkdir -p "$REPOFX/.jplugin/state-machines"
  cp "$REPOFX/findings.json" "$REPOFX/.jplugin/state-machines/findings.json"
  run sm "$REPOFX/src" check
  assert_exit 0 "check from a subdirectory: the default findings file and its cited paths resolve from the root"

  # Stored coverage and flags that no longer match the transitions are refused.
  (cd "$REPOFX" && "$TEST_PYTHON" -c "
import json
d = json.load(open('findings.json'))
d['findings'][0]['transitions'][1]['tested'] = True
json.dump(d, open('findings.json', 'w'))
")
  assert_refused 1 "stale — re-run with --write" "check: stored coverage/flags that contradict the transitions are refused" \
    -- sm "$REPOFX" check findings.json
  sm "$REPOFX" check findings.json --write >/dev/null 2>&1
  (cd "$REPOFX" && "$TEST_PYTHON" -c "
import json
d = json.load(open('findings.json'))
d['findings'][0]['flags'] = []
json.dump(d, open('findings.json', 'w'))
")
  assert_refused 1 "stale — re-run with --write" "check: stale flags alone, with a correct coverage, are refused" \
    -- sm "$REPOFX" check findings.json

  # Should-fix 2: the Phase 3 rule is "more than 3 states" and "under 50%".
  (cd "$REPOFX" && "$TEST_PYTHON" -c "
import json
def edge(a, b, t): return {'from': a, 'to': b, 'via': 'f() at src/order.js:4', 'tested': t}
def machine(name, states, tested):
    return {'name': name, 'files': ['src/order.js'], 'states': states, 'entry': states[0], 'exit': [],
            'transitions': [edge(states[i], states[i + 1], t) for i, t in enumerate(tested)],
            'tested': 'UNTESTED', 'tests': [], 'confidence': 'MEDIUM', 'hidden': []}
json.dump({'findings': [machine('Three at zero', ['a', 'b', 'c'], [False, False]),
                        machine('Four at half', ['a', 'b', 'c', 'd'], [True, False]),
                        machine('Four under half', ['a', 'b', 'c', 'd'], [True, False, False])]},
          open('edge.json', 'w'))
")
  run sm "$REPOFX" check edge.json
  assert_eq "MEDIUM Three at zero — 3 states, 2 transitions, 0 hidden, coverage 0%, flags: UNTESTED" "$(printf '%s\n' "$output" | grep -x "MEDIUM Three at zero — .*")" \
    "check: exactly 3 states is not wide, however low the coverage"
  assert_eq "MEDIUM Four at half — 4 states, 2 transitions, 0 hidden, coverage 50%, flags: UNTESTED" "$(printf '%s\n' "$output" | grep -x "MEDIUM Four at half — .*")" \
    "check: exactly 50% coverage is not low"
  assert_eq "MEDIUM Four under half — 4 states, 3 transitions, 0 hidden, coverage 33%, flags: UNTESTED, WIDE_LOW_COVERAGE" "$(printf '%s\n' "$output" | grep -x "MEDIUM Four under half — .*")" \
    "check: more than 3 states under 50% is flagged"
fi; end_case

if begin_case "tla"; then
  cp "$REPO/tests/fixtures/find-implicit-state-machines/findings.json" "$REPOFX/findings.json"
  OUT="$(fixture_dir)"
  run sm "$REPOFX" tla findings.json --name "Order lifecycle" --out "$OUT"
  assert_exit 0 "tla: exits 0"
  assert_file_exists "$OUT/OrderLifecycle.tla" "tla: writes the module named after the machine"
  assert_file_exists "$OUT/OrderLifecycle.cfg" "tla: writes its TLC config"
  assert_file_contains "$OUT/OrderLifecycle.tla" "---- MODULE OrderLifecycle ----" "tla: module header matches the file name"
  assert_file_contains "$OUT/OrderLifecycle.tla" 'Init == state = "pending" /\ via = "start"' "tla: Init is the entry state"
  assert_file_contains "$OUT/OrderLifecycle.tla" 'state = "paid" /\ state'"'"' = "shipped"' "tla: one action per intended transition"
  assert_file_contains "$OUT/OrderLifecycle.tla" 'HiddenVias == {"hidden 1: ship() at src/order.js:11"}' \
    "tla: hidden transitions are named so the invariant can catch them"
  assert_file_contains "$OUT/OrderLifecycle.tla" 'Done == state \in {"shipped", "cancelled"} /\ UNCHANGED vars' \
    "tla: exit states get a stutter step so they are not deadlocks"
  assert_file_contains "$OUT/OrderLifecycle.cfg" "INVARIANT IntendedOnly" "tla: the config checks that only intended steps run"
  assert_refused 1 "no finding named" "tla: an unknown machine name is refused" \
    -- sm "$REPOFX" tla findings.json --name "Nope" --out "$OUT"
  DEFINED="$(cd "$OUT" && "$TEST_PYTHON" -c '
import re
tla = open("OrderLifecycle.tla").read()
names = re.findall(r"^(?:INIT|NEXT|INVARIANT) (\w+)$", open("OrderLifecycle.cfg").read(), re.M)
print(len(names), all(re.search(r"^" + n + r" ==", tla, re.M) for n in names))
')"
  assert_eq "4 True" "$DEFINED" "tla: every operator the config names is defined in the module"

  mkdir -p "$REPOFX/.jplugin/state-machines"
  cp "$REPO/tests/fixtures/find-implicit-state-machines/findings.json" "$REPOFX/.jplugin/state-machines/findings.json"
  run sm "$REPOFX/src" tla --name "Player mode"
  assert_exit 0 "tla from a subdirectory with no paths: exits 0"
  assert_file_exists "$REPOFX/.jplugin/state-machines/tla/PlayerMode.tla" \
    "tla: the default findings file and output directory resolve from the repository root"
  PM="$REPOFX/.jplugin/state-machines/tla/PlayerMode.tla"
  assert_file_contains "$PM" "HiddenVias == {}" "tla: a machine with no hidden transitions has an empty HiddenVias"
  assert_file_contains "$PM" "Next == T1" "tla: a machine with no exit states has no Done step"
  (cd "$REPOFX" && "$TEST_PYTHON" - <<'PY'
import json
d = json.load(open("findings.json"))
d["findings"][1]["transitions"][0]["via"] = 'play("now\\fast") at src/mode.py:5'
d["findings"][1]["name"] = "2nd player"
json.dump(d, open("quoted.json", "w"))
PY
)
  run sm "$REPOFX" tla quoted.json --name "2nd player" --out "$OUT"
  assert_file_contains "$OUT/M2ndPlayer.tla" "---- MODULE M2ndPlayer ----" "tla: a name starting with a digit gets a letter prefix"
  assert_file_contains "$OUT/M2ndPlayer.tla" 'via'"'"' = "play(\"now\\fast\") at src/mode.py:5"' \
    "tla: quotes and backslashes in via are escaped as TLA+ strings"
  EMPTY="$(fixture_dir)"
  (cd "$REPOFX" && "$TEST_PYTHON" -c "
import json
d = json.load(open('findings.json'))
d['findings'][0]['entry'] = 'new'
json.dump(d, open('bad-tla.json', 'w'))
")
  assert_refused 1 "entry 'new' is not a declared state" "tla: an invalid findings file is refused" \
    -- sm "$REPOFX" tla bad-tla.json --name "Order lifecycle" --out "$EMPTY"
  assert_eq "" "$(ls "$EMPTY")" "tla: nothing is written for an invalid findings file"
fi; end_case

if begin_case "skill-doc"; then
  MD="$SKILL/SKILL.md"
  assert_file_contains "$MD" ".jplugin/state-machines/findings.json" "SKILL.md: names the findings path"
  assert_file_matches "$MD" "[Nn]ever (modify|edit|change) application code" "SKILL.md: the scan is read-only"
  assert_file_contains "$MD" "LOW" "SKILL.md: says how to report an ambiguous pattern"
  assert_file_contains "$MD" "/statechart" "SKILL.md: Phase 4 bridges to /statechart"
  assert_file_contains "$MD" "/create-formal-verification-skill" "SKILL.md: Phase 4 names the formal-verification skill"
  SIGFILE="$(fixture_dir)/signals.json"
  run sm "$REPOFX" signals
  assert_exit 0 "signals: prints the signal table and exclusion lists"
  printf '%s' "$output" > "$SIGFILE"
  MISSING="$("$TEST_PYTHON" - "$SIGFILE" "$SKILL/references/signals.md" <<'PY'
import json, re, sys
table = json.load(open(sys.argv[1], encoding="utf-8"))
doc = open(sys.argv[2], encoding="utf-8").read()
rows = {m[0]: int(m[1]) for m in re.findall(r"^\| `([a-z-]+)` \| (\d+) \|", doc, re.M)}
missing = [n for n, w in table["weights"].items() if rows.get(n) != w]
missing += [n for n in rows if n not in table["weights"]]
missing += [v for group in table["excluded"].values() for v in group
            if "`" + v + "`" not in doc and "`" + v + "/`" not in doc]
print("parsed", len(table["weights"]), "weights;", " ".join(sorted(missing)))
PY
)"
  assert_eq "parsed 11 weights; " "$MISSING" "signals.md: every signal weight and every exclusion the script applies is documented — the by-hand fallback cannot drift"
fi; end_case

finish
