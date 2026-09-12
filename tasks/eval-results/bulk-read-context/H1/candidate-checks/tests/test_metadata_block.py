"""Regression coverage for the metadata-block reader/writer agreement.

`parse_metadata_block` (the reader) and `upsert_metadata_block` (the writer, via
`_metadata_bounds`) must pick the same BEGIN..END pair as authoritative. Before
this fix, the reader took the *first* BEGIN it found while the writer took the
*last well-formed* pair, so a body quoting an unfinished example block --
before or after the real one -- let the reader invent fields (a bogus parent or
dependency) from the wrong block, or lose identity entirely.
"""

from __future__ import annotations

import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    Task,
    parse_metadata_block,
    task_from_metadata,
    upsert_metadata_block,
)


REAL_BLOCK = "\n".join(
    [
        METADATA_BEGIN,
        "<!-- Managed by /task-registry. Edit the fields, not the markers. -->",
        "task-id: real-task",
        "kind: bug",
        METADATA_END,
    ]
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_leading_unfinished_example_is_ignored(self):
        body = (
            "Quoted example of the format:\n\n"
            f"{METADATA_BEGIN}\n"
            "task-id: example-parent\n"
            "parent: bogus-parent\n"
            "depends-on: bogus-dep\n\n"
            "Then the real block below.\n\n"
            f"{REAL_BLOCK}\n\n"
            "Trailing human text.\n"
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields, {"task-id": "real-task", "kind": "bug"})

    def test_trailing_unfinished_example_is_ignored(self):
        body = (
            "Real block:\n\n"
            f"{REAL_BLOCK}\n\n"
            "Unfinished example after:\n"
            f"{METADATA_BEGIN}\n"
            "task-id: example-after\n"
            "parent: bogus-parent-2\n"
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields, {"task-id": "real-task", "kind": "bug"})

    def test_no_complete_block_is_no_metadata(self):
        body = f"{METADATA_BEGIN}\ntask-id: nope\nparent: bogus\n"
        self.assertEqual(parse_metadata_block(body), {})

    def test_empty_body_is_no_metadata(self):
        self.assertEqual(parse_metadata_block(""), {})
        self.assertEqual(parse_metadata_block(None), {})

    def test_repeated_line_per_entry_keys_are_preserved(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: t1",
                "kind: bug",
                "evidence: first sighting, with a comma",
                "evidence: second sighting, also with a comma",
                METADATA_END,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(
            fields["evidence"],
            ("first sighting, with a comma", "second sighting, also with a comma"),
        )

    def test_depends_on_still_splits_on_comma(self):
        body = "\n".join(
            [METADATA_BEGIN, "task-id: t1", "depends-on: a, b, c", METADATA_END]
        )
        self.assertEqual(parse_metadata_block(body)["depends-on"], ("a", "b", "c"))


class ReaderWriterAgreementTests(unittest.TestCase):
    def test_reader_and_writer_agree_when_example_precedes_real_block(self):
        """upsert must update the same block parse_metadata_block reads."""
        body = (
            "Example in the docs:\n\n"
            f"{METADATA_BEGIN}\n"
            "task-id: example\n\n"
            "Real block:\n\n"
            f"{REAL_BLOCK}\n\n"
            "Trailing prose.\n"
        )
        task = Task(id="real-task", title="t", kind="bug", status="open", depends_on=("dep-1",))
        updated = upsert_metadata_block(body, task)

        # The stray example and the surrounding prose survive untouched.
        self.assertIn("Example in the docs:", updated)
        self.assertIn("Trailing prose.", updated)
        self.assertIn(f"{METADATA_BEGIN}\ntask-id: example", updated)

        # The real block was updated in place, in the same location the reader sees.
        fields = parse_metadata_block(updated)
        self.assertEqual(fields["task-id"], "real-task")
        self.assertEqual(fields["depends-on"], ("dep-1",))

    def test_updating_real_block_keeps_surrounding_human_text(self):
        body = f"Preamble kept.\n\n{REAL_BLOCK}\n\n## Notes\n\nHuman notes kept.\n"
        task = Task(id="real-task", title="t", kind="bug", status="open", parent="parent-1")
        updated = upsert_metadata_block(body, task)
        self.assertIn("Preamble kept.", updated)
        self.assertIn("## Notes", updated)
        self.assertIn("Human notes kept.", updated)
        self.assertIn("parent: parent-1", updated)


class TaskFromMetadataTests(unittest.TestCase):
    def test_does_not_invent_parent_from_unfinished_leading_example(self):
        body = (
            "Format example, unfinished:\n\n"
            f"{METADATA_BEGIN}\n"
            "task-id: example\n"
            "parent: bogus-parent\n"
            "depends-on: bogus-dep\n\n"
            f"{REAL_BLOCK}\n"
        )
        task = task_from_metadata(
            title="Issue title",
            body=body,
            external=None,
            status="open",
        )
        self.assertEqual(task.id, "real-task")
        self.assertIsNone(task.parent)
        self.assertEqual(task.depends_on, ())

    def test_no_complete_block_falls_back_to_provisional_identity(self):
        body = f"{METADATA_BEGIN}\ntask-id: unfinished\n"
        task = task_from_metadata(
            title="Issue title",
            body=body,
            external=None,
            status="open",
            fallback_id="",
        )
        self.assertNotEqual(task.id, "unfinished")
        self.assertEqual(task.extra.get("registry_identity"), "provisional-title-slug")


if __name__ == "__main__":
    unittest.main()
