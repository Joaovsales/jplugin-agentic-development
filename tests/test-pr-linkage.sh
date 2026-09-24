#!/usr/bin/env bash
# tests/test-pr-linkage.sh — a closing keyword binds to ONE issue reference only.
#
# GitHub links a closing keyword (close/closes/closed/fix/fixes/fixed/
# resolve/resolves/resolved) to the single issue reference that immediately
# follows it, not to every reference in a list that trails it. Issue #123:
# a PR body of `Closes #99, #100, #101, #102, #103` closed only #99 on
# merge — verified via PR #121's `closingIssuesReferences=[99]` — and
# #100-#103 had to be closed by hand. The working form repeats the keyword
# per issue: `Closes #99, closes #100, closes #101`.
#
# pr_linkage.py's `orphaned_references` finds every reference in such a list
# that has no keyword of its own, so a wrap-up PR body can be checked before
# create/re-sync instead of failing silently after merge. The list shapes
# pinned below are the ones a false pass would let through: the script's one
# job is to catch silent non-closure, so every separator people actually write
# has to end up here.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - <<'PY'
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(os.environ["ROOT"])
SCRIPT = ROOT / ".agents/skills/wrap-up-session/scripts/pr_linkage.py"

spec = importlib.util.spec_from_file_location("pr_linkage", SCRIPT)
pr_linkage = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pr_linkage
spec.loader.exec_module(pr_linkage)

orphaned = pr_linkage.orphaned_references
ORPHANED = pr_linkage.ORPHANED_REFERENCES


class BoundReferenceTests(unittest.TestCase):
    def test_single_closes_has_no_orphan(self):
        self.assertEqual(orphaned("Closes #99"), [])

    def test_per_issue_keyword_list_has_no_orphan(self):
        self.assertEqual(orphaned("Closes #99, closes #100, closes #101"), [])

    def test_refs_is_not_a_closing_keyword(self):
        # A plain mention list is fine — nothing is being (mis)closed.
        self.assertEqual(orphaned("Refs #1, #2"), [])

    def test_body_with_no_closing_keyword_has_no_orphans(self):
        self.assertEqual(orphaned("See #1 for background, #2 also relevant"), [])

    def test_empty_body_has_no_orphans(self):
        self.assertEqual(orphaned(""), [])

    def test_sentence_break_ends_the_chain(self):
        self.assertEqual(orphaned("Closes #1. See #2, #3"), [])

    def test_prose_between_references_ends_the_chain(self):
        self.assertEqual(orphaned("Closes #1 after the refactor in #2, #3"), [])

    def test_quoted_example_in_a_code_span_is_not_a_linkage(self):
        # GitHub does not autolink inside code, and this branch's own PR body
        # quotes the failing form verbatim.
        self.assertEqual(orphaned("See `Closes #1, #2` for the failing form"), [])
        self.assertEqual(orphaned("```\nCloses #1, #2\n```\nCloses #3"), [])


class OrphanedReferenceTests(unittest.TestCase):
    def test_comma_list_reports_orphans_in_order(self):
        # The failure this closes: issue #123 — `Closes #99, #100, #101`
        # links only #99, and #100/#101 have to be closed by hand.
        self.assertEqual(orphaned("Closes #99, #100, #101"), ["#100", "#101"])

    def test_every_list_separator_people_write(self):
        cases = {
            "Closes #1, #2 and #3": ["#2", "#3"],
            "Closes #1, and #2": ["#2"],
            "Closes #1 and also #2": ["#2"],
            "Fixes #1;#2": ["#2"],
            "Fixes #1; #2": ["#2"],
            "Closes #1 & #2": ["#2"],
            "Closes #1 / #2": ["#2"],
            "Closes #1 #2": ["#2"],
            "Closes #1 , #2": ["#2"],
            "Closes #1\n#2": ["#2"],
            "Closes #1\n- #2\n- #3": ["#2", "#3"],
        }
        for body, expected in cases.items():
            with self.subTest(body=body):
                self.assertEqual(orphaned(body), expected)

    def test_mixed_case_keywords(self):
        self.assertEqual(orphaned("Fixes #10, #11"), ["#11"])
        self.assertEqual(orphaned("resolved #20, #21"), ["#21"])
        self.assertEqual(orphaned("CLOSES #30, #31"), ["#31"])

    def test_colon_after_the_keyword_is_tolerated(self):
        self.assertEqual(orphaned("Closes: #1, #2"), ["#2"])

    def test_every_reference_form_github_binds(self):
        self.assertEqual(orphaned("Fixes owner/repo#7, #8"), ["#8"])
        self.assertEqual(orphaned("Closes GH-1, GH-2"), ["GH-2"])
        self.assertEqual(
            orphaned("Closes https://github.com/o/r/issues/5, #6"), ["#6"]
        )

    def test_two_clauses_each_report_their_own_tail(self):
        self.assertEqual(orphaned("Closes #1, #2\nFixes #3, #4"), ["#2", "#4"])


class CommandLineTests(unittest.TestCase):
    def run_cli(self, *args, stdin_text=""):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=stdin_text,
            capture_output=True,
            text=True,
        )

    def test_clean_body_exits_zero_and_prints_nothing(self):
        done = self.run_cli("check", stdin_text="Closes #99, closes #100")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, "")

    def test_bad_body_exits_orphaned_and_names_each_orphan(self):
        done = self.run_cli("check", stdin_text="Closes #99, #100, #101")
        self.assertEqual(done.returncode, ORPHANED)
        self.assertEqual(done.stdout.splitlines(), ["#100", "#101"])

    def test_finding_exit_code_is_neither_a_crash_nor_a_usage_error(self):
        # 1 is an uncaught exception, 2 is argparse's usage error. A caller
        # reading the exit code must not mistake either for a finding.
        self.assertNotIn(ORPHANED, (1, 2))
        usage = self.run_cli("check", "--bodyfile", "x")
        self.assertEqual(usage.returncode, 2)
        self.assertNotEqual(usage.returncode, ORPHANED)
        self.assertEqual(usage.stdout, "")

    def test_body_file_flag_reads_from_disk_instead_of_stdin(self):
        with tempfile.TemporaryDirectory() as tmp:
            body_path = pathlib.Path(tmp) / "body.txt"
            body_path.write_text("Fixes #10, #11", encoding="utf-8")
            done = self.run_cli("check", "--body-file", str(body_path))
        self.assertEqual(done.returncode, ORPHANED)
        self.assertEqual(done.stdout.splitlines(), ["#11"])

    def test_missing_body_file_is_a_crash_not_a_clean_body(self):
        done = self.run_cli("check", "--body-file", "does-not-exist.txt")
        self.assertEqual(done.returncode, 1)
        self.assertIn("FileNotFoundError", done.stderr)


runner = unittest.TextTestRunner(verbosity=0, stream=sys.stderr)
result = runner.run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
count = result.testsRun
if not result.wasSuccessful():
    print(f"  -> {len(result.failures) + len(result.errors)}/{count} assertions FAILED")
    sys.exit(1)
print(f"  -> {count} assertions passed")
PY
