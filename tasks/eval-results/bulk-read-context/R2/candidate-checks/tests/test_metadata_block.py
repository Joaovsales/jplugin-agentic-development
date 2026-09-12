"""Regression coverage for the shared metadata-block reader.

The reader (`parse_metadata_block`) and the writer (`upsert_metadata_block`,
via `_metadata_bounds`) must agree on which BEGIN..END pair is the real,
complete block. A quoted example elsewhere in the body — unfinished or not —
must never leak fields into the parse.
"""

import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    ExternalRef,
    parse_metadata_block,
    task_from_metadata,
    upsert_metadata_block,
)
from registry.providers.local import _merged_with_existing
from registry.model import Task


REAL_BLOCK = "\n".join(
    [
        METADATA_BEGIN,
        "task-id: real-task",
        "kind: bug",
        METADATA_END,
    ]
)


class ParseMetadataBlockTests(unittest.TestCase):
    def test_reads_a_lone_complete_block(self):
        body = f"Some prose.\n\n{REAL_BLOCK}\n"
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-task")
        self.assertEqual(fields["kind"], "bug")

    def test_ignores_a_leading_unfinished_example_before_the_real_block(self):
        quoted = f"Example format:\n\n{METADATA_BEGIN}\ntask-id: quoted-example\nparent: quoted-parent\n"
        body = f"{quoted}\nMore text.\n\n{REAL_BLOCK}\n"
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-task")
        self.assertNotIn("parent", fields)

    def test_ignores_a_trailing_unfinished_example_after_the_real_block(self):
        quoted = f"{METADATA_BEGIN}\ntask-id: quoted-example\n"
        body = f"{REAL_BLOCK}\n\nSee format below:\n\n{quoted}"
        fields = parse_metadata_block(body)
        self.assertEqual(fields["task-id"], "real-task")

    def test_a_lone_unfinished_example_with_no_complete_block_is_no_metadata(self):
        body = f"Format example:\n\n{METADATA_BEGIN}\ntask-id: quoted-example\n"
        fields = parse_metadata_block(body)
        self.assertEqual(fields, {})

    def test_reader_and_writer_agree_on_the_authoritative_block(self):
        quoted = f"{METADATA_BEGIN}\ntask-id: quoted-example\n"
        body = f"{quoted}\n{REAL_BLOCK}\n"
        task = Task(id="real-task", title="Real task", kind="bug")
        rewritten = upsert_metadata_block(body, task.with_(kind="feature"))
        fields = parse_metadata_block(rewritten)
        self.assertEqual(fields["kind"], "feature")
        self.assertEqual(fields["task-id"], "real-task")
        # The leading quoted example is untouched human text, not rewritten.
        self.assertIn("task-id: quoted-example", rewritten)

    def test_preserves_repeated_evidence_entries(self):
        body = "\n".join(
            [
                METADATA_BEGIN,
                "task-id: real-task",
                "evidence: first, with a comma",
                "evidence: second, also with a comma",
                METADATA_END,
            ]
        )
        fields = parse_metadata_block(body)
        self.assertEqual(
            fields["evidence"], ("first, with a comma", "second, also with a comma")
        )

    def test_no_metadata_marker_at_all(self):
        self.assertEqual(parse_metadata_block("just a body"), {})
        self.assertEqual(parse_metadata_block(""), {})


class TaskFromMetadataTests(unittest.TestCase):
    def test_does_not_invent_a_parent_from_a_leading_quoted_example(self):
        quoted = f"Example:\n\n{METADATA_BEGIN}\ntask-id: quoted-example\nparent: quoted-parent\n"
        body = f"{quoted}\n\n{REAL_BLOCK}\n"
        task = task_from_metadata(
            title="Real task",
            body=body,
            external=ExternalRef("github", "42", "https://example/42"),
            status="open",
        )
        self.assertEqual(task.id, "real-task")
        self.assertIsNone(task.parent)


class MergedWithExistingTests(unittest.TestCase):
    def test_does_not_inherit_kind_from_a_quoted_example(self):
        quoted = f"Example:\n\n{METADATA_BEGIN}\ntask-id: quoted-example\nkind: epic\n"
        existing = f"{quoted}\n\n{REAL_BLOCK}\n"
        incoming = Task(id="real-task", title="Real task", kind="task")
        merged = _merged_with_existing(incoming, existing)
        self.assertEqual(merged.kind, "bug")


if __name__ == "__main__":
    unittest.main()
