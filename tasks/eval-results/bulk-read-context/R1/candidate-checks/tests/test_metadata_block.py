"""Regression coverage: the reader and the writer must agree on which
BEGIN..END pair in a body is the authoritative metadata block.

A task description can quote the block format as an example. If that quote is
unfinished (a BEGIN with no matching END of its own), it must never be mistaken
for the real block — whether it sits before or after it.
"""

import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    Task,
    parse_metadata_block,
    upsert_metadata_block,
)

REAL_TASK = Task(id="real-task", title="Real task", parent=None)


def real_block(task_id="real-task", parent=None, depends_on=()):
    task = Task(id=task_id, title="Real task", parent=parent, depends_on=depends_on)
    return upsert_metadata_block("", task).strip()


class ParseMetadataBlockTests(unittest.TestCase):
    def test_no_block_returns_empty(self):
        self.assertEqual(parse_metadata_block(""), {})
        self.assertEqual(parse_metadata_block("just some prose"), {})

    def test_single_complete_block(self):
        body = f"Some notes.\n\n{real_block(parent='epic.roots')}\n\nMore notes."
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["parent"], "epic.roots")

    def test_unfinished_example_before_real_block_is_ignored(self):
        quoted_example = f"{METADATA_BEGIN}\nparent: example.fake\ntask-id: fake-id"
        body = (
            "Format example (do not fill in the end marker below):\n\n"
            f"{quoted_example}\n\n"
            "Actual task:\n\n"
            f"{real_block(parent='epic.roots')}\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["parent"], "epic.roots")
        self.assertNotEqual(meta.get("parent"), "example.fake")

    def test_unfinished_example_after_real_block_is_ignored(self):
        trailing_example = f"{METADATA_BEGIN}\nparent: example.fake\ndepends-on: fake-dep"
        body = (
            f"{real_block(parent='epic.roots', depends_on=('a', 'b'))}\n\n"
            "Example of the format for reference:\n\n"
            f"{trailing_example}\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["parent"], "epic.roots")
        self.assertEqual(meta["depends-on"], ("a", "b"))

    def test_only_unfinished_example_reads_as_no_metadata(self):
        body = f"{METADATA_BEGIN}\ntask-id: fake-id\nparent: example.fake\n"
        self.assertEqual(parse_metadata_block(body), {})

    def test_reader_and_writer_agree_after_upsert_with_stray_marker(self):
        # A body carrying only a stray, unfinished quote of the format: treated
        # as having no block, so upsert appends rather than deleting the quote.
        stray = f"See the format:\n\n{METADATA_BEGIN}\nparent: example.fake\n"
        task = Task(id="new-task", title="New task", parent="epic.roots")
        written = upsert_metadata_block(stray, task)

        meta = parse_metadata_block(written)
        self.assertEqual(meta["task-id"], "new-task")
        self.assertEqual(meta["parent"], "epic.roots")
        # The stray quote is still there, untouched.
        self.assertIn("See the format:", written)
        self.assertIn("parent: example.fake", written)

    def test_update_preserves_surrounding_human_text(self):
        body = (
            "Intro paragraph.\n\n"
            f"{real_block(parent='epic.old')}\n\n"
            "Trailing paragraph."
        )
        updated = upsert_metadata_block(
            body, Task(id="real-task", title="Real task", parent="epic.new")
        )
        self.assertIn("Intro paragraph.", updated)
        self.assertIn("Trailing paragraph.", updated)
        meta = parse_metadata_block(updated)
        self.assertEqual(meta["parent"], "epic.new")

    def test_repeated_line_per_entry_keys_preserved(self):
        task = Task(
            id="t1",
            title="T1",
            evidence=("first, with a comma", "second entry"),
            reproduction=("step one, ok", "step two"),
            proposed_fix=("do x, then y",),
        )
        block = upsert_metadata_block("", task)
        meta = parse_metadata_block(block)
        self.assertEqual(meta["evidence"], ("first, with a comma", "second entry"))
        self.assertEqual(meta["reproduction"], ("step one, ok", "step two"))
        self.assertEqual(meta["proposed-fix"], ("do x, then y",))

    def test_unfinished_example_does_not_leak_identity_when_no_real_block(self):
        body = f"Example only:\n\n{METADATA_BEGIN}\ntask-id: should-not-be-used\n"
        meta = parse_metadata_block(body)
        self.assertEqual(meta, {})


if __name__ == "__main__":
    unittest.main()
