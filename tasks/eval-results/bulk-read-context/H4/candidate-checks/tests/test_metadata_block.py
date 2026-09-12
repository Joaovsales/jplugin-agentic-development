import unittest

from registry.model import (
    METADATA_BEGIN,
    METADATA_END,
    Task,
    parse_metadata_block,
    upsert_metadata_block,
)

REAL_BLOCK = f"""{METADATA_BEGIN}
task-id: real-task
kind: task
depends-on: other-task
{METADATA_END}"""


class ParseMetadataBlockTest(unittest.TestCase):
    def test_reads_a_well_formed_block(self):
        meta = parse_metadata_block(f"prose\n\n{REAL_BLOCK}\n")
        self.assertEqual(meta["task-id"], "real-task")
        self.assertEqual(meta["depends-on"], ("other-task",))

    def test_no_block_is_no_metadata(self):
        self.assertEqual(parse_metadata_block(""), {})
        self.assertEqual(parse_metadata_block("just prose"), {})

    def test_ignores_a_leading_unfinished_example_block(self):
        body = (
            "Quoted example of the format:\n"
            f"{METADATA_BEGIN}\n"
            "task-id: fake-task\n"
            "parent: fake-parent\n"
            "depends-on: fake-dep\n"
            "(the example is never closed)\n\n"
            "Actual registry block:\n"
            f"{REAL_BLOCK}\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")
        self.assertNotIn("parent", meta)
        self.assertEqual(meta["depends-on"], ("other-task",))

    def test_ignores_a_trailing_unfinished_example_block(self):
        body = (
            f"{REAL_BLOCK}\n\n"
            "Format for reference:\n"
            f"{METADATA_BEGIN}\n"
            "task-id: fake-task\n"
            "(never closed)\n"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["task-id"], "real-task")

    def test_reader_and_writer_agree_on_which_block_is_authoritative(self):
        body = (
            "Quoted example:\n"
            f"{METADATA_BEGIN}\n"
            "task-id: fake-task\n"
            "parent: fake-parent\n"
            "(unfinished)\n\n"
            f"{REAL_BLOCK}\n"
        )
        task = Task(id="real-task", title="t", kind="task", status="open")
        rewritten = upsert_metadata_block(body, task)
        # The stray quoted example survives untouched; only the real block updates.
        self.assertIn("task-id: fake-task", rewritten)
        self.assertIn("parent: fake-parent", rewritten)
        meta_after = parse_metadata_block(rewritten)
        self.assertEqual(meta_after["task-id"], "real-task")
        self.assertNotIn("parent", meta_after)

    def test_preserves_comma_containing_prose_entries(self):
        body = (
            f"{METADATA_BEGIN}\n"
            "task-id: t1\n"
            "kind: task\n"
            "evidence: log line with, a comma, in it\n"
            "reproduction: step one, then step two\n"
            f"{METADATA_END}"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["evidence"], ("log line with, a comma, in it",))
        self.assertEqual(meta["reproduction"], ("step one, then step two",))

    def test_preserves_repeated_entries(self):
        body = (
            f"{METADATA_BEGIN}\n"
            "task-id: t1\n"
            "kind: task\n"
            "evidence: first source line\n"
            "evidence: second source line\n"
            "proposed-fix: do this\n"
            "proposed-fix: then that\n"
            f"{METADATA_END}"
        )
        meta = parse_metadata_block(body)
        self.assertEqual(meta["evidence"], ("first source line", "second source line"))
        self.assertEqual(meta["proposed-fix"], ("do this", "then that"))

    def test_updating_a_real_block_keeps_surrounding_human_text(self):
        body = f"# Title\n\nHuman notes above.\n\n{REAL_BLOCK}\n\nHuman notes below.\n"
        task = Task(id="real-task", title="Title", kind="task", status="open")
        rewritten = upsert_metadata_block(body, task)
        self.assertIn("Human notes above.", rewritten)
        self.assertIn("Human notes below.", rewritten)


if __name__ == "__main__":
    unittest.main()
