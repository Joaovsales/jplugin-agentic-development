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
    def test_leading_unfinished_example_is_ignored(self):
        body = "\n".join(
            [
                "Quoted example for the format:",
                METADATA_BEGIN,
                "task-id: example-id",
                "parent: example-parent",
                "",
                "Then the real block:",
                METADATA_BEGIN,
                "task-id: real-id",
                "kind: bug",
                METADATA_END,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-id")
        self.assertEqual(fields["kind"], "bug")
        self.assertNotIn("parent", fields)

    def test_trailing_unfinished_example_is_ignored(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-id",
                "kind: bug",
                METADATA_END,
                "",
                "Example for later:",
                METADATA_BEGIN,
                "task-id: example-id",
                "parent: example-parent",
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-id")
        self.assertEqual(fields["kind"], "bug")
        self.assertNotIn("parent", fields)

    def test_only_unfinished_block_reads_as_no_metadata(self):
        body = "\n".join(
            [
                "Quoted example, never closed:",
                METADATA_BEGIN,
                "task-id: example-id",
                "parent: example-parent",
            ]
        )
        self.assertEqual(parse_metadata_block(body), {})

    def test_no_block_reads_as_no_metadata(self):
        self.assertEqual(parse_metadata_block("just prose, no markers here"), {})

    def test_reader_and_writer_agree_on_which_block_is_real(self):
        body = "\n".join(
            [
                "Example: " + METADATA_BEGIN,
                "task-id: example-id",
                "parent: example-parent",
                "",
                METADATA_BEGIN,
                "task-id: real-id",
                "kind: feature",
                METADATA_END,
            ]
        )
        task = Task(id="real-id", title="Real task", kind="feature")
        updated = upsert_metadata_block(body, task)
        fields = parse_metadata_block(updated)
        self.assertEqual(fields["task-id"], "real-id")
        self.assertNotIn("parent", fields)
        # The leading quoted example is human text outside the real markers
        # and must survive the update untouched.
        self.assertIn("Example: " + METADATA_BEGIN, updated)
        self.assertIn("task-id: example-id", updated)

    def test_task_from_metadata_does_not_invent_parent_from_example(self):
        body = "\n".join(
            [
                "As documented: " + METADATA_BEGIN,
                "task-id: example-id",
                "parent: example-parent",
                "",
                METADATA_BEGIN,
                "task-id: real-id",
                "kind: bug",
                METADATA_END,
            ]
        )
        task = task_from_metadata(
            title="Real task",
            body=body,
            external=None,
            status="open",
        )
        self.assertEqual(task.id, "real-id")
        self.assertIsNone(task.parent)

    def test_repeated_entries_and_commas_still_round_trip(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-id",
                "kind: bug",
                "evidence: log line with, a comma, in it",
                "evidence: second log line",
                "reproduction: step one, then step two",
                METADATA_END,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(
            fields["evidence"],
            ("log line with, a comma, in it", "second log line"),
        )
        self.assertEqual(fields["reproduction"], ("step one, then step two",))


if __name__ == "__main__":
    unittest.main()
