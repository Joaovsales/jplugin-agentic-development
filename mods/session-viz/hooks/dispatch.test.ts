import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { missingContractItems, offTier, tierOf } from './dispatch'

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

/** A prompt carrying all seven contract markers (review-dispatch-contract § The seven items). */
const FULL_PROMPT = [
  'Review `git diff` (diff --git a/x b/x) against specs/x.md and tasks/todo.md.',
  '[AMBIGUITY] none emitted',
  'deferrals: none',
  'boundary: review issues introduced by this session',
  'Emit confidence and autofix_class on every finding; failure: say so.',
].join('\n')

/** The world beneath the plugin: the bottoms every `$` call the mod makes needs, and the toasts it raised. */
function world(on: On) {
  const toasts: string[] = []
  on('ui.toast', ($, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', () => ({ value: undefined }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'agent-1' }))
  on('agent.list', () => ({ value: [] }))
  on('session.repo', () => ({ value: null }))
  on('fs.read', () => ({ deny: 'ENOENT: no such file' }))
  const clock = mock.clock(on)
  return { toasts, clock }
}

type Spawn = { subagentType: string; model?: string; parentModel?: string; prompt?: string }

function spawn($: Engine, s: Spawn) {
  return $.agent.spawn({
    tool_use_id: 'tu-1',
    prompt: s.prompt ?? 'work',
    description: 'work',
    subagentType: s.subagentType,
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: s.parentModel ?? 'claude-sonnet-5-5',
    background: true,
    fork: false,
    ...(s.model === undefined ? {} : { model: s.model }),
  })
}

test('tiers: a pinned persona on another tier toasts, a ceiling persona on any model toasts, the critic floor and unlisted types are silent, each toast is a Gates row', async ($, on) => {
  const w = world(on)

  const result = await spawn($, { subagentType: 'backend-developer', model: 'opus' })
  expect(result).toMatchObject({ agentId: 'agent-1' })
  await spawn($, { subagentType: 'jplugin:code-reviewer', model: 'sonnet', prompt: FULL_PROMPT })
  await spawn($, { subagentType: 'critic', model: 'opus', parentModel: 'claude-sonnet-5-5', prompt: FULL_PROMPT })
  await spawn($, { subagentType: 'planner', model: 'opus' })
  await spawn($, { subagentType: 'general-purpose', model: 'haiku' })
  await spawn($, { subagentType: 'backend-developer' })
  await spawn($, { subagentType: 'backend-developer', model: 'sonnet' })
  await spawn($, { subagentType: 'critic', model: 'sonnet', parentModel: 'claude-opus-5-5', prompt: FULL_PROMPT })
  await w.clock.settle()

  // The critic's planner floor (the one allowed override) and the tier of a model string, as pure checks.
  const critic = { subagentType: 'jplugin:critic', model: 'opus' }
  expect(offTier({ ...critic, parentModel: 'claude-sonnet-5-5' })).toBeUndefined()
  expect(offTier({ ...critic, parentModel: 'claude-haiku-5' })).toBeUndefined()
  expect(offTier({ ...critic, parentModel: 'a-custom-model' })).toBeUndefined()
  expect(offTier({ ...critic, parentModel: 'claude-opus-5-5' })).toBe(
    'session-viz: critic dispatched on opus (planner); model-routing says inherit',
  )
  expect(tierOf('Claude-Opus-5-5')).toBe('planner')
  expect(tierOf('haiku')).toBe('scout')
  expect(tierOf('gpt-x')).toBeUndefined()
  expect(offTier({ subagentType: 'planner', model: 'opus', parentModel: 'claude-sonnet-5-5' })).toBeUndefined()
  expect(offTier({ subagentType: 'backend-developer', model: 'gpt-x', parentModel: 'claude-sonnet-5-5' })).toBeUndefined()
  expect(offTier({ subagentType: 'Explore', model: 'opus', parentModel: 'claude-sonnet-5-5' })).toBeUndefined()

  expect(w.toasts).toEqual([
    'session-viz: backend-developer dispatched on opus (planner); model-routing says builder',
    'session-viz: code-reviewer dispatched on sonnet (builder); model-routing says inherit',
    'session-viz: critic dispatched on sonnet (builder); model-routing says inherit',
  ])

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /dispatched on opus \(planner\)/ }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /code-reviewer dispatched on sonnet/ }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^⚠ critic dispatched on sonnet/ }), surface).toBeDefined()
    await ui.unmount()
  }
})

test('contract: a reviewer prompt with all seven markers is silent, one missing items 5 and 6 toasts once, a general-purpose spawn is silent', async ($, on) => {
  const w = world(on)

  await spawn($, { subagentType: 'code-reviewer', prompt: FULL_PROMPT })
  await spawn($, { subagentType: 'general-purpose', prompt: 'no markers at all' })
  await w.clock.settle()
  expect(w.toasts).toEqual([])
  expect(missingContractItems('critic', 'no spec — a pure change')).toEqual([1, 3, 4, 5, 6, 7])

  const partial = FULL_PROMPT.replace('deferrals: none', '').replace('boundary: review issues introduced by this session', '')
  await spawn($, { subagentType: 'jplugin:code-reviewer', prompt: partial })
  await w.clock.settle()
  expect(w.toasts).toEqual(['session-viz: code-reviewer dispatch missing contract item(s) 5, 6'])

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /missing contract item\(s\) 5, 6/ }), surface).toBeDefined()
    await ui.unmount()
  }
})
