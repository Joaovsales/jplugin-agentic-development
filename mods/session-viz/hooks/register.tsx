import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { AgentsSection, DrillDown, registerAgents } from './agents'
import { DispatchIssues, registerDispatch } from './dispatch'
import { GatesSection, registerGates } from './gates'
import { PhaseSection, registerPhase } from './phase'
import { PlanSection, registerPlan } from './plan'
import {
  INITIAL_AGENTS,
  INITIAL_ASKING,
  INITIAL_MEASURE,
  INITIAL_PHASE,
  INITIAL_PLAN,
  INITIAL_SELECTED,
  PANE,
  TITLE,
  WIDE_COLUMNS,
  emptyGates,
  refreshStatus,
} from './state'
import type { Draw } from './state'

const phase = atom({ plugin: 'session-viz', key: 'phase' } as const, INITIAL_PHASE)
const agents = atom({ plugin: 'session-viz', key: 'agents' } as const, INITIAL_AGENTS)
const asking = atom({ plugin: 'session-viz', key: 'asking' } as const, INITIAL_ASKING)
const selected = atom({ plugin: 'session-viz', key: 'selected' } as const, INITIAL_SELECTED)
const plan = atom({ plugin: 'session-viz', key: 'plan' } as const, INITIAL_PLAN)
const gates = atom({ plugin: 'session-viz', key: 'gates' } as const, emptyGates())
const measure = atom({ plugin: 'session-viz', key: 'measure' } as const, INITIAL_MEASURE)

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'session-viz',
      description: 'Show how this jplugin session is going: phase, plan, sub-agents and quality gates',
    })
    void $.ui.open({ id: PANE, title: TITLE })
    await refreshStatus($)

    return next(e)
  })

  on('command.run', { command: 'session-viz' }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE, focus: true })

    return { text: 'Session pane opened.' }
  })

  on('session.measure', async ($, e, next) => {
    await update($, measure, current => ({
      percent: e.context.percent ?? current.percent,
      usd: e.cost?.usd ?? current.usd,
    }))
    await refreshStatus($)

    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const t = $.ui.resolve(e)
    const { Box } = t
    const [ph, pl, ag, open, picked, ga] = await Promise.all([
      read($, phase),
      read($, plan),
      read($, agents),
      read($, asking),
      read($, selected),
      read($, gates),
    ])
    const width = e.props.bodyColumns
    const isWide = width >= WIDE_COLUMNS
    const leftWidth = isWide ? Math.floor(width / 2) : width
    const left: Draw = { t, width: Math.max(1, leftWidth - 1), view: e.props.view.agentId }
    const right: Draw = { ...left, width: Math.max(1, isWide ? width - leftWidth : width) }

    return (
      <Box flexDirection={isWide ? 'row' : 'column'}>
        <Box flexDirection="column" width={leftWidth} paddingRight={isWide ? 1 : 0}>
          {PhaseSection(left, ph)}
          {PlanSection(left, pl)}
          {AgentsSection($, left, ag, open, picked)}
          {GatesSection(left, ga)}
          {DispatchIssues(left, ga.dispatch)}
        </Box>
        <Box flexDirection="column" width={right.width}>
          {DrillDown($, right, ag, picked)}
        </Box>
      </Box>
    )
  })

  registerPhase(on)
  registerPlan(on)
  registerAgents(on)
  registerGates(on)
  registerDispatch(on)
}
