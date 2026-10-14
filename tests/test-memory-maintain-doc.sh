# tests/test-memory-maintain-doc.sh — P4 Reflector-lite split,
# retargeted at the typed learning store (M3).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

A=".agents/skills/memory-maintain/SKILL.md"
history_pattern=$(sed -n "s/.*grep -Ec '\([^']*\)' tasks\/history\.md.*/\1/p" .agents/hooks/session-start.sh)

for f in "$A"; do
  assert_file_contains "$f" "Light pass — every session" "P4: $f documents per-session light pass"
  assert_file_contains "$f" "Heavy pass — every 5 sessions" "P4: $f keeps heavy pass gated at 5"
  assert_file_contains "$f" "silent no-op" "P4: $f no-ops when the store is absent"
  assert_file_contains "$f" "tasks/solutions" "M3: $f sweeps the typed store"
  assert_file_contains "$f" "needs_review" "M3: $f resolves needs_review documents"
  assert_file_contains "$f" "Contradicted" "M3: $f handles contradicted documents"
  # The duplicated command is executable contract, not a snapshot of its prose.
  assert_file_contains "$f" "grep -Ec '$history_pattern' tasks/history.md" \
    "$f: history heading pattern matches the real hook"
done

# --- Merge test: a pair scores on /learn Step 4's per-track dimensions -------
# Phase 2 merged a pair only on "same problem, same root cause", and no
# knowledge-track document carries a root cause, so a duplicate decision or
# pattern could never merge. Both passes now score a pair on /learn Step 4,
# which owns the per-track sets (#168). The heading, the High band and the
# number of dimensions per track are read from Step 4 itself, so renaming the
# heading or changing the band or the scale fails here instead of leaving a
# dead pointer or a stale ">70%" translation.
learn=$(tr -d '\r' < .agents/skills/learn/SKILL.md)
step4=$(printf '%s\n' "$learn" | sed -n 's/^### \(4\. Score Overlap.*\)$/\1/p')
high_band=$(printf '%s\n' "$learn" | sed -n 's/^| High | \([^|]*[^ |]\) *|.*/\1/p')
dimensions() { printf '%s\n' "$learn" | sed -n "s/^| $1 | \(.*\) |\$/\1/p" | awk -F',' '{print NF}'; }
assert_contains "$step4" "Score Overlap Before Writing" \
  "merge test: /learn Step 4 carries the heading the reference names"
assert_prose_contains "$A" "Step 4 (§ $step4)" \
  "merge test: $A scores a pair on /learn Step 4"
assert_prose_contains "$A" "High is $high_band of the five dimensions, the >70% threshold" \
  "merge test: $A restates Step 4's High band ($high_band) as the >70% threshold"
assert_eq "5 5" "$(dimensions bug) $(dimensions knowledge)" \
  "merge test: Step 4 scores each track on five dimensions, the scale $A's >70% translation assumes"
assert_prose_contains "$A" "a pair on different tracks never merges" \
  "merge test: $A never merges across tracks"
assert_prose_contains "$A" "passes the Phase 2 merge test" \
  "merge test: the light pass applies the Phase 2 merge test"
# Step 4's track cap is the only merge boundary, as it is when /learn writes:
# the merge test adds no category condition of its own.
phase2=$(awk '/^## Phase 2/{p=1} /^## Phase 3/{p=0} p' "$A" | tr -s '[:space:]' ' ')
assert_contains "$phase2" "apply the **merge test**: score the pair the way \`/learn\` Step 4" \
  "merge test: Phase 2 defines the name the light pass cites"
assert_contains "$phase2" "merge only on a High score" \
  "merge test: Phase 2 merges only on a High score"
assert_not_contains "$phase2" "same category" \
  "merge test: Phase 2 adds no category boundary to Step 4's track cap"
assert_file_not_matches "$A" 'same root cause|semantic overlap' \
  "merge test: $A carries no bug-track-only overlap wording"

finish
