/**
 * Pi mirror of .claude/hooks/bulk-read-gate.py — specs/bulk-read-gate.md.
 *
 * Blocks any single read that would put more than BULK_READ_MIN_LINES lines
 * (default 350) of one file into the calling model's context, and names the
 * two allowed alternatives: dispatch `bulk-reader` with a question, or read
 * only the range an edit needs. It never rewrites the call and never reads
 * content into the model — it counts newlines.
 *
 * Installed by install.sh into ~/.pi/agent/extensions/. Set BULK_READ_GATE=off
 * to disable for one session. The Python hook is the reference; keep the
 * threshold, the environment names, the read range rule, the command-list and
 * redirection grammar, and the shell pattern list in step with it.
 */

import { closeSync, openSync, readSync, statSync } from "node:fs";
import { basename } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export const DEFAULT_THRESHOLD = 350;
const GATE_ENV = "BULK_READ_GATE";
const THRESHOLD_ENV = "BULK_READ_MIN_LINES";
const BINARY_PROBE_BYTES = 8192;
// Command lists: each list's final pipe stage prints into the tool result, so
// every one is gated. `|` alone hands a stage's stdout to the next stage.
const LIST_SEPARATORS = new Set(["||", "&&", ";", "&", "\n"]);
// `2>&1`, `> out`, `>> log`, `&> all`, `< in` — with or without the operand glued on.
const REDIRECT = /^(\d*)(&>>|&>|>>|>|<<|<)(.*)$/;
const SED_RANGE = /^(\d+),(\d+|\$)p$/;
const HEAD_COUNT = /^(?:-n|--lines=|-)(\d+)$/;
const POWERSHELL_LIMITERS = new Set(["-totalcount", "-head", "-first", "-tail", "-last"]);

type ToolInput = Record<string, unknown>;
/** [first line, last line or null for end of file], 1-based and inclusive. */
type Window = [number, number | null];
const WHOLE: Window = [1, null];

function threshold(): number {
  const raw = (process.env[THRESHOLD_ENV] ?? "").trim();
  if (raw === "") return DEFAULT_THRESHOLD;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    // Loud, never a silent allow: a misconfigured gate is a broken gate.
    throw new Error(`bulk-read-gate: ${THRESHOLD_ENV} must be a positive integer, got ${JSON.stringify(raw)}`);
  }
  return value;
}

function expandHome(path: string): string {
  return path.startsWith("~/") ? `${homedir()}/${path.slice(2)}` : path;
}

/**
 * Line count of a regular text file; 0 when the gate has no opinion (missing,
 * directory, binary) — zero lines never exceeds a threshold. A path that exists
 * but cannot be opened throws, and the handler blocks with the error text.
 */
function countLines(path: string): number {
  const expanded = expandHome(path);
  let size: number;
  try {
    const stat = statSync(expanded);
    if (!stat.isFile()) return 0;
    size = stat.size;
  } catch {
    return 0; // missing: the tool reports its own error
  }
  const fd = openSync(expanded, "r"); // permission errors throw — loud by design
  try {
    const buffer = Buffer.alloc(1 << 20);
    let lines = 0;
    let last = -1;
    let offset = 0;
    let probed = false;
    while (offset < size) {
      const read = readSync(fd, buffer, 0, buffer.length, offset);
      if (read <= 0) break;
      if (!probed) {
        probed = true;
        if (buffer.subarray(0, Math.min(read, BINARY_PROBE_BYTES)).includes(0)) return 0;
      }
      for (let i = 0; i < read; i++) if (buffer[i] === 10) lines++;
      last = buffer[read - 1];
      offset += read;
    }
    if (last !== -1 && last !== 10) lines++;
    return lines;
  } finally {
    closeSync(fd);
  }
}

function denyReason(path: string, lines: number, limit: number): string {
  return (
    `${path} has ${lines} lines; the bulk-read gate denies reads over ${limit} lines ` +
    `(${THRESHOLD_ENV}). Either dispatch the \`bulk-reader\` agent with a ` +
    `question about this file, or read only the range you need for an edit ` +
    `(read with offset/limit of at most ${limit} lines, or \`sed -n 'A,Bp'\`).`
  );
}

function positiveInt(value: unknown): number | null {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

/** How many of an N-line file's lines printing `window` puts into context. */
function deliveredLines(lines: number, window: Window): number {
  const [start, end] = window;
  return Math.max(Math.min(end ?? lines, lines) - start + 1, 0);
}

function gatePath(path: string, window: Window, limit: number): string | null {
  const lines = countLines(path);
  const delivered = deliveredLines(lines, window);
  return delivered > limit ? denyReason(path, lines, limit) : null;
}

/** Pi's `read` tool: `path`, optional `offset` and `limit`. */
function gateRead(input: ToolInput, limit: number): string | null {
  const path = input.path;
  if (typeof path !== "string" || path === "") return null;
  const offset = positiveInt(input.offset) ?? 1;
  const requested = positiveInt(input.limit);
  return gatePath(path, [offset, requested ? offset + requested - 1 : null], limit);
}

/** `&` inside `2>&1` or `&>` is part of a redirection, not a list separator. */
function redirectGlue(current: string, command: string, i: number): boolean {
  return command[i] === "&" && (current.endsWith(">") || command[i + 1] === ">");
}

/**
 * Quote-aware split. Quotes stay on the token (see unquote); backslashes are
 * literal so Windows paths survive; `|`, `||`, `&&`, `;`, `&` and newline are
 * their own tokens.
 */
function tokenize(command: string): string[] {
  const tokens: string[] = [];
  let current = "";
  let quote: string | null = null;
  const flush = () => {
    if (current !== "") tokens.push(current);
    current = "";
  };
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      current += ch;
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      current += ch;
      continue;
    }
    if (ch === "\n" || ((ch === "|" || ch === "&" || ch === ";") && !redirectGlue(current, command, i))) {
      flush();
      const pair = command.slice(i, i + 2);
      if (pair === "||" || pair === "&&") {
        tokens.push(pair);
        i++;
      } else {
        tokens.push(ch);
      }
      continue;
    }
    if (/\s/.test(ch)) {
      flush();
      continue;
    }
    current += ch;
  }
  flush();
  return tokens;
}

/** The last pipe stage of every command list — each prints into the tool result. */
function finalStages(tokens: string[]): string[][] {
  const stages: string[][] = [];
  let stage: string[] = [];
  for (const token of tokens) {
    if (LIST_SEPARATORS.has(token)) {
      stages.push(stage);
      stage = [];
    } else if (token === "|") {
      stage = [];
    } else {
      stage.push(token);
    }
  }
  stages.push(stage);
  return stages;
}

/**
 * Drop redirections and their operands. `< path` makes the path an argument
 * (cat < big prints big); `N>&M` is a descriptor copy and `<<WORD` an inline
 * heredoc, neither of which changes what is printed; `>`/`>>`/`&>` to a file
 * take the stage's stdout out of the tool result.
 */
function stripRedirects(args: string[]): { args: string[]; silenced: boolean } {
  const kept: string[] = [];
  const inputs: string[] = [];
  let silenced = false;
  for (let i = 0; i < args.length; i++) {
    const match = REDIRECT.exec(args[i]);
    if (!match) {
      kept.push(args[i]);
      continue;
    }
    const [, fd, op] = match;
    let target = match[3];
    if (target === "" && i + 1 < args.length) target = args[++i];
    if (target.startsWith("&") || op === "<<") continue;
    if (op === "<") inputs.push(target);
    else if (fd === "" || fd === "1" || op.startsWith("&")) silenced = true;
  }
  return { args: kept.concat(inputs), silenced };
}

function unquote(token: string): string {
  if (token.length >= 2 && token[0] === token[token.length - 1] && (token[0] === '"' || token[0] === "'")) {
    return token.slice(1, -1);
  }
  return token;
}

function positional(args: string[]): string[] {
  return args.filter((arg) => !arg.startsWith("-")).map(unquote);
}

function powershellPaths(args: string[]): string[] {
  const paths: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const lowered = args[i].toLowerCase();
    if (lowered === "-path" || lowered === "-literalpath") {
      if (i + 1 < args.length) paths.push(unquote(args[i + 1]));
      i++;
    } else if (!args[i].startsWith("-")) {
      paths.push(unquote(args[i]));
    }
  }
  return paths;
}

/** `head [-n N] path` prints lines 1..N (10 by default). */
function headRead(args: string[]): { paths: string[]; window: Window } {
  let count: number | null = 10;
  const paths: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const match = HEAD_COUNT.exec(arg);
    if ((arg === "-n" || arg === "--lines") && i + 1 < args.length) count = positiveInt(args[++i]);
    else if (match) count = positiveInt(match[1]);
    else if (arg.startsWith("-")) return { paths: [], window: WHOLE }; // -c bytes and friends are not line reads
    else paths.push(unquote(arg));
  }
  return count ? { paths, window: [1, count] } : { paths: [], window: WHOLE };
}

/** `sed -n 'A,Bp' path` prints lines A..B; `$` means end of file. */
function sedRead(args: string[]): { paths: string[]; window: Window } {
  let script: string | null = null;
  const paths: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if ((arg === "-e" || arg === "--expression") && i + 1 < args.length) script = unquote(args[++i]);
    else if (!arg.startsWith("-")) {
      if (script === null) script = unquote(arg);
      else paths.push(unquote(arg));
    }
  }
  const match = SED_RANGE.exec(script ?? "");
  if (!match) return { paths: [], window: WHOLE };
  const end = match[2] === "$" ? null : Number(match[2]);
  return { paths, window: [Number(match[1]), end] };
}

/** Paths a stage prints into the tool result, and the line window it prints. */
function shellRead(stage: string[]): { paths: string[]; window: Window } {
  if (stage.length === 0) return { paths: [], window: WHOLE };
  const { args, silenced } = stripRedirects(stage.slice(1));
  if (silenced) return { paths: [], window: WHOLE };
  const name = basename(unquote(stage[0])).toLowerCase();
  if (name === "cat" || name === "type") return { paths: positional(args), window: WHOLE };
  if (name === "get-content" || name === "gc") {
    if (args.some((arg) => POWERSHELL_LIMITERS.has(arg.toLowerCase()))) return { paths: [], window: WHOLE };
    return { paths: powershellPaths(args), window: WHOLE };
  }
  if (name === "head") return headRead(args);
  if (name === "sed") return sedRead(args);
  return { paths: [], window: WHOLE };
}

/** Pi's `bash` tool: `command`. Every command list's final pipe stage decides. */
function gateShell(input: ToolInput, limit: number): string | null {
  const command = input.command;
  if (typeof command !== "string") return null;
  for (const stage of finalStages(tokenize(command))) {
    const { paths, window } = shellRead(stage);
    for (const path of paths) {
      const reason = gatePath(path, window, limit);
      if (reason !== null) return reason;
    }
  }
  return null;
}

export default function bulkReadGate(pi: ExtensionAPI): void {
  pi.on("tool_call", async (event) => {
    if ((process.env[GATE_ENV] ?? "").trim().toLowerCase() === "off") return undefined;
    if (event.toolName !== "read" && event.toolName !== "bash") return undefined;
    // Errors are returned as a block, not thrown: how the host treats a rejected
    // handler is its decision, and blocking with the error text is the one
    // outcome this module can guarantee is loud rather than a silent allow.
    try {
      const limit = threshold();
      const input = (event.input ?? {}) as ToolInput;
      let reason: string | null = null;
      if (event.toolName === "read") reason = gateRead(input, limit);
      else if (event.toolName === "bash") reason = gateShell(input, limit);
      return reason ? { block: true, reason } : undefined;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { block: true, reason: `bulk-read-gate: ${message}` };
    }
  });
}
