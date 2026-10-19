import type { On, RenderElement } from 'claude-code'

import type { DispatchIssue } from '../types'
import type { Draw } from './state'

/** Slice 5 fills this file: the tier table and off-tier rule (D11), the seven contract markers (D10), their toasts and `DispatchIssues`. */
export function registerDispatch(_on: On): void {}

/** The dispatch issues drawn under the Gates section; nothing while there are none. */
export function DispatchIssues(_d: Draw, _issues: DispatchIssue[]): RenderElement | null {
  return null
}
