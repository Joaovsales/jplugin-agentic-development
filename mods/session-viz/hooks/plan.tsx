import type { On, RenderElement } from 'claude-code'

import type { PlanProgress } from '../types'
import type { Draw } from './state'

/** Slice 3 fills this file: `parsePlan`, the active-block choice (D9), the re-read triggers and `PlanSection`. */
export function registerPlan(_on: On): void {}

export function PlanSection(d: Draw, _plan: PlanProgress | null): RenderElement {
  const { Box, Text } = d.t
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>PLAN</Text>
      <Text dimColor>no plan block</Text>
    </Box>
  )
}
