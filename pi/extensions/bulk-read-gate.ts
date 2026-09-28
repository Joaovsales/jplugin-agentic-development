/** Post-read adapter for scripts/context-read.py; installed by install.sh. */
import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI, ToolResultEvent } from '@mariozechner/pi-coding-agent';

const here = dirname(fileURLToPath(import.meta.url));
const cli = existsSync(resolve(here, 'context-read.py'))
  ? resolve(here, 'context-read.py') : resolve(here, '../../scripts/context-read.py');

function logFallback(callId: string, category: string): void {
  const path = process.env.BULK_READ_TELEMETRY ?? resolve(homedir(), '.cache/coding-agent-workflow/bulk-read-fallback.jsonl');
  const record = { time: Math.floor(Date.now() / 1000), category, harness: 'pi', call_id: callId, usage: 'unknown' };
  try {
    mkdirSync(dirname(path), { recursive: true });
    appendFileSync(path, JSON.stringify(record) + '\n');
  } catch (error) {
    process.stderr.write(`bulk-read-gate: telemetry write failed: ${String(error)}\n`);
  }
}

function requestFor(event: ToolResultEvent): object {
  return {
    harness: 'pi', tool_name: event.toolName, tool_input: event.input,
    tool_response: event.content[0].text, tool_use_id: event.toolCallId, cwd: process.cwd(),
  };
}

function parseRouterOutput(callId: string, stdout: string): unknown | null {
  try {
    const response = JSON.parse(stdout);
    if (!Object.hasOwn(response, 'replacement')) throw new Error('missing replacement');
    return response.replacement;
  } catch {
    logFallback(callId, 'invalid_router_response');
    return null;
  }
}

function routeResult(event: ToolResultEvent): unknown | null {
  if (!existsSync(cli)) {
    logFallback(event.toolCallId, 'cli_missing');
    return null;
  }
  const result = spawnSync('python3', [cli, '--route'], {
    input: JSON.stringify(requestFor(event)), encoding: 'utf8', timeout: 90000,
    maxBuffer: 1024 * 1024, env: process.env,
  });
  if (result.error || result.status !== 0) {
    logFallback(event.toolCallId, 'router_failed');
    return null;
  }
  return parseRouterOutput(event.toolCallId, result.stdout);
}

export default function bulkReadGate(pi: ExtensionAPI): void {
  pi.on('tool_result', async (event) => {
    if (process.env.BULK_READ_GATE?.toLowerCase() === 'off' || process.env.BULK_READ_CHILD === '1') return;
    if (!['read', 'bash', 'powershell'].includes(event.toolName) || event.isError) return;
    if (event.content.length !== 1 || event.content[0]?.type !== 'text') return;
    const replacement = routeResult(event);
    if (replacement === null) return;
    return { content: [{ type: 'text' as const, text: JSON.stringify(replacement) }] };
  });
}
