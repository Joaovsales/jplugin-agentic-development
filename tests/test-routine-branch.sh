#!/usr/bin/env bash
# tests/test-routine-branch.sh — the routine branch convention, both directions.
#
# specs/category-routines.md AC3, AC4, AC5. The branch name is the only channel
# that carries the routine and the issue from the routine that opened the work to
# the `/wrap-up-session` that closes it, so the parser is load-bearing. The
# formatter ships with it: a reader with no writer in-tree is a serialization
# nobody can test round-trip, and a routine emitting `routine/plan/90_slug` would
# parse to None while wrap-up silently opened a ready PR instead of a draft.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

python3 - <<'PY'
import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(os.environ["ROOT"])
SCRIPT = ROOT / ".agents/skills/wrap-up-session/scripts/routine_branch.py"
spec = importlib.util.spec_from_file_location("routine_branch", SCRIPT)
routine_branch = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = routine_branch
spec.loader.exec_module(routine_branch)

parse = routine_branch.parse_routine_branch
fmt = routine_branch.format_routine_branch

#: The module owns this list now; the test asserts it matches the contract doc.
CONTRACT_ROUTINES = routine_branch.CONTRACT_ROUTINES


class ParseTests(unittest.TestCase):
    def test_ac3_namespaced_forms_yield_routine_and_issue(self):
        self.assertEqual(parse("routine/plan/90-auxiliary-input-contract"), ("plan", 90))
        self.assertEqual(parse("routine/fix/97-recipe-morph-beats"), ("fix", 97))
        self.assertEqual(parse("routine/improve/12-x"), ("improve", 12))
        self.assertEqual(parse("routine/build/3-x"), ("build", 3))

    def test_ac4_rejects_everything_outside_the_namespace_or_shape(self):
        # `fix/2024-refactor` is the reason the namespace exists: prefix-anchoring
        # on a bare routine name links a human branch to unrelated issue 2024.
        for branch in (
            "fix/2024-refactor",
            "feature/2024-refactor",
            "routine/fix/no-number",
            "routine/fix/90",
            "master",
            "routine//90-x",
        ):
            with self.subTest(branch=branch):
                self.assertIsNone(parse(branch))

    def test_empty_and_whitespace_branches_are_not_routines(self):
        for branch in ("", "   ", "\n"):
            with self.subTest(branch=repr(branch)):
                self.assertIsNone(parse(branch))

    def test_namespace_is_anchored_at_the_start(self):
        self.assertIsNone(parse("wip/routine/fix/90-x"))

    def test_routine_name_is_lowercase_and_hyphenated_only(self):
        self.assertIsNone(parse("routine/Fix/90-x"))
        self.assertIsNone(parse("routine/fix_it/90-x"))
        self.assertIsNone(parse("routine/-fix/90-x"))
        self.assertEqual(parse("routine/deep-fix/90-x"), ("deep-fix", 90))

    def test_slug_may_contain_hyphens_and_digits(self):
        self.assertEqual(parse("routine/fix/90-drop-923-loc"), ("fix", 90))


class FormatTests(unittest.TestCase):
    def test_ac5_round_trips_every_contract_routine(self):
        for name in CONTRACT_ROUTINES:
            with self.subTest(routine=name):
                branch = fmt(name, 90, "auxiliary input contract")
                self.assertEqual(parse(branch), (name, 90))

    def test_a_name_no_routine_owns_is_refused(self):
        # The failure this closes: `plna` passes any shape check and yields a
        # branch that parses. wrap-up then sees "not plan" and opens a READY PR
        # for what should have been a draft proposal, with nothing erroring.
        with self.assertRaises(ValueError) as caught:
            fmt("plna", 90, "x")
        self.assertIn("plna", str(caught.exception))
        # A caller adding a routine says so explicitly rather than editing the module.
        self.assertEqual(fmt("audit", 90, "x", known=("audit",)), "routine/audit/90-x")

    def test_an_unsluggable_title_falls_back_instead_of_halting(self):
        # A CJK or emoji-only issue title must not halt a routine at step 3. The
        # issue number is what identifies the branch; the slug is decoration.
        branch = fmt("fix", 90, "\u30c6\u30b9\u30c8")
        self.assertEqual(branch, f"routine/fix/90-{routine_branch.FALLBACK_SLUG}")
        self.assertEqual(parse(branch), ("fix", 90))
        self.assertEqual(parse(fmt("fix", 7, "!!!")), ("fix", 7))

    def test_slug_is_normalized_so_the_output_always_parses(self):
        self.assertEqual(
            fmt("plan", 90, "Auxiliary Input Contract"),
            "routine/plan/90-auxiliary-input-contract",
        )
        # The failure this closes: an underscore slug parses to None, and wrap-up
        # would open a ready PR for a `plan` routine with nothing raising.
        self.assertEqual(fmt("plan", 90, "90_slug"), "routine/plan/90-90-slug")
        self.assertEqual(fmt("fix", 7, "  trailing --- junk!!  "), "routine/fix/7-trailing-junk")

    def test_long_slugs_are_truncated_without_a_trailing_hyphen(self):
        branch = fmt("fix", 7, "word " * 60)
        self.assertLessEqual(len(branch), routine_branch.MAX_BRANCH_LENGTH)
        self.assertFalse(branch.endswith("-"))
        self.assertEqual(parse(branch), ("fix", 7))

    def test_refuses_input_it_cannot_serialize(self):
        # No silent failures: a formatter that emitted an unparseable branch would
        # be discovered as a wrong PR flag, days later, with no error anywhere.
        for routine, issue, slug in (
            ("", 90, "x"),
            ("Fix", 90, "x"),
            ("fix_it", 90, "x"),
            ("fix", 0, "x"),
            ("fix", -1, "x"),
        ):
            with self.subTest(routine=routine, issue=issue, slug=slug):
                with self.assertRaises(ValueError):
                    fmt(routine, issue, slug)

    def test_every_contract_routine_name_is_itself_parseable(self):
        # Guards the list against an entry the regex could not carry back.
        for name in CONTRACT_ROUTINES:
            with self.subTest(routine=name):
                self.assertEqual(parse(f"routine/{name}/1-x"), (name, 1))


class CommandLineTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
        )

    def test_parse_prints_routine_and_issue(self):
        done = self.run_cli("parse", "routine/plan/90-x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.split(), ["plan", "90"])

    def test_parse_of_a_plain_branch_exits_three_and_prints_nothing(self):
        # Not a failure — a branch outside the namespace is the ordinary case, and
        # wrap-up behaves exactly as it does today. Quiet, non-zero, no stderr.
        done = self.run_cli("parse", "master")
        self.assertEqual(done.returncode, 3)
        self.assertEqual(done.stdout.strip(), "")
        self.assertEqual(done.stderr.strip(), "")

    def test_format_prints_the_branch(self):
        done = self.run_cli("format", "plan", "90", "Auxiliary Input Contract")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "routine/plan/90-auxiliary-input-contract")

    def test_format_refuses_loudly(self):
        done = self.run_cli("format", "Fix", "90", "x")
        self.assertEqual(done.returncode, 2)
        self.assertIn("Fix", done.stderr)


class ContractAgreementTests(unittest.TestCase):
    """The module's routine list and the contract document must not drift.

    CONTRACT_ROUTINES is the formatter's membership check, so a routine present
    in one and absent from the other is either an unschedulable branch or a
    routine nobody can create a branch for.
    """

    def test_module_list_matches_the_contract_document(self):
        contract = (ROOT / ".agents/skills/wrap-up-session/references/routines.md").read_text(
            encoding="utf-8"
        )
        documented = set(re.findall(r"^\| `([a-z][a-z-]*)` \|", contract, re.M))
        self.assertEqual(documented, set(CONTRACT_ROUTINES))


runner = unittest.TextTestRunner(verbosity=0, stream=sys.stderr)
result = runner.run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
count = result.testsRun
if not result.wasSuccessful():
    print(f"  -> {len(result.failures) + len(result.errors)}/{count} assertions FAILED")
    sys.exit(1)
print(f"  -> {count} assertions passed")
PY
