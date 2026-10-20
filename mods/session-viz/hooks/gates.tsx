import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, RenderElement } from 'claude-code'

import type { FindingCounts, Gates, ReceiptState, Severity } from '../types'
import { EMPTY_FINDINGS, EVERY, GATES_KEPT, INITIAL_AGENTS, INITIAL_TOASTED, SEVERITIES, emptyGates, findingCounts, fit } from './state'
import type { Draw } from './state'

const gates = atom({ plugin: 'session-viz', key: 'gates' } as const, emptyGates())
const toasted = atom({ plugin: 'session-viz', key: 'toasted' } as const, INITIAL_TOASTED)
const agents = atom({ plugin: 'session-viz', key: 'agents' } as const, INITIAL_AGENTS)


/** `1. [MUST-FIX | confidence: 100 | …] file:line — text`, the number prefix optional. */
const FINDING = new RegExp(`^\\s*(?:\\d+\\.\\s*)?\\[(${SEVERITIES.join('|')})\\s*\\|`)
/** `Verdict: ✅ GO`, the glyph optional. */
const VERDICT = /^\s*Verdict:\s*(?:\S+\s+)?(GO|HOLD|STOP)\b/
/** `Receipt: STOP <fp8> policy qg1-00000000`. */
const RECEIPT_LINE = /^\s*Receipt:\s*(GO|HOLD|STOP)\s+([0-9a-f]{8})/
/** `ref: refs/heads/<branch>` in a HEAD file. */
const HEAD_REF = /^ref:\s*refs\/heads\/(\S+)/
/** A receipt fingerprint as the pointer names it. */
const FINGERPRINT = /^[0-9a-f]{64}$/

function lines(text: string): string[] {
  return text.split(/\r?\n/)
}

function startingWith(text: string, tag: string): string[] {
  return lines(text)
    .map(line => line.trim())
    .filter(line => line.startsWith(tag))
}

/** The finding count per severity of a reviewer's answer. */
export function parseFindings(text: string): FindingCounts {
  const counts: FindingCounts = { ...EMPTY_FINDINGS }
  for (const line of lines(text)) {
    const found = FINDING.exec(line)
    if (found !== null) counts[found[1] as Severity] += 1
  }
  return counts
}

/** Every `[AMBIGUITY] …` line, whole. */
export function parseAmbiguities(text: string): string[] {
  return startingWith(text, '[AMBIGUITY]')
}

/** Every `[SURFACE] +<path> | reason: …` line, whole. */
export function parseSurfaces(text: string): string[] {
  return startingWith(text, '[SURFACE]')
}

/** The verdict of the last `Verdict:` line. */
export function parseVerdict(text: string): string | undefined {
  const found = lines(text)
    .map(line => VERDICT.exec(line))
    .filter(match => match !== null)
  return found.at(-1)?.[1]
}

/** The verdict and fingerprint of the last `Receipt:` line. */
export function parseReceiptLine(text: string): { verdict: string; fp8: string } | undefined {
  const found = lines(text)
    .map(line => RECEIPT_LINE.exec(line))
    .filter(match => match !== null)
    .at(-1)
  return found === undefined ? undefined : { verdict: found[1]!, fp8: found[2]! }
}

function sumFindings(a: FindingCounts, b: FindingCounts): FindingCounts {
  return findingCounts(severity => a[severity] + b[severity])
}

async function readText($: EngineInterface, path: string): Promise<string | undefined> {
  try {
    return await $.fs.read(path)
  } catch {
    return undefined
  }
}

function parseObject(text: string): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(text)
    return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : undefined
  } catch {
    return undefined
  }
}

/** The branch HEAD names, through the `gitdir:` file a worktree has; undefined when detached or unreadable. */
async function currentBranch($: EngineInterface, cwd: string): Promise<string | undefined> {
  const dotGit = await readText($, `${cwd}/.git`)
  const gitDir = dotGit?.startsWith('gitdir:') ? dotGit.slice('gitdir:'.length).trim() : `${cwd}/.git`
  const head = await readText($, `${gitDir}/HEAD`)
  return head === undefined ? undefined : HEAD_REF.exec(head)?.[1]
}

/**
 * What the current branch's pointer location holds (spec D12): no pointer, a pointer or receipt that cannot be read
 * (a dangling pointer included), or the receipt; undefined when no repo or branch resolves, so no location could be read.
 */
async function readReceipt($: EngineInterface): Promise<ReceiptState | undefined> {
  const repo = await $.session.repo()
  if (repo === null) return undefined
  const branch = await currentBranch($, await $.session.cwd())
  if (branch === undefined) return undefined

  const dir = `${repo.root}/.git/quality-receipts`
  const pointerText = await readText($, `${dir}/branch-${branch.replace(/[^A-Za-z0-9_.-]/g, '-')}.json`)
  if (pointerText === undefined) return { state: 'none' }
  const fingerprint = parseObject(pointerText)?.fingerprint
  if (typeof fingerprint !== 'string' || !FINGERPRINT.test(fingerprint)) return { state: 'unreadable' }

  const receiptText = await readText($, `${dir}/${fingerprint}.json`)
  if (receiptText === undefined) return { state: 'unreadable' }
  const receipt = parseObject(receiptText)
  if (receipt === undefined || typeof receipt.verdict !== 'string') return { state: 'unreadable' }

  const tests = receipt.tests
  const testsExit = typeof tests === 'object' && tests !== null ? (tests as Record<string, unknown>).exit : undefined
  return {
    state: 'ok',
    verdict: receipt.verdict,
    fp8: fingerprint.slice(0, 8),
    testsExit: typeof testsExit === 'number' ? testsExit : undefined,
    unresolved: Array.isArray(receipt.unresolved) ? receipt.unresolved.length : undefined,
    designVerdict: typeof receipt.design_verdict === 'string' ? receipt.design_verdict : undefined,
  }
}

/** Toasts a STOP once per `id` of its kind (a receipt fingerprint, or a main-loop turn); HOLD and GO never reach here. */
async function toastStop($: EngineInterface, kind: keyof typeof INITIAL_TOASTED, id: string, fp8: string | undefined): Promise<void> {
  // Decided inside the updater, so two overlapping refreshes of one STOP cannot both toast.
  let fresh = false
  await update($, toasted, current => {
    if (current[kind].includes(id)) return current
    fresh = true
    return { ...current, [kind]: [...current[kind], id] }
  })
  if (fresh) $.ui.toast(`session-viz: quality gate STOP${fp8 === undefined ? '' : ` (${fp8})`}`)
}

/**
 * Re-reads the receipt files into the section; a STOP toasts once per fingerprint. Whatever the pointer
 * location holds replaces what is shown; only when no repo or branch resolves does a main-loop line's receipt stay.
 */
async function refreshReceipt($: EngineInterface): Promise<void> {
  const found = await readReceipt($)
  if (found === undefined) return
  await update($, gates, current => ({ ...current, receipt: found }))
  if (found.state === 'ok' && found.verdict === 'STOP') await toastStop($, 'fingerprints', found.fp8, found.fp8)
}

/** What a sub-agent's answer adds: its parsed lines go on its row and into the section. */
async function recordAgentAnswer($: EngineInterface, agentId: string, answer: string): Promise<void> {
  const parsed = { findings: parseFindings(answer), ambiguities: parseAmbiguities(answer), surfaces: parseSurfaces(answer) }
  const row = (await read($, agents)).find(one => one.agentId === agentId)
  const agent = row?.type ?? agentId
  const tagged = (texts: string[]) => texts.map(text => ({ agent, text }))
  await update($, agents, rows => rows.map(one => (one.agentId === agentId ? { ...one, ...parsed } : one)))
  await update($, gates, current => ({
    ...current,
    findings: sumFindings(current.findings, parsed.findings),
    ambiguities: [...current.ambiguities, ...tagged(parsed.ambiguities)].slice(-GATES_KEPT),
    surfaces: [...current.surfaces, ...tagged(parsed.surfaces)].slice(-GATES_KEPT),
  }))
}

/** A main-loop `Receipt:` line's verdict and fingerprint laid over the receipt the files last gave, when they gave one. */
function fromLine(current: ReceiptState, line: { verdict: string; fp8: string }): ReceiptState {
  return current.state === 'ok' ? { ...current, ...line } : { state: 'ok', ...line }
}

/** What the main loop's answer adds: its Verdict and Receipt lines, a STOP toast once per turn, then the files re-read. */
async function recordMainAnswer($: EngineInterface, turnId: string, answer: string): Promise<void> {
  const verdict = parseVerdict(answer)
  const line = parseReceiptLine(answer)
  await update($, gates, current => ({
    ...current,
    verdict: verdict ?? current.verdict,
    receipt: line === undefined ? current.receipt : fromLine(current.receipt, line),
  }))
  if (line?.verdict === 'STOP' || verdict === 'STOP') {
    const fp8 = line?.verdict === 'STOP' ? line.fp8 : undefined
    await toastStop($, 'turns', turnId, fp8)
    // The same fingerprint's file read must not toast it a second time.
    if (fp8 !== undefined) await update($, toasted, current => ({ ...current, fingerprints: [...new Set([...current.fingerprints, fp8])] }))
  }
  await refreshReceipt($)
}

export function registerGates(on: On): void {
  on('session.start', { cwd: EVERY }, async ($, e, next) => {
    const result = await next(e)
    await refreshReceipt($)

    return result
  })

  on('turn.complete', { answer: EVERY }, async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) await recordMainAnswer($, e.turnId, e.answer)
    else await recordAgentAnswer($, e.agentId, e.answer)

    return result
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    if (e.command.includes('receipt.py') && e.command.includes('write')) await refreshReceipt($)

    return result
  })
}

function receiptLine(receipt: ReceiptState): string {
  if (receipt.state === 'unreadable') return 'receipt unreadable'
  if (receipt.state === 'none') return 'no receipt yet'
  const parts = [
    `receipt ${receipt.verdict} ${receipt.fp8}`,
    receipt.testsExit === undefined ? undefined : `tests exit ${receipt.testsExit}`,
    receipt.unresolved === undefined ? undefined : `unresolved ${receipt.unresolved}`,
  ]
  return parts.filter((part): part is string => part !== undefined).join(' · ')
}

export function GatesSection(d: Draw, state: Gates): RenderElement {
  const { Box, Text } = d.t
  const isDim = state.receipt.state !== 'ok'
  const counts = SEVERITIES.filter(severity => state.findings[severity] > 0)
    .map(severity => `${severity} ${state.findings[severity]}`)
    .join(' · ')
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>GATES</Text>
      <Text dimColor={isDim}>{fit(receiptLine(state.receipt), d.width)}</Text>
      {state.verdict !== undefined && <Text>{fit(`verdict ${state.verdict}`, d.width)}</Text>}
      {counts !== '' && <Text>{fit(counts, d.width)}</Text>}
      {state.ambiguities.map((one, index) => (
        <Text key={`a${index}`}>{fit(`⚑ ${one.agent}: ${one.text}`, d.width)}</Text>
      ))}
      {state.surfaces.map((one, index) => (
        <Text key={`s${index}`}>{fit(`${one.agent}: ${one.text}`, d.width)}</Text>
      ))}
    </Box>
  )
}
