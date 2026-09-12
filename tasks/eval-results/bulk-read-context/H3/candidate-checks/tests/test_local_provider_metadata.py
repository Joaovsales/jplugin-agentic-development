"""Regression coverage for the local Markdown provider's metadata handling,
which must agree with registry.model on which block is authoritative and
must never drop human text because of a stray or unfinished example.
"""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest

from registry.config import Config
from registry.model import METADATA_BEGIN, METADATA_END, Task
from registry.providers.base import WriteGate
from registry.providers.local import LocalMarkdownProvider


class LocalMarkdownMetadataTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.config = Config(root=self.root)
        gate = WriteGate(apply=True, require_approval=False)
        self.provider = LocalMarkdownProvider(self.config, gate)
        os.makedirs(self.provider.detail_dir, exist_ok=True)

    def _write(self, task_id: str, text: str) -> str:
        path = self.provider._path_for(task_id)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def test_read_ignores_leading_quoted_example_block(self):
        text = "\n".join(
            [
                "# Real title",
                "",
                "Here's what an incomplete block looks like:",
                METADATA_BEGIN,
                "task-id: example-only",
                "parent: example-parent",
                "",
                METADATA_BEGIN,
                "task-id: real-task",
                "kind: bug",
                METADATA_END,
                "",
                "- status: open",
                "",
            ]
        )
        path = self._write("real-task", text)
        task = self.provider._read(path)
        self.assertEqual(task.id, "real-task")
        self.assertIsNone(task.parent)

    def test_update_preserves_surrounding_human_text_and_stray_example(self):
        original = "\n".join(
            [
                "# Real title",
                "",
                "quoted example of the format:",
                METADATA_BEGIN,
                "task-id: example-only",
                "",
                METADATA_BEGIN,
                "task-id: real-task",
                "kind: bug",
                METADATA_END,
                "",
                "- status: open",
                "",
                "Notes a human wrote by hand that must survive edits.",
                "",
            ]
        )
        self._write("real-task", original)
        task = Task(id="real-task", title="Real title", kind="bug", status="in_progress")
        self.provider.update_task(task)

        with open(self.provider._path_for("real-task"), encoding="utf-8") as handle:
            updated = handle.read()

        self.assertIn("quoted example of the format:", updated)
        self.assertIn("Notes a human wrote by hand that must survive edits.", updated)
        self.assertIn("status: in_progress", updated)


if __name__ == "__main__":
    unittest.main()
