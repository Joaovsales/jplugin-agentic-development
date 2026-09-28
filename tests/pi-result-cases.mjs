import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import bulkReadGate from '../pi/extensions/bulk-read-gate.ts';

const box = mkdtempSync(join(tmpdir(), 'pi-result-'));
const source = join(box, 'large.txt');
writeFileSync(source, Array.from({length: 400}, (_, i) => `line ${i + 1}\n`).join(''));
const worker = join(box, 'worker.py');
writeFileSync(worker, `import json,os,sys
from pathlib import Path
r=json.load(sys.stdin); Path(os.environ['CALLS']).open('a').write('x')
s=r['content']; print(json.dumps({'path':r['path'],'sha256':r['sha256'],'claims':[{'text':'first line','start_line':1,'end_line':1}],'coverage':[{'start_line':1,'end_line':len(s.splitlines())}],'unknowns':[],'incomplete':False}))
`);
process.env.BULK_READ_WORKER_ARGV = JSON.stringify(['python3', worker]);
process.env.BULK_READ_TELEMETRY = join(box, 'telemetry.jsonl');
process.env.CALLS = join(box, 'calls');
let handler;
bulkReadGate({ on(name, fn) { if (name === 'tool_result') handler = fn; } });
assert.equal(typeof handler, 'function');
const event = (id, input, content, error = false) => ({
  toolName: 'read', toolCallId: id, input, content: [{type:'text', text:content}], isError:error,
});
const large = readFileSync(source, 'utf8');
const replaced = await handler(event('one', {path:source}, large));
assert.match(replaced.content[0].text, /first line/);
assert.equal(readFileSync(process.env.CALLS, 'utf8'), 'x');
const shell = {...event('shell', {command:`cat ${source}`}, large), toolName:'bash'};
assert.match((await handler(shell)).content[0].text, /first line/);
assert.equal(readFileSync(process.env.CALLS, 'utf8'), 'xx');
assert.equal(await handler(event('two', {path:source, limit:50}, large)), undefined);
assert.equal(await handler(event('three', {path:source}, large, true)), undefined);
assert.equal(await handler(event('four', {path:source}, 'tiny')), undefined);
writeFileSync(worker, 'import sys; sys.exit(7)\n');
assert.equal(await handler(event('five', {path:source}, large)), undefined);
const record = JSON.parse(readFileSync(process.env.BULK_READ_TELEMETRY, 'utf8').trim());
assert.equal(record.call_id, 'five');
assert.equal(record.usage, 'unknown');
console.log('Pi tool_result replacement and fallback passed');
