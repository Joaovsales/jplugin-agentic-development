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

const SPAWN = {
  tool_use_id: 'tu-1',
  prompt: 'Review slice 3.',
  description: 'review slice 3',
  subagentType: 'code-reviewer',
  provider: { plugin: 'engine', tier: 'core' as const },
  parentModel: 'claude-sonnet-5-5',
  background: true,
  fork: false,
  model: 'sonnet',
}

/** The world beneath the plugin: every call on `$` the mod makes answered from memory; spawns are numbered by their description. */
function world(on: On) {
  const logs: string[] = []
  const listed: Array<{ id: string; description: string; type: string; status: 'killed' | 'running' | 'completed' | 'failed' }> = []
  let messageCalls = 0
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('agent.list', () => ({ value: listed }))
  on('session.repo', () => ({ value: null }))
  on('fs.read', () => ({ deny: 'ENOENT: no such file' }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.messages', () => {
    messageCalls += 1
    return { value: [] }
  })
  on('agent.spawn', ($, e) => ({ model: 'claude-sonnet-5-5', agentId: `agent-${e.description}` }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.log', ($, e) => {
    logs.push(e.text)
    return { value: undefined }
  })
  on('tool.call', () => ({ result: {} as never }))
  on('turn.step', async function* ($, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn' as const,
      usage: null,
    }
  })
  const clock = mock.clock(on)
  return { logs, listed, clock, messageCalls: () => messageCalls }
}

/** A tool call raised inside a sub-agent's loop: `agentId` rides the event, though the call's input type does not name it. */
function calledBy($: { tool: { call: (input: never) => Promise<unknown> } }, agentId: string, input: { tool: string } & Record<string, unknown>) {
  return $.tool.call({ ...input, agentId } as never)
}

async function drain(stream: AsyncIterable<unknown>): Promise<void> {
  for await (const _chunk of stream) {
    // read to the end so the result settles
  }
}

test('tree: a reviewer under a running parent is indented with its stage, ends as a check with seconds, and a killed list-only agent is a root cross', async ($, on) => {
  const w = world(on)
  await $.agent.spawn({ ...SPAWN, tool_use_id: 'tu-0', description: 'gp', subagentType: 'general-purpose' })
  await $.agent.spawn({ ...SPAWN, description: 'cr', parentAgentId: 'agent-gp' })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const parent = await ui.find({ key: 'agent:agent-gp' })
    const child = await ui.find({ key: 'agent:agent-cr' })
    expect(parent?.text).toContain('◐')
    expect(parent?.text?.startsWith(' ')).toBe(false)
    expect(child?.text?.startsWith('  ')).toBe(true)
    expect(child?.text).toContain('◐')
    expect(child?.text).toContain('review')
    expect(child?.text).toContain('code-reviewer')
    await ui.unmount()
  }

  await $.turn.complete({
    answer: 'Done.',
    durationMs: 12_000,
    isAborted: false,
    turnId: 'turn-1',
    agentId: 'agent-cr',
    reason: 'answer',
  })

  w.listed.push({ id: 'agent-k', description: 'orphan', type: 'Explore', status: 'killed' })
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  await w.clock.advance(5000)

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const child = (await ui.find({ key: 'agent:agent-cr' }))?.text ?? ''
    expect(child).toContain('✓')
    expect(child).toContain('12s')
    const killed = (await ui.find({ key: 'agent:agent-k' }))?.text ?? ''
    expect(killed).toContain('✗')
    expect(killed.startsWith(' ')).toBe(false)
    expect(killed).toContain('orphan')
    await ui.unmount()
  }
})

test('footprint: Read, Edit, Grep, Bash and two steps give the lists and counts; the 41st read drops the oldest and says +1 more', async ($, on) => {
  const w = world(on)
  await $.agent.spawn({ ...SPAWN, description: 'x' })
  const agentId = 'agent-x'

  await calledBy($, agentId, { tool: 'Read', file_path: 'a.md' })
  await calledBy($, agentId, { tool: 'Edit', file_path: 'b.ts', old_string: 'a', new_string: 'b' })
  await calledBy($, agentId, { tool: 'Grep', pattern: 'foo', path: 'src' })
  await calledBy($, agentId, { tool: 'Bash', command: 'npm test' })
  await drain($.turn.step({ turnId: 'turn-1', index: 0, model: 'claude-sonnet-5-5', messageCount: 3, agentId }))
  await drain($.turn.step({ turnId: 'turn-1', index: 1, model: 'claude-sonnet-5-5', messageCount: 7, agentId }))

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: `agent:${agentId}` })
    expect(await ui.find({ type: 'Text', text: /^read \[a\.md\]$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^edited \[b\.ts\]$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^grepped \[foo in src\]$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^commands \[npm test\]$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /4 tool calls · 2 steps · 7 messages/ })).toBeDefined()
    await ui.press({ key: `agent:${agentId}` })
    await ui.unmount()
  }

  for (let i = 0; i < 40; i += 1) await calledBy($, agentId, { tool: 'Read', file_path: `f${i}.md` })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: `agent:${agentId}` })
  const read = (await ui.find({ type: 'Text', text: /^read \[/ }))?.text ?? ''
  expect(read).not.toContain('a.md')
  expect(read.startsWith('read [f0.md, f1.md')).toBe(true)
  expect(read).toContain('+1 more')
  await ui.unmount()
  expect(w.messageCalls()).toBe(0)
})

test('drill-down: pressing a row answers its key, scrolls to the spawning tool call and opens the brief; pressing again closes it; no transcript is read', async ($, on) => {
  const w = world(on)
  await $.agent.spawn({ ...SPAWN, description: 'cr', parentAgentId: 'agent-gp', prompt: `Review slice 3. ${'x'.repeat(2100)}` })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: 'no agent selected' })).toBeDefined()

    const pressed = await ui.press({ key: 'agent:agent-cr' })
    expect(pressed?.element).toBe('agent:agent-cr')
    await w.clock.settle()
    // A pane press cannot reach a transcript row in the test world, so the engine's refusal names the row the press asked for.
    expect(w.logs.at(-1)).toMatch(/^scroll to tu-1 failed/)
    expect(await ui.find({ type: 'Text', text: 'no agent selected' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^code-reviewer · cr$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^requested sonnet · resolved claude-sonnet-5-5$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^parent claude-sonnet-5-5 · under agent-gp$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^running · 0 tool calls · 0 steps · 0 messages$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^… \+\d+ chars$/ })).toBeDefined()

    await ui.press({ key: 'agent:agent-cr' })
    expect(await ui.find({ type: 'Text', text: /^code-reviewer · cr$/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'no agent selected' })).toBeDefined()
    await ui.unmount()
  }
  expect(w.messageCalls()).toBe(0)
})
