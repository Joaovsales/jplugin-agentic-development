import { atom, update } from 'claude-code'
import type { On, RenderElement } from 'claude-code'

import type { Phase, PhaseState } from '../types'
import { INITIAL_PHASE, SPEC_PATH, fit, lastSegment, refreshStatus } from './state'
import type { Draw } from './state'

const phase = atom({ plugin: 'session-viz', key: 'phase' } as const, INITIAL_PHASE)

/** Which phase each jplugin skill puts the session in (spec D8); any other skill shows as running and leaves the phase. */
const PHASE_OF: Readonly<Record<string, Phase>> = {
  prd: 'PLAN',
  'grill-me': 'PLAN',
  grilling: 'PLAN',
  brainstorm: 'PLAN',
  plan: 'PLAN',
  'system-design-planning': 'PLAN',
  slice: 'PLAN',
  'visual-plan': 'PLAN',
  build: 'BUILD',
  yolo: 'BUILD',
  'auto-push': 'BUILD',
  'make-it-simpler': 'BUILD',
  'quality-gate': 'GATE',
  'software-design-expert-review': 'GATE',
  'security-scan': 'GATE',
  'verify-evidence': 'GATE',
  'wrap-up-session': 'WRAP-UP',
}

/** `[ROUTE] lane=<lane> | chain=<skill, …> | reason: …`, as /go prints it. */
const ROUTE = /^\s*\[ROUTE\]\s*lane=([^|\r\n]+?)\s*\|\s*chain=([^|\r\n]+?)\s*(?:\||$)/m

export function phaseOfSkill(skill: string): Phase | undefined {
  return PHASE_OF[lastSegment(skill)]
}

export function parseRoute(text: string): { lane: string; chain: string } | undefined {
  const found = ROUTE.exec(text)
  return found === null ? undefined : { lane: found[1]!.trim(), chain: found[2]!.trim() }
}

export function parseSpec(text: string): string | undefined {
  return SPEC_PATH.exec(text)?.[0]
}

export function registerPhase(on: On): void {
  on('skill.prompt', async ($, e, next) => {
    const result = await next(e)
    const skill = lastSegment(e.skill)
    const nextPhase = phaseOfSkill(e.skill)
    await update($, phase, current => ({ ...current, skill, phase: nextPhase ?? current.phase }))
    await refreshStatus($)

    return result
  })

  // A streaming event: the hook is the generator, `yield* next(e)` forwards the response and
  // evaluates to the step's result. The route is read off every main-loop step, not only the
  // turn's final answer.
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    if (e.agentId === undefined) {
      const route = parseRoute(result.answer)
      if (route !== undefined) await update($, phase, current => ({ ...current, ...route }))
    }

    return result
  })

  on('prompt.submit', async ($, e, next) => {
    const result = await next(e)
    const spec = parseSpec(e.text)
    if (spec !== undefined) await update($, phase, current => ({ ...current, spec }))

    return result
  })
}

export function PhaseSection(d: Draw, state: PhaseState): RenderElement {
  const { Box, Text } = d.t
  const head = state.skill === undefined ? undefined : `${state.phase} · ${state.skill}`
  const route = state.lane === undefined ? undefined : `route ${state.lane}${state.chain === undefined ? '' : ` · ${state.chain}`}`
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>PHASE</Text>
      {head === undefined ? (
        <Text dimColor>{fit(`${state.phase} · no skill running`, d.width)}</Text>
      ) : (
        <Text>{fit(head, d.width)}</Text>
      )}
      {route !== undefined && <Text dimColor>{fit(route, d.width)}</Text>}
      {state.spec !== undefined && <Text dimColor>{fit(`spec ${state.spec}`, d.width)}</Text>}
    </Box>
  )
}
