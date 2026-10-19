import type { EngineInterface, On, RenderElement } from 'claude-code'

import type { AgentRow } from '../types'
import type { Draw } from './state'

/** Slice 2 fills this file: the tree, the footprints, the `$.agent.list()` merge and the drill-down. */
export function registerAgents(_on: On): void {}

export function AgentsSection(_$: EngineInterface, d: Draw, _agents: AgentRow[], _asking: string[], _selected: string | null): RenderElement {
  const { Box, Text } = d.t
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>AGENTS</Text>
      <Text dimColor>no sub-agents yet</Text>
    </Box>
  )
}

export function DrillDown(_$: EngineInterface, d: Draw, _agents: AgentRow[], _selected: string | null): RenderElement {
  const { Box, Text } = d.t
  return (
    <Box flexDirection="column">
      <Text bold>AGENT</Text>
      <Text dimColor>no agent selected</Text>
    </Box>
  )
}
