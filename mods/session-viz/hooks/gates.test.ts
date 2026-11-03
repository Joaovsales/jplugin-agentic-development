import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { parseAmbiguities, parseFindings, parseReceiptLine, parseSurfaces, parseVerdict } from './gates'

const SURFACES = ['terminal', 'desktop'] as const

const PANE = {
  plugin: 'session-viz',
  component: 'Pane' as const,
  requestId: 'session-viz',
  props: {
    title: 'Session',
    isFocused: false,
    bodyColumns: 200,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
}

const FP = 'ab12cd34' + '0'.repeat(56)
const FP_HOLD = 'ee55ff66' + '1'.repeat(56)
const STOP_TOAST = 'session-viz: quality gate STOP (ab12cd34)'

const ANSWER = [
  '1. [MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent] a.py:1 — x',
  '[MUST-FIX | confidence: 90 | autofix_class: gated_auto | owner: agent] b.py:2 — y',
  '[NITPICK | confidence: 60 | autofix_class: manual | owner: human] c.py:3 — z',
  '[AMBIGUITY] which config | options: A) root B) pkg | picked: A | reason: closer',
  '[SURFACE] +x.py | reason: y',
].join('\n')

/** The world beneath the plugin, with a quality receipt on disk that a test can change. */
function world(on: On) {
  const toasts: string[] = []
  const disk = {
    /** What `.git/HEAD` holds: a branch ref, or a bare sha when detached. */
    head: 'ref: refs/heads/feat/x\n',
    fingerprint: FP,
    receipt: { schema: 'qg1', verdict: 'STOP', tests: { exit: 1 }, unresolved: [{ id: 1 }], design_verdict: 'GO' } as unknown,
    /** Whether feat/x's branch pointer file exists. */
    pointer: true,
    /** Whether the receipt file the pointer names exists; false makes the pointer dangle. */
    receiptFile: true,
  }
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', ($, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('agent.list', () => ({ value: [] }))
  on('agent.spawn', ($, e) => ({ model: 'claude-sonnet-5-5', agentId: `agent-${e.description}` }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.repo', () => ({ value: { root: 'C:/repo', remote: null, internal: false, name: null } }))
  on('session.cwd', () => ({ value: 'C:/repo' }))
  on('fs.read', ($, e) => {
    const path = e.path.replace(/\\/g, '/')
    if (path === 'C:/repo/.git') return { deny: 'EISDIR' }
    if (path === 'C:/repo/.git/HEAD') return { value: disk.head }
    if (path === 'C:/repo/.git/quality-receipts/branch-feat-x.json' && disk.pointer) {
      return { value: JSON.stringify({ fingerprint: disk.fingerprint }) }
    }
    if (path === `C:/repo/.git/quality-receipts/${disk.fingerprint}.json` && disk.receiptFile) {
      return typeof disk.receipt === 'string' ? { value: disk.receipt } : { value: JSON.stringify(disk.receipt) }
    }
    return { deny: 'ENOENT: no such file' }
  })
  on('turn.complete', () => ({ text: '' }))
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: '', stderr: '', interrupted: false } }))
  const clock = mock.clock(on)
  return { toasts, disk, clock }
}

test('parsers: findings, ambiguities, surfaces, Verdict and Receipt lines', () => {
  expect(parseFindings(ANSWER)).toEqual({ 'MUST-FIX': 2, 'SHOULD-FIX': 0, NITPICK: 1 })
  expect(parseFindings('see [MUST-FIX | x] inline\nnothing')).toEqual({ 'MUST-FIX': 0, 'SHOULD-FIX': 0, NITPICK: 0 })
  expect(parseAmbiguities(ANSWER)).toEqual(['[AMBIGUITY] which config | options: A) root B) pkg | picked: A | reason: closer'])
  expect(parseSurfaces(ANSWER)).toEqual(['[SURFACE] +x.py | reason: y'])
  expect(parseVerdict('Verdict: ✅ GO\nmore\n  Verdict: STOP\n')).toBe('STOP')
  expect(parseVerdict('Verdict: HOLD')).toBe('HOLD')
  expect(parseVerdict('no verdict here')).toBeUndefined()
  expect(parseReceiptLine('Receipt: STOP deadbeef policy qg1-00000000')).toEqual({ verdict: 'STOP', fp8: 'deadbeef' })
  expect(parseReceiptLine('Receipt: STOP nothex policy')).toBeUndefined()
})

test('findings: a reviewer answer gives MUST-FIX 2 · NITPICK 1, the ambiguity with the agent\'s type, and the surface report', async ($, on) => {
  world(on)
  await $.agent.spawn({
    tool_use_id: 'tu-1',
    prompt: 'Review slice 3.',
    description: 'cr',
    subagentType: 'code-reviewer',
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: 'claude-sonnet-5-5',
    background: true,
    fork: false,
  })
  await $.turn.complete({
    answer: ANSWER,
    durationMs: 12000,
    isAborted: false,
    turnId: 'turn-2',
    agentId: 'agent-cr',
    reason: 'answer',
  })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /^no receipt yet$/ }), `${surface}: receipt`).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^MUST-FIX 2 · NITPICK 1$/ }), `${surface}: findings`).toBeDefined()
    expect(
      await ui.find({ type: 'Text', text: /^⚑ code-reviewer: \[AMBIGUITY\] which config \| options: A\) root B\) pkg/ }),
      `${surface}: ambiguity`,
    ).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^code-reviewer: \[SURFACE\] \+x\.py \| reason: y$/ }), `${surface}: surface`).toBeDefined()
    await ui.unmount()
  }
})

test('receipt: a STOP receipt toasts once per fingerprint, HOLD is silent, a main-loop Receipt line toasts once per turn, Gates reads the receipt', async ($, on) => {
  const w = world(on)

  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
  expect(w.toasts).toEqual([STOP_TOAST])

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(
      await ui.find({ type: 'Text', text: /^receipt STOP ab12cd34 · tests exit 1 · unresolved 1$/ }),
      `${surface}: receipt line`,
    ).toBeDefined()
    await ui.unmount()
  }

  // A second read of the same fingerprint is silent.
  await $.tool.call({ tool: 'Bash', command: 'python3 .agents/skills/quality-gate/scripts/receipt.py write --verdict STOP' })
  await w.clock.settle()
  expect(w.toasts).toEqual([STOP_TOAST])

  // A HOLD receipt toasts nothing, and a command that is not a receipt write does not read.
  w.disk.fingerprint = FP_HOLD
  w.disk.receipt = { schema: 'qg1', verdict: 'HOLD', tests: { exit: 0 }, unresolved: [], design_verdict: 'GO' }
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await w.clock.settle()
  const stale = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await stale.find({ type: 'Text', text: /^receipt STOP ab12cd34/ })).toBeDefined()
  await stale.unmount()
  await $.tool.call({ tool: 'Bash', command: 'python3 .agents/skills/quality-gate/scripts/receipt.py write --verdict HOLD' })
  await w.clock.settle()
  expect(w.toasts).toEqual([STOP_TOAST])
  const holdUi = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await holdUi.find({ type: 'Text', text: /^receipt HOLD ee55ff66 · tests exit 0 · unresolved 0$/ })).toBeDefined()
  await holdUi.unmount()

  // The main loop's Receipt line toasts once per turn; the same turn again is silent, a new turn toasts.
  const line = 'Done.\nReceipt: STOP deadbeef policy qg1-00000000\nVerdict: STOP'
  const turn = (turnId: string) =>
    $.turn.complete({ answer: line, durationMs: 1000, isAborted: false, turnId, reason: 'answer' })
  await turn('turn-3')
  await turn('turn-3')
  await w.clock.settle()
  expect(w.toasts).toEqual([STOP_TOAST, 'session-viz: quality gate STOP (deadbeef)'])
  await turn('turn-4')
  await w.clock.settle()
  expect(w.toasts).toHaveLength(3)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^verdict STOP$/ })).toBeDefined()
  await ui.unmount()
})

test('receipt: no pointer reads as no receipt yet, a malformed receipt as unreadable', async ($, on) => {
  const w = world(on)
  w.disk.pointer = false
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
  let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^no receipt yet$/ })).toBeDefined()
  await ui.unmount()

  w.disk.pointer = true
  w.disk.receipt = '{ not json'
  await $.tool.call({ tool: 'Bash', command: 'python3 receipt.py write' })
  await w.clock.settle()
  ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^receipt unreadable$/ })).toBeDefined()
  await ui.unmount()
  expect(w.toasts).toEqual([])
})

test('receipt: a branch with no pointer replaces the last branch\'s receipt, a dangling pointer is unreadable, a detached HEAD keeps what is shown', async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  await w.clock.settle()

  const receiptLine = async (): Promise<string> => {
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    const line = (await ui.find({ type: 'Text', text: /^(receipt |no receipt)/ }))?.text ?? ''
    await ui.unmount()
    return line
  }
  const rewrite = async (): Promise<void> => {
    await $.tool.call({ tool: 'Bash', command: 'python3 receipt.py write' })
    await w.clock.settle()
  }
  expect(await receiptLine()).toMatch(/^receipt STOP ab12cd34/)

  // On feat/y no pointer exists: feat/x's receipt must not stay on screen.
  w.disk.head = 'ref: refs/heads/feat/y\n'
  await rewrite()
  expect(await receiptLine()).toBe('no receipt yet')

  // Back on feat/x the pointer names a receipt file that is gone: a dangling pointer, not "no receipt".
  w.disk.head = 'ref: refs/heads/feat/x\n'
  w.disk.receiptFile = false
  await rewrite()
  expect(await receiptLine()).toBe('receipt unreadable')

  // A detached HEAD names no branch, so no pointer location can be read: what is shown stays, whatever is on disk.
  w.disk.head = `${'c0ffee00'.repeat(5)}\n`
  w.disk.receiptFile = true
  await rewrite()
  expect(await receiptLine()).toBe('receipt unreadable')
  expect(w.toasts).toEqual([STOP_TOAST])
})
