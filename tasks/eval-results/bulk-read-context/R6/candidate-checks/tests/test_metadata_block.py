"""Regression coverage for the metadata-block reader/writer agreement.

`parse_metadata_block` (the reader) and `_metadata_bounds` (which
`upsert_metadata_block`, the writer, relies on) must pick the same block as
authoritative. Before the fix, the reader took the text between the first
BEGIN marker and the first END marker, so a body that quoted an unfinished
example ahead of the real block let the example's fields bleed into the
parsed result -- or, with a stray unfinished example trailing the real one,
still worked by accident. This file pins both directions down.
"""

import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    Task,
    parse_metadata_block,
    task_from_metadata,
    upsert_metadata_block,
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_no_block_returns_empty(self):
        self.assertEqual(parse_metadata_block("just some prose"), {})

    def test_ordinary_block_is_read(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-task",
                "parent: real-parent",
                METADATA_END,
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["parent"], "real-parent")

    def test_leading_unfinished_example_is_ignored(self):
        """An unfinished example quoted before the real block must not donate
        fields the real block never set -- e.g. an invented parent."""
        body = "\n".join(
            [
                "Here is the format we use, for reference:",
                METADATA_BEGIN,
                "task-id: example-task",
                "parent: invented-parent",
                "",
                "(the example above is never closed)",
                "",
                METADATA_BEGIN,
                "task-id: real-task",
                METADATA_END,
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertNotIn("parent", meta)

    def test_trailing_unfinished_example_is_ignored(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-task",
                METADATA_END,
                "",
                "See also the format below (left unfinished intentionally):",
                METADATA_BEGIN,
                "task-id: example-task",
                "parent: invented-parent",
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertNotIn("parent", meta)

    def test_only_unfinished_block_is_treated_as_no_metadata(self):
        body = "\n".join(
            [
                "An example, never closed:",
                METADATA_BEGIN,
                "task-id: example-task",
            ]
        )
        self.assertEqual(parse_metadata_block(body), {})

    def test_repeated_line_per_entry_keys_still_accrete(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-task",
                "evidence: first sighting, with a comma",
                "evidence: second sighting, also with a comma",
                METADATA_END,
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(
            meta["evidence"],
            ("first sighting, with a comma", "second sighting, also with a comma"),
        )

    def test_reader_agrees_with_writer_on_which_block_is_real(self):
        """The reader's identity must match the span the writer would update."""
        body = "\n".join(
            [
                "Quoted example, unfinished:",
                METADATA_BEGIN,
                "task-id: example-task",
                "",
                METADATA_BEGIN,
                "task-id: real-task",
                METADATA_END,
                "",
                "Some human-written notes about this task.",
            ]
        )
        task = Task(id="real-task", title="Real task")
        rewritten = upsert_metadata_block(body, task)
        # Everything outside the real block -- including the quoted example --
        # survives the write untouched.
        self.assertIn("Quoted example, unfinished:", rewritten)
        self.assertIn("task-id: example-task", rewritten)
        self.assertIn("Some human-written notes about this task.", rewritten)
        meta_after_write = parse_metadata_block(rewritten)
        self.assertEqual(meta_after_write["task-id"], "real-task")
        # The reader, run on the original body, must have identified the very
        # same block the writer just replaced.
        self.assertEqual(parse_metadata_block(body).get("task-id"), "real-task")


class TaskFromMetadataTests(unittest.TestCase):
    def test_quoted_example_does_not_invent_parent_or_dependency(self):
        body = "\n".join(
            [
                "For reference, tasks look like this:",
                METADATA_BEGIN,
                "task-id: example-task",
                "parent: invented-parent",
                "depends-on: invented-dep",
                "",
                METADATA_BEGIN,
                "task-id: real-task",
                METADATA_END,
            ]
        )
        task = task_from_metadata(
            title="Real task",
            body=body,
            external=None,
            status="open",
        )
        self.assertEqual(task.id, "real-task")
        self.assertIsNone(task.parent)
        self.assertEqual(task.depends_on, ())


if __name__ == "__main__":
    unittest.main()
