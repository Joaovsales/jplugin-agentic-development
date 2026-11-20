#!/usr/bin/env python3
"""Archive expired raw memory payloads before clearing them; retain durable memories."""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import tempfile


def archived_bytes(path, chunks):
    """Write and fsync a gzip archive, then verify every uncompressed byte."""
    expected = hashlib.sha256()
    with path.open('xb') as raw:
        os.chmod(path, 0o600)
        with gzip.GzipFile(fileobj=raw, mode='wb') as zipped:
            for chunk in chunks:
                expected.update(chunk)
                zipped.write(chunk)
        raw.flush()
        os.fsync(raw.fileno())
    actual = hashlib.sha256()
    with gzip.open(path, 'rb') as restored:
        for chunk in iter(lambda: restored.read(1024 * 1024), b''):
            actual.update(chunk)
    if actual.digest() != expected.digest():
        raise RuntimeError('Archive verification failed; original data retained')
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    return expected.hexdigest()


def maintain(database, logs, archives, now_ms):
    if not database.is_file() or not logs.is_dir():
        raise RuntimeError('Expected database or log directory is missing')
    archives.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory = os.open(archives.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    run = Path(tempfile.mkdtemp(prefix='run-', dir=archives))
    directory = os.open(archives, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    now = datetime.datetime.fromtimestamp(now_ms / 1000, datetime.timezone.utc)
    days = 86400000
    plans = [
        ('failed', 'pending_messages', 'id,tool_input,tool_response,last_user_message,last_assistant_message',
         "status='failed' AND coalesce(failed_at_epoch,completed_at_epoch,created_at_epoch) < ? AND (tool_input IS NOT NULL OR tool_response IS NOT NULL OR last_user_message IS NOT NULL OR last_assistant_message IS NOT NULL)",
         now_ms - 7 * days,
         'UPDATE pending_messages SET tool_input=NULL,tool_response=NULL,last_user_message=NULL,last_assistant_message=NULL'),
        ('session_prompts', 'sdk_sessions', 'id,user_prompt',
         'started_at_epoch < ? AND user_prompt IS NOT NULL', now_ms - 90 * days,
         'UPDATE sdk_sessions SET user_prompt=NULL'),
        ('prompt_rows', 'user_prompts', '*', 'created_at_epoch < ?', now_ms - 90 * days,
         'DELETE FROM user_prompts'),
    ]
    report = dict(utc=now.isoformat(),payload_bytes=0,counts={},archives=[],logs=0,log_bytes=0)
    conn = sqlite3.connect(database, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute('PRAGMA foreign_keys=ON')
        conn.execute('BEGIN IMMEDIATE')
        for label, table, columns, where, cutoff, mutation in plans:
            count = 0
            raw_bytes = 0
            def chunks():
                nonlocal count, raw_bytes
                cursor = conn.execute(f'SELECT {columns} FROM {table} WHERE {where}', (cutoff,))
                for row in cursor:
                    value = dict(row)
                    count += 1
                    fields = ['tool_input','tool_response','last_user_message','last_assistant_message'] if label == 'failed' else ['user_prompt'] if label == 'session_prompts' else ['prompt_text']
                    raw_bytes += sum(len(value.get(k, '').encode()) for k in fields if value.get(k) is not None)
                    yield (json.dumps(dict(table=table, row=value), ensure_ascii=False)+'\n').encode()
            archive = run / (label + '.jsonl.gz')
            sha = archived_bytes(archive, chunks())
            conn.execute(mutation + ' WHERE ' + where, (cutoff,))
            report['counts'][label] = count
            report['payload_bytes'] += raw_bytes
            report['archives'].append(dict(kind=label,sha256=sha,bytes=archive.stat().st_size,payload_bytes=raw_bytes))
        conn.commit()
    finally:
        conn.close()
    cutoff_date = (now - datetime.timedelta(days=30)).date().isoformat()
    for original in sorted(logs.glob('claude-mem-*.log')):
        match = re.fullmatch(r'claude-mem-(\d{4}-\d{2}-\d{2})\.log', original.name)
        if not match or match[1] >= cutoff_date:
            continue
        before = original.stat()
        if before.st_mtime * 1000 >= now_ms - 30 * days:
            continue
        with original.open('rb') as stream:
            sha = archived_bytes(run / (original.name + '.gz'), iter(lambda: stream.read(1024 * 1024), b''))
        after = original.stat()
        if (before.st_ino,before.st_size,before.st_mtime_ns) != (after.st_ino,after.st_size,after.st_mtime_ns):
            raise RuntimeError('Log changed during archival; original retained')
        original.unlink()
        report['logs'] += 1
        report['log_bytes'] += before.st_size
    (run/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=Path.home()/'.claude-mem/claude-mem.db')
    parser.add_argument('--logs', type=Path, default=Path.home()/'.claude-mem/logs')
    parser.add_argument('--archives', type=Path, default=Path.home()/'.local/state/claude-mem-retention/archives')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = maintain(args.database,args.logs,args.archives,int(datetime.datetime.now(datetime.timezone.utc).timestamp()*1000))
        args.report.write_text(json.dumps(report,indent=2)+'\n')
    except Exception as error:
        import sys
        print(json.dumps(dict(error=type(error).__name__,message=str(error))),file=sys.stderr)
        sys.exit(1)
