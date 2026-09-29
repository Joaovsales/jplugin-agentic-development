#!/bin/bash
# tests/test-make-it-simpler.sh — /make-it-simpler (specs/make-it-simpler.md).
#
# signals.py rank runs inside a temporary `git init` repository built from
# tests/fixtures/make-it-simpler/, so the fixtures are tracked there and never
# rank here (D18). Each fixture file seeds exactly one signal; the expected
# order below is the score formula applied by hand:
# score = lines_saved × max(callers, 1) × (5 if always_loaded else 1).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SIGNALS="$REPO/.agents/skills/make-it-simpler/scripts/signals.py"
BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
[ -n "$BOX" ] && [ -d "$BOX" ] || { printf 'mktemp -d failed\n' >&2; exit 1; }

# fixture_repo <dir> <fixture> — a committed repository holding one fixture.
fixture_repo() {
  mkdir -p "$1"
  [ -n "$2" ] && cp -R "$REPO/tests/fixtures/make-it-simpler/$2/." "$1/"
  git -C "$1" init -q
  git -C "$1" config core.autocrlf false
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
}
rank() { (cd "$1" && shift && "$TEST_PYTHON" "$SIGNALS" rank "$@"); }

SEVEN="$BOX/seven"
fixture_repo "$SEVEN" seven

# --- AC 1: seven signals, verbatim evidence, score formula, sort order --------
OUT="$(rank "$SEVEN")"; STATUS=$?
assert_eq "0" "$STATUS" "rank: exits 0 over the seven-signal fixture"
printf '%s' "$OUT" > "$BOX/seven.json"
CHECK="$(cd "$SEVEN" && "$TEST_PYTHON" - "$BOX/seven.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
SEVEN = {"duplicate-rule", "citation-drift", "over-budget", "doc-script-contradiction",
         "enforced-prose", "orphan-or-overlap", "code-red-flag"}
cands = data["candidates"]
print("signals", sorted(c["signal"] for c in cands) == sorted(SEVEN))
for c in cands:
    lines = open(c["path"], encoding="utf-8").read().splitlines()
    w = 5 if c["always_loaded"] else 1
    ok = (c["evidence"] == lines[c["line"] - 1]
          and c["score"] == c["lines_saved"] * max(c["callers"], 1) * w
          and c["key"] == f'{c["signal"]} in {c["path"]}')
    print("row", c["key"], ok)
print("sorted", cands == sorted(cands, key=lambda c: (-c["score"], c["key"])))
print("head", bool(data["head"]))
for c in cands:
    print("order", c["key"], c["line"], c["score"])
PY
)"
assert_contains "$CHECK" "signals True" "AC 1: one candidate for each of the seven signals"
assert_not_contains "$CHECK" " False" "AC 1: every row quotes its line verbatim and applies the score formula"
assert_contains "$CHECK" "sorted True" "AC 1: sorted by score desc, then key asc"
assert_contains "$CHECK" "head True" "AC 1: the output names the head commit"
assert_eq "order over-budget in AGENTS.md 201 25
order code-red-flag in tools/big.py 501 10
order orphan-or-overlap in skills/demo/references/unused.md 1 3
order citation-drift in docs/c.md 3 2
order doc-script-contradiction in docs/d.md 3 1
order duplicate-rule in docs/a.md 3 1
order enforced-prose in docs/e.md 3 1" "$(printf '%s\n' "$CHECK" | grep '^order ' | tr -d '\r')" \
  "AC 1: the fixture ranks in the hand-computed order (W = 5 for always-loaded AGENTS.md)"

# --- AC 2: deterministic, read-only, empty tree is success --------------------
BEFORE="$(git -C "$SEVEN" status --porcelain)"
AGAIN="$(rank "$SEVEN")"
assert_eq "$OUT" "$AGAIN" "AC 2: two runs over one tree print byte-identical output"
assert_eq "$BEFORE" "$(git -C "$SEVEN" status --porcelain)" "AC 2: rank writes nothing (git status unchanged)"
assert_eq "" "$(git -C "$SEVEN" status --porcelain --ignored)" "AC 2: no ignored droppings either (no __pycache__)"

QUIET="$BOX/quiet"
mkdir -p "$QUIET"; printf '# Quiet\n\nNothing to see.\n' > "$QUIET/README.md"
fixture_repo "$QUIET" ""
OUT="$(rank "$QUIET")"; STATUS=$?
assert_eq "0" "$STATUS" "AC 2: a tree with no signal exits 0"
assert_contains "$OUT" '"candidates": []' "AC 2: a tree with no signal prints candidates []"

finish
