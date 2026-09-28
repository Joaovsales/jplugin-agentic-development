"""Exercise the public CLI and hook with a worker that never calls a model."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/context-read.py"
HOOK = ROOT / ".claude/hooks/bulk-read-gate.py"


class ContextReadCases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.box = Path(self.temp.name)
        self.source = self.box / "large.txt"
        self.source.write_text("".join(f"line {n}\n" for n in range(400)))
        self.worker = self.box / "worker.py"
        self.worker.write_text(
            "import hashlib,json,os,sys\n"
            "from pathlib import Path\n"
            "r=json.load(sys.stdin); Path(os.environ['CALLS']).open('a').write('x')\n"
            "s=r['content']; p=r['path']\n"
            "print(json.dumps({'path':p,'sha256':hashlib.sha256(s.encode()).hexdigest(),"
            "'claims':[{'text':'first line','start_line':1,'end_line':1}],"
            "'coverage':[{'start_line':1,'end_line':len(s.splitlines())}],"
            "'unknowns':[],'incomplete':False}))\n"
        )
        self.env = dict(os.environ, CALLS=str(self.box / "calls"),
                        BULK_READ_WORKER_ARGV=json.dumps([sys.executable, str(self.worker)]),
                        BULK_READ_TELEMETRY=str(self.box / "telemetry.jsonl"))

    def run_route(self, event, env=None):
        return subprocess.run([sys.executable, str(CLI), "--route"],
                              input=json.dumps(event), text=True, capture_output=True,
                              env=env or self.env, cwd=ROOT)

    def event(self, path=None, response=None, tool="Read", extra=None):
        value = {"file_path": str(path or self.source)}
        value.update(extra or {})
        return {"harness": "claude", "tool_name": tool, "tool_input": value,
                "tool_response": response if response is not None else self.source.read_text(),
                "tool_use_id": "read-1"}

    def test_eligible_read_returns_bounded_map(self):
        result = self.run_route(self.event())
        self.assertEqual(result.returncode, 0, result.stderr)
        route = json.loads(result.stdout)
        self.assertEqual(route["replacement"]["claims"][0]["start_line"], 1)
        self.assertEqual((self.box / "calls").read_text(), "x")

    def test_pi_matching_read_still_routes(self):
        event = self.event(tool="read")
        event["harness"] = "pi"
        result = self.run_route(event)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(json.loads(result.stdout)["replacement"])
        self.assertEqual((self.box / "calls").read_text(), "x")

    def test_worker_metrics_keep_unknown_usage_without_content(self):
        env = dict(self.env, BULK_READ_METRICS=str(self.box / "metrics.jsonl"))
        result = self.run_route(self.event(), env)
        self.assertIsNotNone(json.loads(result.stdout)["replacement"])
        record = json.loads((self.box / "metrics.jsonl").read_text())
        self.assertEqual(record["usage"], "unknown")
        self.assertGreaterEqual(record["latency_ms"], 0)
        self.assertNotIn("line 1", json.dumps(record))

    def test_direct_ranges_and_unsupported_commands_pass_through(self):
        cases = [self.event(extra={"limit": 400}),
                 self.event(extra={"offset": 1, "limit": 50}),
                 self.event(tool="Bash", extra={"command": "cat a | grep b"}),
                 self.event(tool="Bash", extra={"command": "cat $FILE"})]
        for event in cases:
            with self.subTest(event=event["tool_input"]):
                result = self.run_route(event)
                self.assertIsNone(json.loads(result.stdout)["replacement"])
        self.assertFalse((self.box / "calls").exists())

    def test_simple_cat_and_long_line_route(self):
        cat = self.event(tool="Bash", extra={"command": f"cat {self.source}"})
        self.assertIsNotNone(json.loads(self.run_route(cat).stdout)["replacement"])
        self.source.write_text("x" * 40000)
        self.assertIsNotNone(json.loads(self.run_route(self.event()).stdout)["replacement"])

    def test_powershell_literal_windows_path_is_preserved(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("context_read", CLI)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        event = {"tool_name": "PowerShell", "tool_input": {
            "command": r'Get-Content "C:\Program Files\log.txt"'}}
        self.assertEqual(module.read_path(event), r"C:\Program Files\log.txt")
        event["tool_input"]["command"] = r"Get-Content C:\Temp\log.txt"
        self.assertEqual(module.read_path(event), r"C:\Temp\log.txt")

    def test_reused_gate_fixture_matrix(self):
        small = self.box / "small.txt"
        small.write_text("".join(f"line {n}\n" for n in range(100)))
        edge = self.box / "edge.txt"
        missing = self.box / "missing.txt"
        binary = self.box / "binary.bin"
        binary.write_bytes(b"a\0b")
        directory = self.box / "folder"
        directory.mkdir()
        cases = [(self.event(path=small, response=small.read_text()), False),
                 (self.event(path=missing), False),
                 (self.event(path=binary), False),
                 (self.event(path=directory), False),
                 (self.event(extra={"offset": 1, "limit": 400}), False),
                 (self.event(extra={"limit": 50}), False),
                 (self.event(tool="Bash", extra={"command": f"sed -n '1,400p' {self.source}"}), False),
                 (self.event(tool="Bash", extra={"command": f"head -n 400 {self.source}"}), False),
                 (self.event(tool="Bash", extra={"command": f"cat {self.source}; true"}), False),
                 (self.event(tool="Bash", extra={"command": f"cat {self.source} > out.txt"}), False),
                 (self.event(tool="PowerShell", extra={"command": f"Get-Content {self.source}"}), True),
                 (self.event(tool="PowerShell", extra={"command": f"Get-Content {self.source} -TotalCount 20"}), False),
                 (self.event(tool="Bash", extra={"command": f"cat {self.source}"}), True)]
        for count, expected in ((350, False), (351, True)):
            edge.write_text("x\n" * count)
            cases.append((self.event(path=edge, response=edge.read_text()), expected))
        for event, expected in cases:
            with self.subTest(input=event["tool_input"]):
                self.assertEqual(json.loads(self.run_route(event).stdout)["replacement"] is not None,
                                 expected)
        disabled = dict(self.env, BULK_READ_GATE="off")
        self.assertIsNone(json.loads(self.run_route(self.event(), disabled).stdout)["replacement"])

    def test_worker_failure_falls_back_with_metadata_only(self):
        self.worker.write_text("import sys; sys.exit(7)\n")
        result = self.run_route(self.event())
        self.assertEqual(result.returncode, 0)
        self.assertIsNone(json.loads(result.stdout)["replacement"])
        record = json.loads((self.box / "telemetry.jsonl").read_text().splitlines()[0])
        self.assertEqual(record["category"], "worker_failed")
        self.assertEqual(record["usage"], "unknown")
        self.assertNotIn("line 1", json.dumps(record))

    def test_fenced_json_answer_still_requires_valid_schema(self):
        self.worker.write_text(
            "import json,sys; r=json.load(sys.stdin);"
            "m={'path':r['path'],'sha256':r['sha256'],'claims':[],"
            "'coverage':{'start_line':1,'end_line':400},"
            "'unknowns':[],'incomplete':False};"
            "print('```json\\n'+json.dumps(m)+'\\n```')"
        )
        result = self.run_route(self.event())
        self.assertIsNotNone(json.loads(result.stdout)["replacement"])

    def test_single_coverage_range_is_normalized_and_checked(self):
        self.worker.write_text(
            "import json,sys; r=json.load(sys.stdin);"
            "print(json.dumps({'path':r['path'],'sha256':r['sha256'],"
            "'claims':[{'text':'first','start_line':1,'end_line':1}],"
            "'coverage':{'start_line':1,'end_line':400},"
            "'unknowns':[],'incomplete':False}))"
        )
        result = self.run_route(self.event())
        coverage = json.loads(result.stdout)["replacement"]["coverage"]
        self.assertEqual(coverage, [{"start_line": 1, "end_line": 400}])

    def test_bad_citation_falls_back(self):
        self.worker.write_text("import json,sys; r=json.load(sys.stdin);"
                               "print(json.dumps({'path':r['path'],'sha256':r['sha256'],"
                               "'claims':[{'text':'bad','start_line':999,'end_line':999}],"
                               "'coverage':[],'unknowns':[],'incomplete':False}))")
        result = self.run_route(self.event())
        self.assertIsNone(json.loads(result.stdout)["replacement"])
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "invalid_map")

    def test_failure_matrix_preserves_original_and_logs_metadata(self):
        scenarios = [
            ("missing_worker", None, {"BULK_READ_WORKER_ARGV": json.dumps(["/no/such/worker"])}),
            ("timeout", "import time; time.sleep(3)", {"BULK_READ_TIMEOUT_SECONDS": "1"}),
            ("oversized_or_empty_output", "pass", {}),
            ("invalid_configuration_or_response", "print(\"not-json\")", {}),
            ("oversized_or_empty_output", "print(\"x\" * 20000)", {}),
            ("oversized_input", None, {"BULK_READ_MAX_INPUT_BYTES": "20"}),
        ]
        for expected, script, changes in scenarios:
            with self.subTest(category=expected, script=script):
                (self.box / "telemetry.jsonl").unlink(missing_ok=True)
                self.worker.write_text(script or "print(\"unused\")")
                env = dict(self.env, **changes)
                result = self.run_route(self.event(), env)
                self.assertEqual(result.returncode, 0)
                self.assertIsNone(json.loads(result.stdout)["replacement"])
                record = json.loads((self.box / "telemetry.jsonl").read_text())
                self.assertEqual(record["category"], expected)
                self.assertEqual(record["usage"], "unknown")
                self.assertNotIn("line 1", json.dumps(record))

    def test_crlf_source_hash_matches_exact_bytes(self):
        raw = b"line\r\n" * 400
        self.source.write_bytes(raw)
        result = self.run_route(self.event(response=raw.decode()))
        summary = json.loads(result.stdout)["replacement"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["sha256"], hashlib.sha256(raw).hexdigest())

    def test_source_changed_between_tool_and_hook_falls_back(self):
        original = self.source.read_text()
        self.source.write_text("changed\n" * 400)
        event = self.event(response=original)
        result = self.run_route(event)
        self.assertIsNone(json.loads(result.stdout)["replacement"])
        self.assertFalse((self.box / "calls").exists())
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "changed_source")

    def test_pi_source_changed_between_tool_and_hook_falls_back(self):
        original = self.source.read_text()
        self.source.write_text("changed\n" * 400)
        event = self.event(response=original, tool="read")
        event["harness"] = "pi"
        result = self.run_route(event)
        self.assertIsNone(json.loads(result.stdout)["replacement"])
        self.assertFalse((self.box / "calls").exists())
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "changed_source")

    def test_changed_source_falls_back(self):
        self.worker.write_text(
            "import json,sys,pathlib; r=json.load(sys.stdin);"
            "pathlib.Path(r['path']).write_text('changed');"
            "print(json.dumps({'path':r['path'],'sha256':r['sha256'],"
            "'claims':[],'coverage':[],'unknowns':[],'incomplete':True}))"
        )
        result = self.run_route(self.event())
        self.assertIsNone(json.loads(result.stdout)["replacement"])
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "changed_source")

    def test_missing_cli_hook_falls_back(self):
        event = self.event()
        env = dict(self.env, BULK_READ_CLI=str(self.box / "missing.py"))
        result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event),
                                text=True, capture_output=True, env=env, cwd=ROOT)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "cli_missing")

    def test_real_worker_launch_isolated_and_tool_free(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("context_read", CLI)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for harness in ("claude", "pi"):
            argv = module.worker_argv(harness)
            self.assertIn("--system-prompt", argv)
            self.assertIn("--no-tools" if harness == "pi" else "--tools", argv)
        self.assertIn("--disable", module.worker_argv("codex"))

    def test_pi_worker_selects_last_json_answer(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("context_read", CLI)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        answer = json.dumps({"path": "sample"})
        events = [
            {"type": "message_end", "message": {"role": "assistant",
             "content": [{"type": "text", "text": answer}, {"type": "text", "text": "\n"}]}},
        ]
        selected = module.worker_answer("pi", "\n".join(json.dumps(x) for x in events))
        self.assertEqual(selected, answer)

    def test_claude_worker_returns_after_result_even_if_cli_lingers(self):
        fake = self.box / "claude"
        fake.write_text(
            "#!/usr/bin/env python3\n"
            "import json,sys,time,os,pathlib\n"
            "pathlib.Path(os.environ['WORKER_CWD']).write_text(os.getcwd())\n"
            "r=json.load(sys.stdin); s=r['content']\n"
            "m={'path':r['path'],'sha256':r['sha256'],'claims':[],"
            "'coverage':[{'start_line':1,'end_line':len(s.splitlines())}],"
            "'unknowns':[],'incomplete':False}\n"
            "print(json.dumps({'result':json.dumps(m)}),flush=True);time.sleep(5)\n"
        )
        fake.chmod(0o755)
        env = dict(self.env, PATH=str(self.box) + os.pathsep + os.environ["PATH"],
                   BULK_READ_TIMEOUT_SECONDS="2", WORKER_CWD=str(self.box / "worker-cwd"))
        env.pop("BULK_READ_WORKER_ARGV")
        result = self.run_route(self.event(), env)
        self.assertIsNotNone(json.loads(result.stdout)["replacement"])
        self.assertNotEqual((self.box / "worker-cwd").read_text(), str(ROOT))

    def test_claude_native_read_shape_is_replaced(self):
        event = self.event(response={"type": "text", "file": {
            "filePath": str(self.source), "content": self.source.read_text()}})
        result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event),
                                text=True, capture_output=True, env=self.env, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)["hookSpecificOutput"]["updatedToolOutput"]
        self.assertEqual(output["file"]["filePath"], str(self.source))
        self.assertIn("first line", output["file"]["content"])

    def test_explicit_question_maps_multiple_paths(self):
        second = self.box / "second.txt"
        second.write_text("other\n" * 10)
        result = subprocess.run([sys.executable, str(CLI), "--question", "Find the first line",
                                 str(self.source), str(second)], text=True, capture_output=True,
                                env=self.env, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        maps = json.loads(result.stdout)
        self.assertEqual([item["path"] for item in maps], [str(self.source), str(second)])
        self.assertEqual((self.box / "calls").read_text(), "xx")

    def test_invalid_cli_request_and_missing_path_are_explicit_errors(self):
        malformed = subprocess.run([sys.executable, str(CLI), "--route"], input="not json",
                                   text=True, capture_output=True, env=self.env, cwd=ROOT)
        self.assertEqual(malformed.returncode, 2)
        self.assertIn("invalid route event", malformed.stderr)
        missing = subprocess.run([sys.executable, str(CLI), "--question", "why",
                                  str(self.box / "missing")], text=True, capture_output=True,
                                 env=self.env, cwd=ROOT)
        self.assertEqual(missing.returncode, 1)
        usage = subprocess.run([sys.executable, str(CLI)], text=True, capture_output=True,
                               env=self.env, cwd=ROOT)
        self.assertEqual(usage.returncode, 2)

    def test_claude_bash_object_output_keeps_result_shape(self):
        event = self.event(tool="Bash", extra={"command": f"cat {self.source}"},
                           response={"stdout": self.source.read_text(), "stderr": "", "interrupted": False})
        result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event),
                                text=True, capture_output=True, env=self.env, cwd=ROOT)
        updated = json.loads(result.stdout)["hookSpecificOutput"]["updatedToolOutput"]
        self.assertIn("first line", updated["stdout"])
        self.assertEqual(updated["stderr"], "")
        self.assertFalse(updated["interrupted"])

    def test_hook_disabled_and_malformed_events_pass_through(self):
        disabled = dict(self.env, BULK_READ_GATE="off")
        result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(self.event()),
                                text=True, capture_output=True, env=disabled, cwd=ROOT)
        self.assertEqual(result.stdout, "")
        malformed = subprocess.run([sys.executable, str(HOOK)], input="not json",
                                   text=True, capture_output=True, env=self.env, cwd=ROOT)
        self.assertEqual(malformed.returncode, 0)
        self.assertEqual(malformed.stdout, "")
        self.assertEqual(json.loads((self.box / "telemetry.jsonl").read_text())["category"],
                         "invalid_hook_event")

    def test_hook_emits_claude_and_codex_replacement_shapes(self):
        for harness in ("claude", "codex"):
            event = self.event()
            event["harness"] = harness
            result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event),
                                    text=True, capture_output=True, env=self.env, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            if harness == "claude":
                self.assertIn("updatedToolOutput", output["hookSpecificOutput"])
            else:
                self.assertEqual(output["decision"], "block")
                self.assertIn("first line", output["reason"])


if __name__ == "__main__":
    unittest.main()
