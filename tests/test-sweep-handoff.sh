#!/bin/bash
# tests/test-sweep-handoff.sh — the issue body a sweep files is the body /debug reads.
#
# specs/sweep-routines.md AC4. `/sweep` hands a finding to a later `/debug #N`
# through the tracker, so the record must carry a reproduction and a proposed
# fix that survive every provider round-trip — GitHub seeds them as body
# sections, the metadata block carries them back, the local provider stores them,
# and `show` renders them. The ID is derived from namespace + primary file +
# short title so a second sweep updates the same issue instead of filing twice.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
CLI="$SCRIPTS/task-registry.py"
PY=python3

TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

pyreg() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -; }
run() { "$PY" "$CLI" "$@"; }

# ---------------------------------------------------------------- 1. in-process
py_out="$(pyreg <<'PY' 2>&1
import sys, unittest
from registry.model import (Task, TaskModelError, render_metadata_block, parse_metadata_block,
                            task_from_metadata, _first_prose_line)
from registry.upsert import derive_id, _merge
from registry.providers import github, local
from registry import detail

REPRO = ("run `make check` on a clean tree, twice", "observed: exit 1 / expected: exit 0")
FIX = ("pin the fixture ordering in tests/lib.sh", "drop the sleep")

def sample(**over):
    fields = dict(
        id="sweep.src-export-py.ordering-drift", title="Ordering drift", kind="bug",
        summary="Export rows come back in a different order on the second run.",
        reproduction=REPRO, proposed_fix=FIX,
        acceptance_criteria=("second run is byte-identical",),
        evidence=("[MUST-FIX | confidence: 100 | autofix_class: manual | owner: agent] src/export.py:88",),
        spec_path="specs/export.md",
    )
    fields.update(over)
    return Task(**fields)

def ordered(body, *needles):
    positions = [body.find(n) for n in needles]
    return all(p >= 0 for p in positions) and positions == sorted(positions), positions

class ModelTests(unittest.TestCase):
    def test_fields_default_empty_and_become_tuples(self):
        bare = Task(id="a.b", title="t")
        self.assertEqual(bare.reproduction, ())
        self.assertEqual(bare.proposed_fix, ())
        listed = Task(id="a.b", title="t", reproduction=["one"], proposed_fix=["two"])
        self.assertEqual(listed.reproduction, ("one",))
        self.assertEqual(listed.proposed_fix, ("two",))

    def test_metadata_block_round_trips_lines_containing_commas(self):
        meta = parse_metadata_block(render_metadata_block(sample()))
        self.assertEqual(meta["reproduction"], REPRO)
        self.assertEqual(meta["proposed-fix"], FIX)

    def test_metadata_block_omits_the_keys_when_empty(self):
        block = render_metadata_block(sample(reproduction=(), proposed_fix=()))
        self.assertNotIn("reproduction:", block)
        self.assertNotIn("proposed-fix:", block)

    def test_task_from_metadata_carries_both(self):
        body = render_metadata_block(sample()) + "\n\nprose"
        task = task_from_metadata(title="t", body=body, external=None, status="open")
        self.assertEqual(task.reproduction, REPRO)
        self.assertEqual(task.proposed_fix, FIX)

    def test_evidence_round_trips_a_verbatim_line_containing_commas(self):
        # /sweep files `--evidence '<verbatim motivating line> (<file>:<line>)'`;
        # a comma-joined block split "rows = sorted(x, key=f)" into two witnesses.
        seen = ("rows = sorted(x, key=f) (src/export.py:88)", "discovered: sweep/janitor @ abc")
        block = render_metadata_block(sample(evidence=seen))
        self.assertIn("evidence: rows = sorted(x, key=f) (src/export.py:88)\n", block)
        self.assertEqual(parse_metadata_block(block)["evidence"], seen)

    def test_a_block_written_comma_joined_reads_as_one_entry(self):
        # Records written before evidence went line-per-entry: read whole,
        # normalized on the next write, never dropped.
        legacy = "<!-- task-registry:begin -->\ntask-id: a.b\nevidence: x, y\n<!-- task-registry:end -->"
        self.assertEqual(parse_metadata_block(legacy)["evidence"], ("x, y",))

    def test_a_newline_inside_an_entry_is_refused(self):
        # The block is line-oriented: `step\nkind: bug` would end the step early
        # and read its tail as a new key.
        for field in ("reproduction", "proposed_fix", "evidence"):
            with self.subTest(field=field):
                with self.assertRaises(TaskModelError) as caught:
                    sample(**{field: ("one\nkind: bug",)})
                self.assertIn(field.replace("_", "-"), str(caught.exception))

class MergeTests(unittest.TestCase):
    def test_a_rerun_replaces_the_steps_and_accretes_the_evidence(self):
        first = sample(evidence=("w1", "w2"))
        second = sample(reproduction=("new step",), evidence=("w2", "w3"))
        merged, verdict = _merge(first, second)
        self.assertEqual(verdict, "updated")
        self.assertEqual(merged.reproduction, ("new step",))
        self.assertEqual(merged.evidence, ("w1", "w2", "w3"))

class LocalRecordTests(unittest.TestCase):
    def test_an_indented_step_loses_its_marker_like_a_flush_one(self):
        # The failure this pins: an indented item kept its marker and gained a
        # second one on every write — `2. 2. observed`.
        text = "## Reproduction\n\n1. flush\n  2. indented\n"
        self.assertEqual(local._steps(text, "Reproduction"), ("flush", "indented"))
        self.assertEqual(local._criteria("## Acceptance Criteria\n\n  - [ ] a\n- [x] b\n"), ("a", "b"))

    def test_the_summary_is_never_a_numbered_step(self):
        self.assertEqual(_first_prose_line("## Reproduction\n\n1. run it\n\nThe summary.\n"), "The summary.")

class SeedBodyTests(unittest.TestCase):
    def test_github_renders_five_sections_in_order(self):
        body = github._seed_body(sample())
        ok, pos = ordered(body, "Export rows", "## Reproduction", "## Proposed fix",
                          "## Acceptance Criteria", "## Evidence", "Spec:")
        self.assertTrue(ok, (pos, body))
        self.assertIn("1. run `make check` on a clean tree, twice", body)
        self.assertIn("2. observed: exit 1 / expected: exit 0", body)
        self.assertIn("- pin the fixture ordering in tests/lib.sh", body)
        self.assertIn("- [ ] second run is byte-identical", body)
        self.assertIn("- [MUST-FIX", body)

    def test_github_omits_sections_it_has_nothing_for(self):
        body = github._seed_body(sample(reproduction=(), proposed_fix=(), evidence=()))
        for heading in ("## Reproduction", "## Proposed fix", "## Evidence"):
            self.assertNotIn(heading, body)
        self.assertIn("## Acceptance Criteria", body)

class DeriveIdTests(unittest.TestCase):
    def test_title_fold_is_opt_in_so_existing_ids_are_stable(self):
        self.assertEqual(derive_id("spec-reconciliation", "specs/feature-c.md"),
                         "spec-reconciliation.specs-feature-c-md")
        self.assertEqual(derive_id("sweep", "src/export.py", title="Ordering drift"),
                         "sweep.src-export-py.ordering-drift")
        self.assertEqual(derive_id("sweep", "src/export.py", title="  ordering DRIFT! "),
                         "sweep.src-export-py.ordering-drift")

class ShowTests(unittest.TestCase):
    def test_detail_renders_both(self):
        lines = detail._render_detail("sweep.x", None, sample(), detail.Report("show", "local"))
        text = "\n".join(lines)
        self.assertIn("reproduction:", text)
        self.assertIn("observed: exit 1 / expected: exit 0", text)
        self.assertIn("proposed fix:", text)
        self.assertIn("drop the sleep", text)

    def test_detail_renders_evidence_one_witness_per_line(self):
        task = sample(evidence=("sorted(x, key=f) (a.py:1)", "discovered: sweep @ abc"))
        text = "\n".join(detail._render_detail("sweep.x", None, task, detail.Report("show", "local")))
        self.assertIn("  evidence:\n    - sorted(x, key=f) (a.py:1)\n    - discovered: sweep @ abc", text)

runner = unittest.TextTestRunner(verbosity=0, stream=sys.stdout)
result = runner.run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
print(f"PYRESULT ran={result.testsRun} failed={len(result.failures) + len(result.errors)}")
PY
)"; py_rc=$?
assert_eq "0" "$py_rc" "AC4 python: model, metadata block, seed bodies, derive_id, show ($(printf '%s' "$py_out" | tail -20))"
assert_contains "$py_out" "PYRESULT ran=15 failed=0" "AC4 python: all 15 cases ran green"

# ---------------------------------------------------------------- 2. through the CLI
P="$(mktemp -d)"; TMP_DIRS+=("$P")
mkdir -p "$P/tasks" "$P/src"
printf '# Tasks\n\n## Plan: Existing\n\n[x] TDD: done -> done\n' > "$P/tasks/todo.md"
printf 'rows = sorted(x)\n' > "$P/src/export.py"

FILE_ARGS=(
  --derive-id sweep --source src/export.py --fold-title
  --title 'Ordering drift'
  --kind bug --label now
  --summary 'Export rows come back in a different order on the second run.'
  --reproduction 'run `make check` on a clean tree, twice'
  --reproduction 'observed: exit 1 / expected: exit 0'
  --proposed-fix 'pin the fixture ordering in tests/lib.sh'
  --criterion 'second run is byte-identical'
  --evidence 'src/export.py:88 — rows = sorted(x, key=None)'
  --evidence 'discovered: sweep/janitor 2026-09-07 @ abc1234'
)

out="$(run upsert --repo "$P" --apply "${FILE_ARGS[@]}" 2>&1)"; rc=$?
assert_eq "0" "$rc" "CLI: upsert --apply with --reproduction/--proposed-fix/--source/--fold-title exits 0 ($out)"
assert_contains "$out" "sweep.src-export-py.ordering-drift" \
  "CLI: the derived id folds namespace, primary file, and short title"
DETAIL="$P/tasks/details/sweep.src-export-py.ordering-drift.md"
assert_eq "present" "$([ -f "$DETAIL" ] && echo present || echo absent)" \
  "CLI: --apply writes the local record under the derived id"
assert_file_contains "$DETAIL" "reproduction: observed: exit 1 / expected: exit 0" \
  "local: metadata block carries each reproduction line whole"
assert_file_contains "$DETAIL" "proposed-fix: pin the fixture ordering in tests/lib.sh" \
  "local: metadata block carries the proposed fix"
assert_file_contains "$DETAIL" "evidence: src/export.py:88 — rows = sorted(x, key=None)" \
  "local: metadata block carries a comma-bearing evidence line whole"
assert_file_contains "$DETAIL" "source: src/export.py" \
  "local: --source is recorded as the task's source path, not its spec"
assert_file_not_matches "$DETAIL" "^spec:" \
  "local: a sweep record about a source file claims no spec"
assert_file_contains "$DETAIL" "## Reproduction" "local: reproduction is rendered as a section"
assert_file_contains "$DETAIL" "1. run \`make check\` on a clean tree, twice" \
  "local: reproduction steps are numbered"
assert_file_contains "$DETAIL" "## Proposed fix" "local: proposed fix is rendered as a section"

show_out="$(run show sweep.src-export-py.ordering-drift --repo "$P" 2>&1)"; show_rc=$?
assert_eq "0" "$show_rc" "CLI: show exits 0 for the filed record"
assert_contains "$show_out" "reproduction:" "show: renders the reproduction"
assert_contains "$show_out" "observed: exit 1 / expected: exit 0" "show: renders every reproduction line"
assert_contains "$show_out" "proposed fix:" "show: renders the proposed fix"
assert_contains "$show_out" "pin the fixture ordering" "show: renders the proposed fix body"

# Same file + title on a later run addresses the SAME task, and the managed
# sections are replaced rather than accreted beside the first copy.
again="$(run upsert --repo "$P" --apply "${FILE_ARGS[@]}" \
  --evidence 'discovered: sweep/janitor 2026-09-08 @ def5678' 2>&1)"; again_rc=$?
assert_eq "0" "$again_rc" "CLI: re-filing the same finding exits 0 ($again)"
assert_contains "$again" "updated" "CLI: re-filing updates the existing task instead of minting a second"
assert_eq "1" "$(grep -c '^## Reproduction' "$DETAIL")" \
  "local: Reproduction is a managed section — one copy after two writes"
assert_eq "1" "$(grep -c '^## Proposed fix' "$DETAIL")" \
  "local: Proposed fix is a managed section — one copy after two writes"
# Evidence is the exception: every run's sighting is kept, once.
assert_file_contains "$DETAIL" "discovered: sweep/janitor 2026-09-08 @ def5678" \
  "local: the second run's sighting is appended to the evidence"
assert_eq "1" "$(grep -c 'discovered: sweep/janitor 2026-09-07 @ abc1234' "$DETAIL")" \
  "local: the first run's sighting survives the second run, once"

# A record re-read from disk with no new reproduction keeps the one it had.
quiet="$(run upsert sweep.src-export-py.ordering-drift --repo "$P" --apply \
  --title 'Ordering drift' --kind bug 2>&1)"; quiet_rc=$?
assert_eq "0" "$quiet_rc" "CLI: a field-less upsert of the same id exits 0 ($quiet)"
assert_file_contains "$DETAIL" "reproduction: observed: exit 1 / expected: exit 0" \
  "local: absent means unchanged — the reproduction survives a bare upsert"
assert_file_contains "$DETAIL" "## Proposed fix" \
  "local: absent means unchanged — the proposed fix survives a bare upsert"

# The visible section is the field's one home in the local file, as it already
# is for acceptance criteria. A human who edits a step there must not have the
# edit reverted by the next registry write from the metadata block's stale copy.
sed -i 's/^- pin the fixture ordering/- pin the fixture ordering (hand-edited)/' "$DETAIL"
sed -i 's/^1\. run /1. by hand: run /' "$DETAIL"
edited="$(run upsert sweep.src-export-py.ordering-drift --repo "$P" --apply \
  --title 'Ordering drift' --kind bug 2>&1)"; edited_rc=$?
assert_eq "0" "$edited_rc" "CLI: a bare upsert after a hand edit exits 0 ($edited)"
assert_file_contains "$DETAIL" "- pin the fixture ordering (hand-edited)" \
  "local: a hand-edited proposed-fix step survives the next write"
assert_file_contains "$DETAIL" "proposed-fix: pin the fixture ordering (hand-edited)" \
  "local: the metadata block is re-projected from the edited section"
assert_file_contains "$DETAIL" "1. by hand: run " \
  "local: a hand-edited reproduction step survives the next write"
assert_file_contains "$DETAIL" "reproduction: by hand: run " \
  "local: the metadata block carries the edited reproduction step"
edited_show="$(run show sweep.src-export-py.ordering-drift --repo "$P" 2>&1)"
assert_contains "$edited_show" "(hand-edited)" "show: renders the hand-edited step"

# --derive-id still needs a path to derive from; --source satisfies it, --fold-title alone does not.
nopath="$(run upsert --repo "$P" --derive-id sweep --fold-title --title 'x' 2>&1)"; nopath_rc=$?
assert_eq "2" "$nopath_rc" "CLI: --derive-id without --spec or --source is a usage error"
assert_contains "$nopath" "--source" "CLI: the usage error names --source as an accepted path"
# --fold-title only means something under --derive-id; alone it was silently ignored.
fold="$(run upsert x.y --repo "$P" --fold-title --title 'x' 2>&1)"; fold_rc=$?
assert_eq "2" "$fold_rc" "CLI: --fold-title without --derive-id is a usage error"
assert_contains "$fold" "--derive-id" "CLI: the usage error names --derive-id"
# Two paths under --derive-id would derive from whichever won silently.
both="$(run upsert --repo "$P" --derive-id sweep --source src/export.py --spec specs/x.md --title 'x' 2>&1)"; both_rc=$?
assert_eq "2" "$both_rc" "CLI: --derive-id with both --source and --spec is a usage error"
# A newline inside a step would end it early in the metadata block; refused before any write.
nl="$(run upsert x.y --repo "$P" --apply --title 'x' --reproduction $'one\nkind: bug' 2>&1)"; nl_rc=$?
assert_eq "2" "$nl_rc" "CLI: a reproduction step containing a newline is refused"
assert_contains "$nl" "reproduction" "CLI: the refusal names the field"
assert_eq "absent" "$([ -f "$P/tasks/details/x.y.md" ] && echo present || echo absent)" \
  "CLI: the refused upsert wrote nothing"

# The parity copy carries the same engine.
assert_files_identical "$CLI" "$REPO/.claude/skills/task-registry/scripts/task-registry.py" \
  "parity: task-registry.py is mirrored"
for f in model.py upsert.py detail.py providers/github.py providers/local.py; do
  assert_files_identical "$SCRIPTS/registry/$f" "$REPO/.claude/skills/task-registry/scripts/registry/$f" \
    "parity: registry/$f is mirrored"
done

finish
