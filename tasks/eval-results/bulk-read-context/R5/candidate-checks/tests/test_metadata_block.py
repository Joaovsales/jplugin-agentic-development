"""Regression coverage for the identity-block reader/writer agreement.

`parse_metadata_block` must pick the same block `_metadata_bounds` (used by
`upsert_metadata_block`) treats as authoritative. Before this fix, the parser
split naively on the first BEGIN/END pair it found, so a quoted or unfinished
example block elsewhere in the body could be read as the real one.
"""

import unittest

from registry.model import (
    ExternalRef,
    Task,
    parse_metadata_block,
    task_from_metadata,
    upsert_metadata_block,
)

REAL_BLOCK = (
    "<!-- task-registry:begin -->\n"
    "<!-- Managed by /task-registry. Edit the fields, not the markers. -->\n"
    "task-id: real-task\n"
    "kind: bug\n"
    "<!-- task-registry:end -->"
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_leading_unfinished_example_is_ignored(self):
        body = (
            "Quoting the format for reference:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: fake-example\n"
            "parent: bogus-parent\n"
            "\n"
            "The actual block follows:\n" + REAL_BLOCK + "\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta, {"task-id": "real-task", "kind": "bug"})
        self.assertNotIn("parent", meta)

    def test_trailing_unfinished_example_is_ignored(self):
        body = (
            REAL_BLOCK + "\n\n"
            "Example for reference:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: should-not-be-seen\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta, {"task-id": "real-task", "kind": "bug"})

    def test_only_unfinished_example_reads_as_no_metadata(self):
        body = (
            "Quoting the format for reference:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: fake-example\n"
            "parent: bogus-parent\n"
        )
        self.assertEqual(parse_metadata_block(body), {})

    def test_absent_block_reads_as_no_metadata(self):
        self.assertEqual(parse_metadata_block("just some prose, no markers"), {})

    def test_repeated_entries_and_comma_prose_survive(self):
        task = Task(
            id="t1",
            title="Widget breaks",
            evidence=("log line: error, retrying", "second log line"),
            reproduction=("open the app, then click save", "observe the crash"),
            proposed_fix=("guard the null case, add a test",),
        )
        body = upsert_metadata_block("", task)
        meta = parse_metadata_block(body)
        self.assertEqual(
            meta["evidence"], ("log line: error, retrying", "second log line")
        )
        self.assertEqual(
            meta["reproduction"],
            ("open the app, then click save", "observe the crash"),
        )
        self.assertEqual(meta["proposed-fix"], ("guard the null case, add a test",))

    def test_task_from_metadata_ignores_quoted_example(self):
        body = (
            "See format:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: fake-example\n"
            "parent: bogus-parent\n"
            "\n" + REAL_BLOCK + "\n"
        )
        task = task_from_metadata(
            title="Widget breaks",
            body=body,
            external=ExternalRef("github", "42"),
            status="open",
        )
        self.assertEqual(task.id, "real-task")
        self.assertIsNone(task.parent)


class UpsertMetadataBlockTests(unittest.TestCase):
    def test_updates_real_block_and_preserves_surrounding_text_and_example(self):
        body = (
            "Quoting the format for reference:\n"
            "<!-- task-registry:begin -->\n"
            "task-id: fake-example\n"
            "\n"
            "Human notes above the real block.\n" + REAL_BLOCK + "\n"
            "\nHuman notes below the real block.\n"
        )
        task = Task(id="real-task", title="Widget breaks", kind="feature")
        updated = upsert_metadata_block(body, task)

        # Surrounding human text and the quoted example are untouched.
        self.assertIn("Quoting the format for reference:", updated)
        self.assertIn("task-id: fake-example", updated)
        self.assertIn("Human notes above the real block.", updated)
        self.assertIn("Human notes below the real block.", updated)

        # Only the real block was rewritten, and it now agrees with the reader.
        meta = parse_metadata_block(updated)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["kind"], "feature")


if __name__ == "__main__":
    unittest.main()
