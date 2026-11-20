import datetime
import gzip
import importlib.util
import json
import pathlib
import sqlite3
import tempfile
from unittest import mock
spec=importlib.util.spec_from_file_location('retention',pathlib.Path(__file__).with_name('retention.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as folder:
    root=pathlib.Path(folder);logs=root/'logs';logs.mkdir();db=root/'store.db'
    c=sqlite3.connect(db);now=1800000000000;day=86400000
    c.executescript('CREATE TABLE sdk_sessions(id INTEGER PRIMARY KEY,user_prompt TEXT,started_at_epoch INTEGER); CREATE TABLE user_prompts(id INTEGER PRIMARY KEY,prompt_text TEXT,created_at_epoch INTEGER); CREATE TABLE pending_messages(id INTEGER PRIMARY KEY,status TEXT,tool_input TEXT,tool_response TEXT,last_user_message TEXT,last_assistant_message TEXT,failed_at_epoch INTEGER,completed_at_epoch INTEGER,created_at_epoch INTEGER);')
    c.executemany('INSERT INTO sdk_sessions VALUES(?,?,?)',[(1,'synthetic expired',now-91*day),(2,'synthetic boundary',now-90*day)])
    c.executemany('INSERT INTO user_prompts VALUES(?,?,?)',[(1,'synthetic expired',now-91*day),(2,'synthetic boundary',now-90*day)])
    c.executemany('INSERT INTO pending_messages VALUES(?,?,?,NULL,NULL,NULL,?,NULL,?)',[(1,'failed','old',now-8*day,now-9*day),(2,'pending','keep',None,now-8*day),(3,'processing','keep',None,now-8*day),(4,'failed','boundary',now-7*day,now-9*day),(5,'failed','recent failure',now-1*day,now-99*day)])
    c.commit();c.close()
    date=datetime.datetime.fromtimestamp(now/1000,datetime.timezone.utc)
    old=logs/f'claude-mem-{(date-datetime.timedelta(days=31)).date()}.log';old.write_text('synthetic log')
    boundary=logs/f'claude-mem-{(date-datetime.timedelta(days=30)).date()}.log';boundary.write_text('keep')
    original_archive=m.archived_bytes
    calls=0
    def fail_second_archive(path,chunks):
        global calls
        calls+=1
        if calls==2:raise OSError('synthetic archive failure')
        return original_archive(path,chunks)
    m.archived_bytes=fail_second_archive
    try:
        m.maintain(db,logs,root/'archives',now)
        raise AssertionError('archive failure must propagate')
    except OSError:
        c=sqlite3.connect(db)
        assert c.execute('SELECT tool_input FROM pending_messages WHERE id=1').fetchone()==('old',)
        assert c.execute('SELECT user_prompt FROM sdk_sessions WHERE id=1').fetchone()==('synthetic expired',)
        c.close()
        assert old.exists()
    finally:m.archived_bytes=original_archive
    real_stat=pathlib.Path.stat
    checks=0
    late=b'\nsynthetic append after final stat\n'
    def append_after_final_stat(path,*args,**kwargs):
        global checks
        result=real_stat(path,*args,**kwargs)
        if path==old:
            checks+=1
            if checks==2:
                with old.open('ab') as stream:stream.write(late)
        return result
    with old.open('ab') as writer:
        with mock.patch.object(pathlib.Path,'stat',append_after_final_stat):
            report=m.maintain(db,logs,root/'archives',now)
        writer.write(b'synthetic open-descriptor append after rotation\n')
        writer.flush()
    assert any(late in path.read_bytes() for path in logs.rglob('*.log')), 'F5: final concurrent append was lost from both source and retained raw logs'

    c=sqlite3.connect(db)
    assert c.execute('SELECT user_prompt FROM sdk_sessions WHERE id=1').fetchone()==(None,)
    assert c.execute('SELECT count(*) FROM user_prompts').fetchone()==(1,)
    assert c.execute('SELECT tool_input FROM pending_messages ORDER BY id').fetchall()==[(None,),('keep',),('keep',),('boundary',),('recent failure',)]
    assert not old.exists() and boundary.exists()
    assert report['log_bytes_reclaimed']==0
    retained=list((logs/'retained').rglob('*.log'))
    assert len(retained)==1 and b'synthetic open-descriptor append after rotation' in retained[0].read_bytes()
    archives=list((root/'archives').glob('*/prompt_rows.jsonl.gz'))
    recovered=[json.loads(line) for line in gzip.open(archives[0],'rt')]
    assert recovered[0]['row']['prompt_text']=='synthetic expired'
    again=m.maintain(db,logs,root/'archives',now)
    assert again['counts']==dict(failed=0,session_prompts=0,prompt_rows=0)
    assert again['logs']==0
    print('PASS: expiry boundaries, failed-at age, pending/processing preservation, archive recovery, failure rollback and idempotence')
