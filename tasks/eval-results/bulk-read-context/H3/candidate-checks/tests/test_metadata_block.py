"""Regression coverage: the reader and the writer must agree on which
metadata block is authoritative when a body quotes a stray or unfinished
example alongside the real one.
"""

from __future__ import annotations

import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    Task,
    metadata_bounds,
    parse_metadata_block,
    render_metadata_block,
    upsert_metadata_block,
)


REAL_BLOCK = "\n".join(
    [
        METADATA_BEGIN,
        "task-id: real-task",
        "kind: bug",
        "depends-on: dep-one, dep-two",
        METADATA_END,
    ]
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_reads_real_block_with_no_stray_markers(self):
        fields = parse_metadata_block(REAL_BLOCK)
        self.assertEqual(fields["task-id"], "real-task")
        self.assertEqual(fields["depends-on"], ("dep-one", "dep-two"))

    def test_ignores_leading_unfinished_example_before_real_block(self):
        body = "\n".join(
            [
                "Here is what an incomplete block looks like:",
                METADATA_BEGIN,
                "task-id: example-only",
                "parent: example-parent",
                "",
                "some human prose in between",
                "",
                REAL_BLOCK,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-task")
        # The quoted example's parent must never leak into the real record.
        self.assertNotIn("parent", fields)
        self.assertEqual(fields["depends-on"], ("dep-one", "dep-two"))

    def test_ignores_trailing_unfinished_example_after_real_block(self):
        body = "\n".join(
            [
                REAL_BLOCK,
                "",
                "By the way, an unfinished block looks like:",
                METADATA_BEGIN,
                "task-id: example-only",
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-task")
        self.assertEqual(fields["depends-on"], ("dep-one", "dep-two"))

    def test_no_complete_block_is_treated_as_no_metadata(self):
        body = "\n".join(
            [
                "Just a fragment of the format, never closed:",
                METADATA_BEGIN,
                "task-id: not-real",
            ]
        )
        self.assertEqual(parse_metadata_block(body), {})

    def test_repeated_line_per_entry_fields_are_preserved(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-task",
                "evidence: first sighting, with a comma in it",
                "evidence: second sighting",
                "reproduction: step one, still one step",
                "reproduction: step two",
                METADATA_END,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(
            fields["evidence"],
            ("first sighting, with a comma in it", "second sighting"),
        )
        self.assertEqual(fields["reproduction"], ("step one, still one step", "step two"))

    def test_agrees_with_writer_on_authoritative_block(self):
        """parse_metadata_block and metadata_bounds must select the same span."""
        body = "\n".join(
            [
                "quoted example:",
                METADATA_BEGIN,
                "task-id: example-only",
                "",
                "more prose",
                "",
                REAL_BLOCK,
            ]
        )
        bounds = metadata_bounds(body)
        start, end = bounds
        self.assertEqual(body[start:end], REAL_BLOCK)
        self.assertEqual(parse_metadata_block(body)["task-id"], "real-task")


class UpsertMetadataBlockTests(unittest.TestCase):
    def test_updating_real_block_keeps_surrounding_human_text(self):
        body = "\n".join(
            [
                "quoted example of the format:",
                METADATA_BEGIN,
                "task-id: example-only",
                "",
                "Human-written notes that must survive.",
                "",
                REAL_BLOCK,
                "",
                "Trailing human notes.",
            ]
        )
        task = Task(id="real-task", title="Real task", kind="bug", depends_on=("dep-one",))
        updated = upsert_metadata_block(body, task)

        self.assertIn("Human-written notes that must survive.", updated)
        self.assertIn("Trailing human notes.", updated)
        self.assertIn("quoted example of the format:", updated)
        # The real block is replaced with the freshly rendered one.
        self.assertIn(render_metadata_block(task), updated)
        self.assertEqual(updated.count(METADATA_BEGIN), 2)  # stray example + real

    def test_round_trip_through_render_and_parse(self):
        task = Task(
            id="round-trip",
            title="Round trip",
            kind="feature",
            parent="parent-task",
            depends_on=("a", "b"),
            evidence=("line one, with comma", "line two"),
        )
        block = render_metadata_block(task)
        fields = parse_metadata_block(block)
        self.assertEqual(fields["task-id"], "round-trip")
        self.assertEqual(fields["parent"], "parent-task")
        self.assertEqual(fields["depends-on"], ("a", "b"))
        self.assertEqual(fields["evidence"], ("line one, with comma", "line two"))


if __name__ == "__main__":
    unittest.main()
