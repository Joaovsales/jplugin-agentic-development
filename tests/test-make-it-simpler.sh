#!/bin/bash
# tests/test-make-it-simpler.sh — /make-it-simpler (specs/make-it-simpler.md).
#
# signals.py rank runs inside a temporary git repository built from
# tests/fixtures/make-it-simpler/, so the fixtures are tracked there and never
# rank here (D18). Each fixture file seeds exactly one signal; the expected
# order below is the score formula applied by hand (a code-red-flag cue
# saves 1 line: splitting a script moves lines, it saves none):
# score = lines_saved × max(callers, 1) × (5 if always_loaded else 1).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SIGNALS="$(under_test .agents/skills/make-it-simpler/scripts)/signals.py"
BOX="$(fixture_dir)"

# commit_fixture <repo> — everything the fixture holds, as one commit.
commit_fixture() {
  git -C "$1" add -A
  git -C "$1" commit -q --allow-empty -m init
}
rank() { (cd "$1" && shift && "$TEST_PYTHON" "$SIGNALS" rank "$@"); }

SEVEN="$(fixture_repo)"
fixture_copy "make-it-simpler/seven/." "$SEVEN"
commit_fixture "$SEVEN"

# --- AC 1: seven signals, verbatim evidence, score formula, sort order --------
run rank "$SEVEN"
assert_exit 0 "rank: exits 0 over the seven-signal fixture"
OUT="$output"
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
order orphan-or-overlap in skills/demo/references/unused.md 1 3
order citation-drift in docs/c.md 3 2
order code-red-flag in tools/big.py 501 1
order doc-script-contradiction in docs/d.md 3 1
order duplicate-rule in docs/a.md 3 1
order enforced-prose in docs/e.md 3 1" "$(printf '%s\n' "$CHECK" | grep '^order ' | tr -d '\r')" \
  "AC 1: the fixture ranks in the hand-computed order (W = 5 for always-loaded AGENTS.md)"

# A SKILL.md over budget loads only when invoked: moving its body to references/
# moves lines, it saves none, so it is a cue worth 1 line. AGENTS.md above is
# always loaded and keeps lines - budget.
BUDGET="$(fixture_repo)"
mkdir -p "$BUDGET/skills/big"
{ printf -- '---\nname: big\n---\n'; seq -f 'line %g' 1 160; } > "$BUDGET/skills/big/SKILL.md"
commit_fixture "$BUDGET"
BUDGET_OUT="$(rank "$BUDGET")"
assert_contains "$BUDGET_OUT" '"lines_saved": 1,' "AC 1: an over-budget SKILL.md that is not always loaded is a cue saving 1 line"

# --- AC 2: deterministic, read-only, empty tree is success --------------------
BEFORE="$(git -C "$SEVEN" status --porcelain)"
AGAIN="$(rank "$SEVEN")"
assert_eq "$OUT" "$AGAIN" "AC 2: two runs over one tree print byte-identical output"
assert_eq "$BEFORE" "$(git -C "$SEVEN" status --porcelain)" "AC 2: rank writes nothing (git status unchanged)"
assert_eq "" "$(git -C "$SEVEN" status --porcelain --ignored)" "AC 2: no ignored droppings either (no __pycache__)"

QUIET="$(fixture_repo)"
printf '# Quiet\n\nNothing to see.\n' > "$QUIET/README.md"
commit_fixture "$QUIET"
run rank "$QUIET"
assert_exit 0 "AC 2: a tree with no signal exits 0"
assert_contains "$output" '"candidates": []' "AC 2: a tree with no signal prints candidates []"

# --- AC 3: --path narrows or refuses; tests/fixtures/ never ranks -------------
assert_refused 2 "matches no tracked file" "AC 3: --path matching no tracked file exits 2" -- rank "$SEVEN" --path nowhere/
assert_contains "$output" "nowhere/" "AC 3: the refusal names the path"
assert_refused 2 "matches no tracked file" "AC 3: --path under tests/fixtures/ matches nothing rankable and exits 2" -- rank "$SEVEN" --path tests/fixtures
OUT="$(rank "$SEVEN" --path docs)"
assert_eq "citation-drift in docs/c.md
doc-script-contradiction in docs/d.md
duplicate-rule in docs/a.md
enforced-prose in docs/e.md" "$(printf '%s\n' "$OUT" | sed -n 's/.*"key": "\(.*\)".*/\1/p')" \
  "AC 3: --path docs keeps only the candidates under docs/"
OUT="$(rank "$SEVEN" --limit 50)"
assert_not_contains "$OUT" '"path": "tests/fixtures/' "AC 3: no candidate is ever under tests/fixtures/"
assert_not_contains "$OUT" '"path": "tasks/' "AC 3: no candidate is ever under tasks/ (append-only logs and registers)"
# tasks/history.md and specs/design.md repeat docs/a.md's rule and tasks/ also
# names tools/big.py: were tasks/ read or specs/ counted as a home, AC 1's order
# would change (duplicate-rule would score 3, big.py's callers would rise).
# The fixture repo's own tests/fixtures/dup/ copies docs/a.md's rule and holds
# an uncited references/ file: were it read, AC 1's hand-computed order above
# would change (duplicate-rule would score 2, lost.md would rank).
assert_refused 2 "matches no tracked file" "AC 3: in this repository the fixtures are tracked but never rank" -- rank "$REPO" --path tests/fixtures/make-it-simpler
assert_eq "$(rank "$SEVEN" --limit 50)" "$(rank "$SEVEN/docs" --limit 50)" \
  "AC 3: run from a subdirectory, rank prints what it prints from the root (paths are root-relative)"
mkdir -p "$BOX/not-a-repo"
assert_refused 2 "signals: git rev-parse failed" "rank outside a git repository is a usage error — exit 2, never an empty success" -- rank "$BOX/not-a-repo"
assert_contains "$output" "signals: git rev-parse failed" "the refusal names the failing git command"

# --- AC 4: what /tidy owns never surfaces --------------------------------------
OUT="$(rank "$SEVEN" --limit 50)"
assert_not_contains "$OUT" "docs/f.md" \
  "AC 4: an unresolved backticked path, a retired-skill reference and a missing script yield no candidate"

# --- AC 5: lens.md defines what signals.py computes ---------------------------
SKILL_DIR="$REPO/.agents/skills/make-it-simpler"
LENS="$SKILL_DIR/references/lens.md"
SIGNAL_NAMES="$("$TEST_PYTHON" - "$SIGNALS" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "DETECTORS":
        print("\n".join(ast.literal_eval(key) for key in node.value.keys))
PY
)"
assert_eq "7" "$(printf '%s\n' "$SIGNAL_NAMES" | grep -c .)" "AC 5: signals.py declares seven signals"
for signal in $SIGNAL_NAMES; do
  signal="${signal%$'\r'}"
  assert_file_contains "$LENS" "| \`$signal\` |" "AC 5: lens.md defines $signal"
done
assert_file_contains "$LENS" "\`W\` — the always-loaded weight, **5**" "AC 5: lens.md names W and its value"
assert_file_matches "$SIGNALS" "^W = 5[[:space:]]*$" "AC 5: signals.py's W matches lens.md"
# lens.md restates the thresholds; each value is pinned to its one home.
for pin in '^W = 5[[:space:]]*$|`W` — the always-loaded weight, **5**' \
           '^CODE_BUDGET = 500[[:space:]]*$|over 500 lines (`CODE_BUDGET`)' \
           '^LINE_BUDGETS = \{"SKILL.md": 150, "AGENTS.md": 200\}|a `SKILL.md` over 150 lines or an `AGENTS.md` over 200' \
           '^DUPLICATE_MIN_CHARS = 60[[:space:]]*$|one Markdown line of at least 60 characters' \
           '^NEEDLE_MIN_CHARS = 20[[:space:]]*$|a quoted needle (20+ characters)'; do
  assert_file_matches "$SIGNALS" "${pin%%|*}" "AC 5: signals.py holds ${pin%%|*}"
  assert_file_contains "$LENS" "${pin#*|}" "AC 5: lens.md states the same value — ${pin#*|}"
done
assert_file_contains "$LENS" "**\`tests/fixtures/\`** — never read and never ranked" "AC 5: lens.md states the fixtures exclusion"
assert_file_contains "$LENS" "**\`tasks/\`** — never read and never ranked" "AC 5: lens.md states the tasks/ exclusion"
assert_file_matches "$SIGNALS" '^EXCLUDED_PREFIXES = \("tests/fixtures/", "tasks/"\)' "AC 5: signals.py excludes the same prefixes"
assert_file_matches "$SIGNALS" '^DESIGN_RECORDS = \("specs/",\)' "AC 5: signals.py holds DESIGN_RECORDS = specs/"
assert_file_contains "$LENS" "**\`specs/\` as a duplicate home**" "AC 5: lens.md states specs/ is never a duplicate home"
assert_prose_contains "$LENS" "its nine checks: \`suite\`, \`inventory\`, \`retired\`,
  \`installed\`, \`refs\`, \`worktrees\`, \`strays\`, \`graph\`, \`registers\`" \
  "AC 5: lens.md names the nine /tidy checks it excludes"

# --- AC 6: safe-moves.md states the five practices ------------------------------
MOVES="$SKILL_DIR/references/safe-moves.md"
assert_file_contains "$MOVES" "1. **Headings are names only.**" "AC 6: practice 1 — headings are names only"
assert_file_contains "$MOVES" "2. **Callers cite by § name.**" "AC 6: practice 2 — callers cite by § name"
assert_file_contains "$MOVES" "3. **A moved assertion is repointed, never deleted without a replacement.**" \
  "AC 6: practice 3 — a moved assertion is repointed"
assert_file_contains "$MOVES" "4. **One home per rule.**" "AC 6: practice 4 — one home per rule"
assert_file_contains "$MOVES" "5. **No script behavior change unless declared minor.**" \
  "AC 6: practice 5 — no script behavior change unless declared minor"

# --- AC 7: frontmatter, budget, /writing-skills section order, README row ------
SKILL="$SKILL_DIR/SKILL.md"
assert_eq "name: make-it-simpler" "$(sed -n '2p' "$SKILL" | tr -d '\r')" "AC 7: frontmatter name is make-it-simpler"
assert_true "AC 7: SKILL.md is at most 150 lines" -- test "$(grep -c '' "$SKILL")" -le 150
assert_eq "## Overview
## The Process
## Integration
## Key Principles" "$(tr -d '\r' < "$SKILL" | awk '/^```/ { f = !f; next } !f' | grep '^## ')" \
  "AC 7: SKILL.md follows /writing-skills' section order"
assert_file_contains "$REPO/README.md" "| \`/make-it-simpler\` |" "AC 7: README.md's skills table lists it"

# --- AC 8: the significance bar is cited, never restated (D5) -------------------
assert_file_contains "$SKILL" "the bar in \`/system-design-planning\` § *When to Use / When Not*" \
  "AC 8: SKILL.md cites /system-design-planning § When to Use / When Not"
for restated in "re-routes a call between two components" "adds a persisted entity" "changes an external contract"; do
  assert_file_not_matches "$SKILL" "$restated" "AC 8: SKILL.md does not restate the bar ($restated)"
done

# --- AC 9: grammar, top-3 fields, none today, four seeds, safe-moves seeding ----
for row in '| `#N` or a registry id |' '| a tracked path prefix |' '| any other text |' '| nothing |'; do
  assert_file_contains "$SKILL" "$row" "AC 9: the argument grammar has the row $row"
done
assert_file_contains "$SKILL" "claim <ref> --routine simplify --apply --approve" \
  "AC 9: an interactive pick is claimed with --routine (the CLI refuses claim without it)"
for field in '`file:line`' 'lines saved' 'callers touched' 'minor/significant'; do
  assert_prose_contains "$SKILL" "$field" "AC 9: each of the top 3 carries $field"
done
assert_file_contains "$SKILL" "**none today writes nothing**" "AC 9: none today writes nothing"
for seed in "1. Scope — what is in and what is out." "2. What stays byte-identical" \
            "3. The minor behavior changes expected" "4. The slice cap for this change."; do
  assert_file_contains "$SKILL" "$seed" "AC 9: grilling seed — $seed"
done
assert_prose_contains "$SKILL" "seeds the five \`safe-moves.md\` practices" \
  "AC 9: the five safe-moves practices are seeded as § Decisions rows"

# --- AC 10: the unattended sequence, its three ends, the scope stop -------------
assert_prose_contains "$SKILL" "Rank, deep review, classify and size" "AC 10: unattended a — rank, classify, size"
assert_file_contains "$SKILL" ".agents/skills/slice/references/sizing.md" "AC 10: sizing cites slice/references/sizing.md"
assert_prose_contains "$SKILL" "\`task-registry show <derived-id>\`" \
  "AC 10: show before upsert, skipping done and cancelled"
assert_file_contains "$SKILL" "--derive-id simplify --source <path> --fold-title" "AC 10: file with a derived simplify id"
assert_prose_contains "$SKILL" "Spine 1–3" "AC 10: spine steps 1–3"
assert_prose_contains "$SKILL" "index rows step b wrote" \
  "AC 10: index rows are the branch's first commit"
assert_prose_contains "$SKILL" "first commit" "AC 10: the index rows are named the first commit"
assert_file_contains "$SKILL" "- **Ready PR**" "AC 10: end 1 — ready PR"
assert_prose_contains "$SKILL" "routine/simplify/<YYYYMMDD>-record" \
  "AC 10: end 2 — docs-only record PR"
assert_prose_contains "$SKILL" "**Silent exit 0**" \
  "AC 10: end 3 — silent exit 0"
assert_prose_contains "$SKILL" "leave the claim in place" \
  "AC 10: the scope stop — non-zero, no PR, claim left, one line with the remedy"

finish
