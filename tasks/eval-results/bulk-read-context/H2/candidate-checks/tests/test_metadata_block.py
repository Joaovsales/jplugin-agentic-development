"""Regression coverage for reader/writer agreement on the metadata block.

parse_metadata_block used to locate the block by splitting on the first BEGIN
and the first END it found, while upsert_metadata_block (via
_metadata_bounds) always located the innermost well-formed pair. A stray or
unfinished BEGIN — a quoted example in prose, an interrupted write — made the
two disagree about which block was authoritative, letting the reader invent a
parent or dependency the writer never wrote.
"""

import unittest

from registry.model import Task, parse_metadata_block, upsert_metadata_block


class ParseMetadataBlockAuthorityTests(unittest.TestCase):
    def test_leading_unfinished_example_is_ignored(self):
        body = (
            "Format looks like this:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: bogus\n"
            "parent: invented-parent\n"
            "depends-on: invented-dep\n"
            "\n"
            "Then write the real one below.\n"
            "\n"
            "<!-- task-registry:begin -->\n"
            "task-id: real-1\n"
            "kind: bug\n"
            "<!-- task-registry:end -->\n"
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields, {"task-id": "real-1", "kind": "bug"})

    def test_trailing_unfinished_example_does_not_shadow_identity(self):
        body = (
            "<!-- task-registry:begin -->\n"
            "task-id: real-2\n"
            "kind: bug\n"
            "<!-- task-registry:end -->\n"
            "\n"
            "## Example\n"
            "<!-- task-registry:begin -->\n"
            "task-id: example-only\n"
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields, {"task-id": "real-2", "kind": "bug"})

    def test_no_complete_block_reads_as_no_metadata(self):
        body = "Some prose.\n<!-- task-registry:begin -->\ntask-id: incomplete\n"
        self.assertEqual(parse_metadata_block(body), {})

    def test_empty_body_reads_as_no_metadata(self):
        self.assertEqual(parse_metadata_block(""), {})

    def test_reader_and_writer_agree_on_which_pair_is_authoritative(self):
        body = (
            "<!-- task-registry:begin -->\n"
            "task-id: stale\n"
            "<!-- task-registry:begin -->\n"
            "task-id: real-3\n"
            "<!-- task-registry:end -->\n"
        )
        task = Task(id="real-3", title="Title", kind="bug")
        rewritten = upsert_metadata_block(body, task)
        self.assertEqual(parse_metadata_block(body)["task-id"], "real-3")
        self.assertEqual(parse_metadata_block(rewritten)["task-id"], "real-3")


class ParseMetadataBlockRoundTripTests(unittest.TestCase):
    def test_round_trip_preserves_repeated_entries_and_commas(self):
        task = Task(
            id="t1",
            title="Title",
            parent="p1",
            depends_on=("d1", "d2"),
            evidence=("found at line 42, column 3", "second occurrence"),
            reproduction=("step one, with a comma", "step two"),
            proposed_fix=("do X, then Y",),
        )
        rendered = upsert_metadata_block("Human-written context.", task)
        fields = parse_metadata_block(rendered)
        self.assertEqual(fields["parent"], "p1")
        self.assertEqual(fields["depends-on"], ("d1", "d2"))
        self.assertEqual(
            fields["evidence"], ("found at line 42, column 3", "second occurrence")
        )
        self.assertEqual(fields["reproduction"], ("step one, with a comma", "step two"))
        self.assertEqual(fields["proposed-fix"], ("do X, then Y",))

    def test_upsert_preserves_surrounding_human_text(self):
        body = "Intro line.\n\n<!-- task-registry:begin -->\ntask-id: old\n<!-- task-registry:end -->\n\n## Notes\nKeep me.\n"
        task = Task(id="old", title="Title", kind="bug")
        rewritten = upsert_metadata_block(body, task)
        self.assertIn("Intro line.", rewritten)
        self.assertIn("## Notes", rewritten)
        self.assertIn("Keep me.", rewritten)
        self.assertEqual(parse_metadata_block(rewritten)["kind"], "bug")


if __name__ == "__main__":
    unittest.main()
