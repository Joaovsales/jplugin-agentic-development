import type { On, RenderElement } from 'claude-code'

import type { Gates } from '../types'
import type { Draw } from './state'

/** Slice 4 fills this file: the finding, ambiguity, surface, Verdict and Receipt parsers, the receipt reader (D12), the STOP toast and `GatesSection`. */
export function registerGates(_on: On): void {}

export function GatesSection(d: Draw, _gates: Gates): RenderElement {
  const { Box, Text } = d.t
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>GATES</Text>
      <Text dimColor>no receipt yet</Text>
    </Box>
  )
}
