#!/usr/bin/env python3
"""Verify claude-mem semantic search; healthy runs produce no output."""
import argparse
import datetime
import http.client
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
import urllib.parse


ACTION = ('Inspect local worker/vector-backend logs and plugin configuration, then restart normally. '
          'For the MCP/Pydantic compatibility failure, check uvx --python 3.13 chroma-mcp --help '
          'and restore the isolated tool using chroma-mcp.requirements.txt. '
          'For missing log evidence, check CLAUDE_MEM_LOG_LEVEL=INFO.')
LOG_LINE = re.compile(r'^\[([^]]+)\] \[[A-Z ]+\] \[([^]]+)\] (.*)')


class ProbeFailure(Exception):
    def __init__(self, message, retryable=False):
        super().__init__(message)
        self.retryable = retryable


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('Timestamp must be a string')
    result = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('Timezone required')
    return result


def request(port, path, params=None):
    if params:
        path += '?' + urllib.parse.urlencode(params)
    connection = http.client.HTTPConnection('localhost', port, timeout=30)
    try:
        connection.request('GET', path)
        response = connection.getresponse()
        body = response.read(1024 * 1024 + 1)
        if len(body) > 1024 * 1024:
            raise ProbeFailure('Semantic API response exceeded the probe limit')
        return response.status, json.loads(body)
    except (OSError, http.client.HTTPException, ValueError):
        raise ProbeFailure('Worker API is unreachable or returned invalid JSON', retryable=True) from None
    finally:
        connection.close()


def log_inventory(logs):
    inventory = {}
    for path in sorted(logs.rglob('claude-mem-*.log')):
        stat = path.stat()
        inventory[path] = (stat.st_dev, stat.st_ino)
    return inventory


def connection_events(logs):
    if not logs.is_dir():
        raise ProbeFailure('Worker log directory is missing; connection failures cannot be checked', retryable=True)
    successes, failures = [], []
    inventory = log_inventory(logs)
    for path, identity in inventory.items():
        with path.open('rb') as stream:
            before = os.fstat(stream.fileno())
            if (before.st_dev, before.st_ino) != identity:
                raise ProbeFailure('Worker log rotated before reading; retrying snapshot', retryable=True)
            # The producer appends only. Read its fixed prefix; late appends wait for the next scan.
            remaining = before.st_size
            while remaining:
                offset = stream.tell()
                raw_line = stream.readline(remaining)
                if not raw_line:
                    raise ProbeFailure('Worker log truncated during reading; retrying snapshot', retryable=True)
                remaining -= len(raw_line)
                if not raw_line.endswith(b'\n'):
                    continue
                match = LOG_LINE.match(raw_line.decode(errors='replace'))
                if not match:
                    continue
                text_time, tag, message = match.groups()
                tag = tag.strip()
                success = tag == 'CHROMA_MCP' and message.strip() == 'Connected to chroma-mcp successfully'
                failure = ((tag == 'CHROMA_MCP' and message.startswith('Connection failed, killing subprocess'))
                           or (tag == 'WORKER' and 'Request failed chroma-mcp connection in backoff' in message))
                if not success and not failure:
                    continue
                try:
                    when = datetime.datetime.strptime(text_time, '%Y-%m-%d %H:%M:%S.%f').astimezone(datetime.timezone.utc)
                except ValueError:
                    raise ProbeFailure('Connection log timestamp is unrecognized; inspect the local worker logs') from None
                event = f'{identity[0]}:{identity[1]}:{offset}:'.encode() + raw_line
                event_id = hashlib.sha256(event).hexdigest()
                (successes if success else failures).append((when, event_id))
            after = os.fstat(stream.fileno())
            if after.st_size < before.st_size or (after.st_size == before.st_size and after.st_mtime_ns != before.st_mtime_ns):
                raise ProbeFailure('Worker log rewritten during reading; retrying snapshot', retryable=True)
    if log_inventory(logs) != inventory:
        raise ProbeFailure('Worker log rotation changed the scan inventory; retrying snapshot', retryable=True)
    return successes, failures


def checkpoint(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.semantic-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def check(data_dir, probe_file, state_file):
    begin = datetime.datetime.now(datetime.timezone.utc)
    try:
        probe = json.loads(probe_file.read_text())
    except (OSError, ValueError):
        raise ProbeFailure('Private probe configuration is missing or invalid') from None
    try:
        worker = json.loads((data_dir / 'worker.pid').read_text())
        started = timestamp(worker['startedAt'])
        port = int(worker['port'])
    except (OSError, ValueError, KeyError, TypeError):
        raise ProbeFailure('Worker metadata is missing or invalid; a restart may be in progress', retryable=True) from None
    if not isinstance(probe, dict) or not isinstance(probe.get('query'), str) or not probe['query'].strip():
        raise ProbeFailure('Private probe configuration requires a nonempty query')
    saved = {}
    if state_file.exists():
        try:
            saved = json.loads(state_file.read_text())
            timestamp(saved['checked_at'])
            if saved.get('event_checkpoint_version') not in (None, 2):
                raise ValueError('Unknown event checkpoint version')
            for field in ('failure_event_ids', 'connection_event_ids'):
                if not isinstance(saved.get(field, []), list) or not all(
                        isinstance(event, str) and re.fullmatch(r'[0-9a-f]{64}', event)
                        for event in saved.get(field, [])):
                    raise ValueError('Invalid event checkpoint')
        except (OSError, ValueError, KeyError, TypeError):
            raise ProbeFailure('Monitor checkpoint is invalid; inspect its private backup') from None
    if saved.get('event_checkpoint_version') == 2:
        seen = set(saved.get('failure_event_ids', []))
    else:
        # Legacy state lacks a complete identity inventory. Bootstrap before the real probe.
        try:
            _, baseline = connection_events(data_dir / 'logs')
        except FileNotFoundError:
            raise ProbeFailure('Worker logs rotated during baseline; retrying snapshot', retryable=True) from None
        seen = {event for _, event in baseline}
    status, healthy = request(port, '/api/health')
    if status != 200 or not isinstance(healthy, dict) or healthy.get('status') != 'ok' or healthy.get('pid') != worker.get('pid'):
        raise ProbeFailure('Worker health or identity check failed; restart claude-mem normally', retryable=True)
    status, result = request(port, '/api/search', dict(query=probe['query'], type='observations', format='json', limit='1', dateStart='1970-01-01'))
    problems = []
    observations = result.get('observations', []) if isinstance(result, dict) else []
    if status != 200:
        error = str(result.get('error', '')) if isinstance(result, dict) else ''
        cause = 'Chroma MCP connection closed or in backoff' if 'Connection closed' in error or 'connection in backoff' in error else 'Semantic query failed'
        problems.append(f'{cause} (HTTP {status}); worker health alone did not detect it')
    elif not isinstance(observations, list) or not observations or not all(isinstance(row, dict) and isinstance(row.get('id'), int) for row in observations):
        problems.append('Semantic query returned no observations for the private known-result query')
    try:
        successes, failures = connection_events(data_dir / 'logs')
    except FileNotFoundError:
        raise ProbeFailure('Worker logs rotated during the scan; retrying connection evidence', retryable=True) from None
    if saved.get('event_checkpoint_version') == 2:
        seen_connections = set(saved.get('connection_event_ids', []))
        current_connections = [when for when, event in successes if event not in seen_connections]
    else:
        current_connections = [when for when, _ in successes if when >= started]
    identity = dict(pid=worker.get('pid'), started_at=started.isoformat(), port=port)
    cached = saved.get('successful_connection_at')
    if cached and saved.get('worker') == identity:
        try:
            attested = timestamp(cached)
        except (ValueError, TypeError):
            raise ProbeFailure('Monitor connection attestation is invalid') from None
        current_connections.append(attested)
    new_failures = sum(event not in seen for _, event in failures)
    if not current_connections:
        problems.append('No successful Chroma MCP connection marker in the current daemon lifetime')
    if new_failures:
        problems.append(f'{new_failures} new connection failure events since the previous probe')
    checkpoint(state_file, dict(checked_at=begin.isoformat(),
                                event_checkpoint_version=2,
                                worker=identity,
                                failure_event_ids=[event for _, event in failures],
                                connection_event_ids=[event for _, event in successes],
                                successful_connection_at=max(current_connections).isoformat() if current_connections else None,
                                failure_events_since_previous=new_failures,
                                semantic_result_count=len(observations) if isinstance(observations, list) else 0))
    if problems:
        raise ProbeFailure('; '.join(problems), retryable=not new_failures)


def check_with_retry(data_dir, probe_file, state_file):
    for attempt in range(3):
        try:
            check(data_dir, probe_file, state_file)
            return
        except ProbeFailure as error:
            if not error.retryable or attempt == 2:
                raise
            time.sleep(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=Path.home() / '.claude-mem')
    parser.add_argument('--probe-file', type=Path, default=Path.home() / '.local/state/claude-mem-retention/semantic-probe.json')
    parser.add_argument('--state-file', type=Path, default=Path.home() / '.local/state/claude-mem-retention/semantic-health.json')
    args = parser.parse_args()
    try:
        check_with_retry(args.data_dir, args.probe_file, args.state_file)
    except (ProbeFailure, OSError) as error:
        reason = str(error) if isinstance(error, ProbeFailure) else 'Monitor could not read logs or persist its checkpoint'
        print(json.dumps(dict(event='claude_mem_semantic_probe_failed', reason=reason, action=ACTION)), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
