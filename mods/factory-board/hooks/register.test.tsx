import type { SessionMessage } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const SURFACES = ['terminal', 'desktop'] as const

const PANE = {
  plugin: 'factory-board',
  component: 'Pane' as const,
  requestId: 'factory-board',
  props: {
    title: 'Factory',
    isFocused: false,
    bodyColumns: 200,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
}

const SPAWN = {
  tool_use_id: 'tu-1',
  prompt: 'Review slice 3.',
  description: 'review slice 3',
  subagentType: 'code-reviewer',
  provider: { plugin: 'engine', tier: 'core' as const },
  parentModel: 'claude-sonnet-5-5',
  background: true,
  fork: false,
}

const TAIL: SessionMessage[] = [
  { role: 'user', text: 'Review slice 3.', toolUses: [] },
  { role: 'assistant', text: 'Looks fine, two nits.', toolUses: [] },
]

test('a spawned agent is a card in its stage column, moves on completion, and opens on press', async ($, on) => {
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.scroll', () => ({}))
  on('session.messages', () => ({ value: TAIL }))

  await $.agent.spawn(SPAWN)

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /^REVIEW 1$/ })).toBeDefined()
    expect((await ui.find({ key: 'card:agent-1' }))?.text).toContain('code-reviewer · review slice 3')
    await ui.unmount()
  }

  await $.turn.complete({
    answer: 'Done.\n[AMBIGUITY] which lint config | options: A) root B) package | picked: A | reason: closer',
    durationMs: 12_000,
    isAborted: false,
    turnId: 'turn-1',
    agentId: 'agent-1',
    reason: 'answer',
  })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /^HUMAN 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^REVIEW 0$/ })).toBeDefined()

    const pressed = await ui.press({ key: 'card:agent-1' })
    expect(pressed?.element).toBe('card:agent-1')
    expect(await ui.find({ type: 'Text', text: /^code-reviewer · review slice 3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /done · 12s · agent agent-1 · 1 \[AMBIGUITY\]/ })).toBeDefined()
    expect(await ui.find({ text: /Looks fine, two nits/ })).toBeDefined()

    await ui.press({ key: 'card:agent-1' })
    expect(await ui.find({ type: 'Text', text: /^code-reviewer · review slice 3$/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('an open AskUserQuestion in the main loop shows the waiting line until it is answered', async ($, on) => {
  let answer: (() => void) | undefined
  let reached: (() => void) | undefined
  const held = new Promise<void>(resolve => {
    answer = resolve
  })
  const isReached = new Promise<void>(resolve => {
    reached = resolve
  })
  on('tool.call', { tool: 'AskUserQuestion' }, async () => {
    reached?.()
    await held
    return { result: { questions: [], answers: {} } }
  })

  const call = $.tool.call({
    tool: 'AskUserQuestion',
    questions: [
      {
        question: 'Which one?',
        header: 'Pick',
        options: [
          { label: 'A', description: 'a' },
          { label: 'B', description: 'b' },
        ],
        multiSelect: false,
      },
    ],
  })

  await isReached

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /waiting for your answer/ })).toBeDefined()
    await ui.unmount()
  }

  answer?.()
  await call

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /waiting for your answer/ })).toBeUndefined()
  await ui.unmount()
})
