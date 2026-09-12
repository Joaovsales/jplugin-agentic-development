"""Regression coverage for the metadata-block reader/writer agreement.

`parse_metadata_block` (read side) and `_metadata_bounds` (write side, via
`upsert_metadata_block`) must pick the same block out of a body that contains
more than one `<!-- task-registry:begin -->` marker. Before this fix they
disagreed: the reader took the first BEGIN..END span it could find by naive
string splitting, so a quoted example block elsewhere in the body could leak
fields into — or entirely stand in for — the real one.
"""

import unittest

from registry.model import (
    ExternalRef,
    Task,
    parse_metadata_block,
    render_metadata_block,
    task_from_metadata,
    upsert_metadata_block,
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_reads_a_well_formed_block(self):
        body = "\n".join(
            [
                "Some human-written prose.",
                "",
                "<!-- task-registry:begin -->",
                "task-id: real-task",
                "kind: bug",
                "<!-- task-registry:end -->",
            ]
        )
        self.assertEqual(
            parse_metadata_block(body), {"task-id": "real-task", "kind": "bug"}
        )

    def test_unfinished_block_before_the_real_one_does_not_leak_fields(self):
        body = "\n".join(
            [
                "Example format, for reference:",
                "<!-- task-registry:begin -->",
                "task-id: example",
                "parent: someone-elses-parent",
                "",
                "Actual metadata below:",
                "<!-- task-registry:begin -->",
                "task-id: real-task",
                "kind: bug",
                "<!-- task-registry:end -->",
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta, {"task-id": "real-task", "kind": "bug"})
        self.assertNotIn("parent", meta)

    def test_sole_unfinished_block_is_treated_as_no_metadata(self):
        body = "\n".join(
            [
                "Random notes.",
                "<!-- task-registry:begin -->",
                "task-id: draft-id",
                "Oops, forgot to close this.",
            ]
        )
        self.assertEqual(parse_metadata_block(body), {})

    def test_trailing_unfinished_example_does_not_steal_identity(self):
        body = "\n".join(
            [
                "<!-- task-registry:begin -->",
                "task-id: real-task",
                "<!-- task-registry:end -->",
                "",
                "For reference, the block looks like:",
                "<!-- task-registry:begin -->",
                "task-id: draft-id",
            ]
        )
        self.assertEqual(parse_metadata_block(body), {"task-id": "real-task"})

    def test_no_marker_at_all_is_no_metadata(self):
        self.assertEqual(parse_metadata_block("just some prose"), {})
        self.assertEqual(parse_metadata_block(""), {})

    def test_preserves_repeated_line_per_entry_keys(self):
        body = "\n".join(
            [
                "<!-- task-registry:begin -->",
                "task-id: real-task",
                "evidence: first, with a comma",
                "evidence: second line of evidence",
                "reproduction: click here, then there",
                "proposed-fix: do the thing, carefully",
                "<!-- task-registry:end -->",
            ]
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["evidence"], ("first, with a comma", "second line of evidence"))
        self.assertEqual(meta["reproduction"], ("click here, then there",))
        self.assertEqual(meta["proposed-fix"], ("do the thing, carefully",))


class ReaderWriterAgreementTests(unittest.TestCase):
    def test_upsert_replaces_the_same_block_the_reader_would_have_used(self):
        body = "\n".join(
            [
                "Example format, for reference:",
                "<!-- task-registry:begin -->",
                "task-id: example",
                "parent: someone-elses-parent",
                "",
                "Actual metadata below:",
                "<!-- task-registry:begin -->",
                "task-id: real-task",
                "<!-- task-registry:end -->",
                "",
                "Human-written closing remarks.",
            ]
        )
        task = Task(id="real-task", title="Real task", kind="bug")
        updated = upsert_metadata_block(body, task)

        self.assertIn("Example format, for reference:", updated)
        self.assertIn("task-id: example", updated)
        self.assertIn("parent: someone-elses-parent", updated)
        self.assertIn("Human-written closing remarks.", updated)

        meta = parse_metadata_block(updated)
        self.assertEqual(meta, {"task-id": "real-task", "kind": "bug"})

    def test_task_from_metadata_ignores_a_dangling_quoted_block(self):
        body = "\n".join(
            [
                "Random notes.",
                "<!-- task-registry:begin -->",
                "task-id: draft-id",
                "Oops, forgot to close this.",
            ]
        )
        task = task_from_metadata(
            title="A real issue title",
            body=body,
            external=ExternalRef("github", "1", "https://example.invalid/1"),
            status="open",
            fallback_id="",
        )
        self.assertNotEqual(task.id, "draft-id")
        self.assertEqual(task.extra.get("registry_identity"), "provisional-title-slug")


if __name__ == "__main__":
    unittest.main()
