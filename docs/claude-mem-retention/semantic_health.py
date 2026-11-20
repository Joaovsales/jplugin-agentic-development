#!/usr/bin/env python3
"""Verify claude-mem semantic search; healthy runs produce no output."""
import argparse
import datetime
import http.client
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import urllib.parse


ACTION = ('Inspect local worker/vector-backend logs and plugin configuration, then restart normally. '
          'For the MCP/Pydantic compatibility failure, check uvx --python 3.13 chroma-mcp --help '
          'and restore the isolated tool using chroma-mcp.requirements.txt. '
          'For missing log evidence, check CLAUDE_MEM_LOG_LEVEL=INFO.')
LOG_LINE = re.compile(r'^\[([^]]+)\] \[[A-Z ]+\] \[([^]]+)\] (.*)')


class ProbeFailure(Exception):
    pass


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
        raise ProbeFailure('Worker API is unreachable or returned invalid JSON') from None
    finally:
        connection.close()


def connection_events(logs):
    successes, failures = [], []
    for path in sorted(logs.glob('claude-mem-*.log')):
        with path.open(errors='replace') as stream:
            for line in stream:
                match = LOG_LINE.match(line)
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
                (successes if success else failures).append(when)
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
        worker = json.loads((data_dir / 'worker.pid').read_text())
        started = timestamp(worker['startedAt'])
        port = int(worker['port'])
    except (OSError, ValueError, KeyError, TypeError):
        raise ProbeFailure('Private probe configuration or worker metadata is missing or invalid') from None
    if not isinstance(probe, dict) or not isinstance(probe.get('query'), str) or not probe['query'].strip():
        raise ProbeFailure('Private probe configuration requires a nonempty query')
    previous = begin
    if state_file.exists():
        try:
            previous = timestamp(json.loads(state_file.read_text())['checked_at'])
            if previous > begin:
                raise ValueError('Clock moved backwards')
        except (OSError, ValueError, KeyError, TypeError):
            raise ProbeFailure('Monitor checkpoint is invalid; inspect its backup and the system clock') from None
    status, healthy = request(port, '/api/health')
    if status != 200 or not isinstance(healthy, dict) or healthy.get('status') != 'ok' or healthy.get('pid') != worker.get('pid'):
        raise ProbeFailure('Worker health or identity check failed; restart claude-mem normally')
    status, result = request(port, '/api/search', dict(query=probe['query'], type='observations', format='json', limit='1', dateStart='1970-01-01'))
    problems = []
    observations = result.get('observations', []) if isinstance(result, dict) else []
    if status != 200:
        error = str(result.get('error', '')) if isinstance(result, dict) else ''
        cause = 'Chroma MCP connection closed or in backoff' if 'Connection closed' in error or 'connection in backoff' in error else 'Semantic query failed'
        problems.append(f'{cause} (HTTP {status}); worker health alone did not detect it')
    elif not isinstance(observations, list) or not observations or not all(isinstance(row, dict) and isinstance(row.get('id'), int) for row in observations):
        problems.append('Semantic query returned no observations for the private known-result query')
    successes, failures = connection_events(data_dir / 'logs')
    current_connections = [when for when in successes if when >= started]
    new_failures = sum(when > previous for when in failures)
    if not current_connections:
        problems.append('No successful Chroma MCP connection marker in the current daemon lifetime')
    if new_failures:
        problems.append(f'{new_failures} new connection failure events since the previous probe')
    checkpoint(state_file, dict(checked_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                successful_connection_at=max(current_connections).isoformat() if current_connections else None,
                                failure_events_since_previous=new_failures,
                                semantic_result_count=len(observations) if isinstance(observations, list) else 0))
    if problems:
        raise ProbeFailure('; '.join(problems))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=Path.home() / '.claude-mem')
    parser.add_argument('--probe-file', type=Path, default=Path.home() / '.local/state/claude-mem-retention/semantic-probe.json')
    parser.add_argument('--state-file', type=Path, default=Path.home() / '.local/state/claude-mem-retention/semantic-health.json')
    args = parser.parse_args()
    try:
        check(args.data_dir, args.probe_file, args.state_file)
    except (ProbeFailure, OSError) as error:
        reason = str(error) if isinstance(error, ProbeFailure) else 'Monitor could not read logs or persist its checkpoint'
        print(json.dumps(dict(event='claude_mem_semantic_probe_failed', reason=reason, action=ACTION)), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
