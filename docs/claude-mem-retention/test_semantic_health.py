import contextlib
import datetime
import http.server
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock
import urllib.parse

MODULE = Path(__file__).with_name('semantic_health.py')
spec = importlib.util.spec_from_file_location('semantic_health', MODULE)
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class SemanticHealthTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.logs = self.root / 'logs'
        self.logs.mkdir()
        self.log = self.logs / 'claude-mem-2026-11-20.log'
        self.state = self.root / 'state.json'
        self.probe = self.root / 'probe.json'
        self.probe.write_text(json.dumps({'query': 'private query must never be logged'}))
        self.status = 200
        self.results = [{'id': 1}]
        self.error = 'MCP error -32000: Connection closed'
        self.request_params = None
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/api/health':
                    status, body = 200, {'status': 'ok', 'pid': 123}
                else:
                    outer.request_params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                    status = outer.status
                    body = {'observations': outer.results} if status == 200 else {'error': outer.error}
                self.send_response(status)
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(('localhost', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.started = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=40)
        (self.root / 'worker.pid').write_text(json.dumps({'pid': 123, 'port': self.server.server_port, 'startedAt': self.started.isoformat()}))
        self.append('CHROMA_MCP', 'Connected to chroma-mcp successfully', self.started + datetime.timedelta(seconds=1))

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def append(self, tag, message, when=None):
        when = when or datetime.datetime.now(datetime.timezone.utc)
        timestamp = when.astimezone().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        with self.log.open('a') as stream:
            stream.write(f'[{timestamp}] [INFO ] [{tag}] {message}\n')

    def check(self):
        health.check(self.root, self.probe, self.state)

    def test_healthy_long_lived_connection_is_silent(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.check()
        self.assertEqual((out.getvalue(), err.getvalue()), ('', ''))
        self.assertEqual(json.loads(self.state.read_text())['semantic_result_count'], 1)
        self.assertEqual(self.request_params['dateStart'], ['1970-01-01'])

    def test_healthy_cli_returns_zero_without_output(self):
        out, err = io.StringIO(), io.StringIO()
        args = ['semantic_health.py', '--data-dir', str(self.root), '--probe-file', str(self.probe), '--state-file', str(self.state)]
        with mock.patch.object(sys, 'argv', args), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = health.main()
        self.assertEqual((status, out.getvalue(), err.getvalue()), (0, '', ''))

    def test_bridge_failure_is_actionable_and_private(self):
        self.status = 500
        result = subprocess.run([sys.executable, str(MODULE), '--data-dir', str(self.root), '--probe-file', str(self.probe), '--state-file', str(self.state)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('Chroma MCP connection closed', result.stderr)
        self.assertIn('chroma-mcp.requirements.txt', result.stderr)
        self.assertNotIn('private query', result.stderr)

    def test_new_failure_is_reported_once_even_after_reconnect(self):
        self.check()
        state = json.loads(self.state.read_text())
        state['checked_at'] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=1)).isoformat()
        self.state.write_text(json.dumps(state))
        self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie')
        with self.assertRaisesRegex(health.ProbeFailure, 'new connection failure'):
            self.check()
        self.check()

    def test_missing_current_daemon_connection_fails(self):
        self.log.write_text('')
        with self.assertRaisesRegex(health.ProbeFailure, 'No successful Chroma MCP connection'):
            self.check()

    def test_rotation_keeps_attestation_for_same_worker_only(self):
        self.check()
        self.log.unlink()
        self.check()
        worker = json.loads((self.root / 'worker.pid').read_text())
        worker['startedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (self.root / 'worker.pid').write_text(json.dumps(worker))
        with self.assertRaisesRegex(health.ProbeFailure, 'No successful Chroma MCP connection'):
            self.check()

    def test_failure_arriving_after_log_scan_is_not_lost(self):
        self.check()
        original = health.connection_events
        def scan_then_append(logs):
            events = original(logs)
            self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie')
            return events
        with mock.patch.object(health, 'connection_events', scan_then_append):
            self.check()
        with self.assertRaisesRegex(health.ProbeFailure, 'new connection failure'):
            self.check()
        self.check()

    def test_restart_transient_is_retried_without_output(self):
        attempts = [health.ProbeFailure('Restart in progress', retryable=True), None]
        with mock.patch.object(health, 'check', side_effect=attempts) as probe, mock.patch.object(health.time, 'sleep') as sleep:
            health.check_with_retry(self.root, self.probe, self.state)
        self.assertEqual(probe.call_count, 2)
        sleep.assert_called_once_with(2)

    def test_retry_exhaustion_is_bounded(self):
        with mock.patch.object(health, 'check', side_effect=health.ProbeFailure('Unavailable', retryable=True)) as probe, mock.patch.object(health.time, 'sleep') as sleep:
            with self.assertRaises(health.ProbeFailure):
                health.check_with_retry(self.root, self.probe, self.state)
        self.assertEqual(probe.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_restart_http_gap_recovers_silently(self):
        original = health.request
        calls = 0
        def starting(port, path, params=None):
            nonlocal calls
            calls += 1
            if calls == 1:
                return 503, {}
            return original(port, path, params)
        with mock.patch.object(health, 'request', side_effect=starting), mock.patch.object(health.time, 'sleep'):
            health.check_with_retry(self.root, self.probe, self.state)
        self.assertEqual(calls, 3)

    def test_missing_log_directory_fails_explicitly(self):
        self.check()
        self.log.unlink()
        self.logs.rmdir()
        with self.assertRaisesRegex(health.ProbeFailure, 'log directory is missing'):
            self.check()

    def test_clock_moves_back_without_alarm_or_missing_new_failure(self):
        self.check()
        real_datetime = datetime.datetime
        shifted = real_datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)
        class BackwardClock(real_datetime):
            @classmethod
            def now(cls, tz=None):
                return shifted.astimezone(tz)
        with mock.patch.object(health.datetime, 'datetime', BackwardClock):
            self.check()
            self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie', shifted)
            with self.assertRaisesRegex(health.ProbeFailure, 'new connection failure'):
                self.check()
            self.check()
        self.check()

    def test_restart_marker_after_clock_step_uses_identity_not_time(self):
        self.check()
        worker = json.loads((self.root / 'worker.pid').read_text())
        now = datetime.datetime.now(datetime.timezone.utc)
        worker['startedAt'] = now.isoformat()
        (self.root / 'worker.pid').write_text(json.dumps(worker))
        self.append('CHROMA_MCP', 'Connected to chroma-mcp successfully', now - datetime.timedelta(hours=2))
        self.check()

    def test_rotation_after_scan_retains_and_reports_late_events(self):
        self.check()
        original = health.connection_events
        retained = self.logs / 'retained' / 'synthetic'
        retained.mkdir(parents=True)
        def scan_then_rotate(logs):
            events = original(logs)
            self.log.rename(retained / self.log.name)
            self.log = retained / self.log.name
            self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie')
            return events
        with mock.patch.object(health, 'connection_events', scan_then_rotate):
            self.check()
        with self.assertRaisesRegex(health.ProbeFailure, 'new connection failure'):
            self.check()
        self.check()

    def test_rotation_between_inventory_and_open_retries_without_checkpoint(self):
        self.check()
        previous = self.state.read_bytes()
        original = health.log_inventory
        retained = self.logs / 'retained' / 'synthetic'
        retained.mkdir(parents=True)
        def rotated(logs):
            inventory = original(logs)
            if self.log.parent == self.logs:
                target = retained / self.log.name
                self.log.rename(target)
                self.log = target
            return inventory
        with mock.patch.object(health, 'log_inventory', rotated):
            with self.assertRaisesRegex(health.ProbeFailure, 'rotated') as raised:
                self.check()
            self.assertTrue(raised.exception.retryable)
        self.assertEqual(self.state.read_bytes(), previous)
        self.check()

    def test_identical_failure_lines_at_different_offsets_are_new_events(self):
        self.check()
        when = datetime.datetime.now(datetime.timezone.utc)
        for _ in range(2):
            self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie', when)
            with self.assertRaisesRegex(health.ProbeFailure, '1 new connection failure'):
                self.check()
        self.check()

    def test_partial_final_line_is_counted_only_when_complete(self):
        self.check()
        when = datetime.datetime.now(datetime.timezone.utc).astimezone().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        with self.log.open('a') as stream:
            stream.write(f'[{when}] [ERROR] [CHROMA_MCP] Connection failed, killing subprocess')
        self.check()
        with self.log.open('a') as stream:
            stream.write(' to prevent zombie\n')
        with self.assertRaisesRegex(health.ProbeFailure, '1 new connection failure'):
            self.check()
        self.check()

    def test_append_while_reading_waits_for_next_snapshot_without_alarm(self):
        self.check()
        original = Path.open
        appended = False
        @contextlib.contextmanager
        def opening(path, *args, **kwargs):
            nonlocal appended
            with original(path, *args, **kwargs) as stream:
                if path == self.log and args == ('rb',):
                    reader = mock.Mock(wraps=stream)
                    def readline(limit):
                        nonlocal appended
                        line = stream.readline(limit)
                        if not appended:
                            appended = True
                            self.append('CHROMA_MCP', 'Connection failed, killing subprocess to prevent zombie')
                        return line
                    reader.readline.side_effect = readline
                    yield reader
                else:
                    yield stream
        with mock.patch.object(Path, 'open', opening):
            self.check()
        with self.assertRaisesRegex(health.ProbeFailure, '1 new connection failure'):
            self.check()
        self.check()

    def test_truncation_during_read_is_loud_and_does_not_advance_checkpoint(self):
        self.check()
        previous = self.state.read_bytes()
        original = Path.open
        @contextlib.contextmanager
        def opening(path, *args, **kwargs):
            with original(path, *args, **kwargs) as stream:
                if path == self.log and args == ('rb',):
                    reader = mock.Mock(wraps=stream)
                    def readline(limit):
                        self.log.write_bytes(b'')
                        return stream.readline(limit)
                    reader.readline.side_effect = readline
                    yield reader
                else:
                    yield stream
        with mock.patch.object(Path, 'open', opening):
            with self.assertRaisesRegex(health.ProbeFailure, 'truncated') as raised:
                self.check()
            self.assertTrue(raised.exception.retryable)
        self.assertEqual(self.state.read_bytes(), previous)
        self.append('CHROMA_MCP', 'Connected to chroma-mcp successfully', self.started + datetime.timedelta(seconds=1))
        self.check()

    def test_recorded_failure_is_never_retried_away(self):
        with mock.patch.object(health, 'check', side_effect=health.ProbeFailure('new connection failure')) as probe, mock.patch.object(health.time, 'sleep') as sleep:
            with self.assertRaises(health.ProbeFailure):
                health.check_with_retry(self.root, self.probe, self.state)
        self.assertEqual(probe.call_count, 1)
        sleep.assert_not_called()

    def test_prompt_text_is_not_a_connection_marker(self):
        self.log.write_text('')
        self.append('HOOK', 'Bash(Connected to chroma-mcp successfully)')
        with self.assertRaises(health.ProbeFailure):
            self.check()

    def test_empty_results_and_empty_query_fail(self):
        self.results = []
        with self.assertRaisesRegex(health.ProbeFailure, 'no observations'):
            self.check()
        self.probe.write_text('{"query":""}')
        with self.assertRaisesRegex(health.ProbeFailure, 'nonempty query'):
            self.check()
        self.probe.write_text('[]')
        with self.assertRaisesRegex(health.ProbeFailure, 'nonempty query'):
            self.check()

    def test_corrupt_checkpoint_does_not_reset_failure_window(self):
        self.state.write_text('broken')
        with self.assertRaisesRegex(health.ProbeFailure, 'checkpoint'):
            self.check()
        self.state.write_text('{"checked_at":0}')
        with self.assertRaisesRegex(health.ProbeFailure, 'checkpoint'):
            self.check()

    def test_unrelated_backend_failure_is_also_loud_and_private(self):
        self.status = 503
        self.error = 'sensitive backend detail that must not be logged'
        with self.assertRaisesRegex(health.ProbeFailure, 'Semantic query failed') as raised:
            self.check()
        self.assertNotIn(self.error, str(raised.exception))


if __name__ == '__main__':
    unittest.main()
