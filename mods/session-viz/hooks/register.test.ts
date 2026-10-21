import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

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
const NARROW = { ...PANE, props: { ...PANE.props, bodyColumns: 80 } }

const EMPTY_LINES = ['idle · no skill running', 'no plan block', 'no sub-agents yet', 'no receipt yet', 'no agent selected']

/** The world beneath the plugin: every call on `$` the mod makes, answered from memory, and what it drew on. */
function world(on: On, options: { answer?: string } = {}) {
  const opens: Array<{ id: string; focus?: true }> = []
  const statuses: Array<string | undefined> = []
  const toasts: string[] = []
  on('ui.open', ($, e) => {
    opens.push({ id: e.id, focus: e.focus })
    return { value: { isPlaced: true as const } }
  })
  on('ui.status', ($, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', ($, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('agent.list', () => ({ value: [] }))
  on('session.repo', () => ({ value: null }))
  on('fs.read', () => ({ deny: 'ENOENT: no such file' }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('skill.prompt', ($, e) => ({ text: e.text }))
  on('prompt.submit', ($, e) => ({ text: e.text }))
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('turn.step', async function* ($, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: options.answer ?? '',
      toolUses: [],
      stopReason: 'end_turn' as const,
      usage: null,
    }
  })
  const clock = mock.clock(on)
  return { opens, statuses, toasts, clock }
}

async function drain(stream: AsyncIterable<unknown>): Promise<void> {
  for await (const _chunk of stream) {
    // read to the end so the result settles
  }
}

test('shell: the pane opens at session.start and on /session-viz, every section draws its empty line on both surfaces, and a tool call passes through unchanged', async ($, on) => {
  const w = world(on)
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: 'ok', stderr: '', interrupted: false } }))

  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
  expect(w.opens).toEqual([{ id: 'session-viz', focus: undefined }])
  expect(w.statuses.at(-1)).toBe('viz · idle')

  const ran = await $.command.run({
    command: 'session-viz',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 200 },
  })
  expect(ran.text).toBe('Session pane opened.')
  expect(w.opens.at(-1)).toEqual({ id: 'session-viz', focus: true })

  for (const surface of SURFACES) {
    for (const target of [PANE, NARROW]) {
      const ui = await $.ui.mount({ ...target, surface })
      for (const line of EMPTY_LINES) {
        expect(await ui.find({ type: 'Text', text: line }), `${surface} ${target.props.bodyColumns}: ${line}`).toBeDefined()
      }
      await ui.unmount()
    }
  }

  const result = await $.tool.call({ tool: 'Bash', command: 'echo ok' })
  expect(result).toMatchObject({ result: { stdout: 'ok' } })
  expect(w.toasts).toEqual([])
})

test('phase: a plugin-prefixed skill.prompt sets the phase, a main-loop [ROUTE] sets lane and chain, a prompt.submit records the spec', async ($, on) => {
  const w = world(on, { answer: 'Routing.\n[ROUTE] lane=fix | chain=debug, quality-gate | reason: a defect\n' })

  await $.skill.prompt({ skill: 'jplugin:build', text: 'Build the plan.' })
  await drain($.turn.step({ turnId: 'turn-1', index: 0, model: 'claude-opus-5-5', messageCount: 3 }))
  await $.prompt.submit({
    text: 'Invoke `/build` for `specs/x.md`.\nPlan: 5 slices.',
    wait: false,
    origin: { kind: 'composer' },
  })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /^BUILD · build$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^route fix · debug, quality-gate$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^spec specs\/x\.md$/ })).toBeDefined()
    await ui.unmount()
  }

  // A sub-agent's [ROUTE] line is not the session's route; an unmapped skill shows as running and leaves the phase.
  await drain($.turn.step({ turnId: 'turn-2', index: 0, model: 'claude-opus-5-5', messageCount: 3, agentId: 'agent-1' }))
  await $.skill.prompt({ skill: 'commit', text: '' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^BUILD · commit$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^route fix · debug, quality-gate$/ })).toBeDefined()
  await ui.unmount()
  expect(w.toasts).toEqual([])
})

test('status line: session.measure writes viz · BUILD · build · ctx 42% · $1.23 and leaves unknown fields out', async ($, on) => {
  const w = world(on)

  await $.skill.prompt({ skill: 'jplugin:build', text: '' })
  await w.clock.settle()
  expect(w.statuses.at(-1)).toBe('viz · BUILD · build')

  await $.session.measure({
    context: { window: 200_000, tokens: 84_000, percent: 42 },
    rateLimits: [],
    cost: { usd: 1.2345 },
    changed: ['context', 'cost'],
  })
  await w.clock.settle()
  expect(w.statuses.at(-1)).toBe('viz · BUILD · build · ctx 42% · $1.23')
})
