import { atom, update } from 'claude-code'
import type { EngineInterface, On, RenderElement } from 'claude-code'

import type { DispatchIssue } from '../types'
import { GATES_KEPT, SPEC_PATH, emptyGates, fit, lastSegment } from './state'
import type { Draw } from './state'

const gates = atom({ plugin: 'session-viz', key: 'gates' } as const, emptyGates())

type Tier = 'planner' | 'builder' | 'scout'

/** How each persona is routed (`.agents/references/model-routing.md` § Agents, § Floors): a pinned tier, `inherit` the session model, or `critic`'s planner floor. */
const ROUTING: Readonly<Record<string, Tier | 'inherit' | 'planner-floor'>> = {
  planner: 'planner',
  'backend-developer': 'builder',
  'frontend-developer': 'builder',
  'frontend-design-validator': 'builder',
  'code-debugger': 'builder',
  'context-document-optimizer': 'builder',
  'code-reviewer': 'inherit',
  'security-reviewer': 'inherit',
  'software-design-expert-review': 'inherit',
  critic: 'planner-floor',
}

/** The personas whose dispatch must carry the seven contract items (review-dispatch-contract § The seven items). */
const REVIEWERS: ReadonlySet<string> = new Set(['code-reviewer', 'critic', 'security-reviewer', 'software-design-expert-review'])

/** Each contract item as the test over a lower-cased prompt that says it is present, in item order 1..7. */
const ITEM_PRESENT: ReadonlyArray<(text: string) => boolean> = [
  text => ['diff --git', '...head', 'git diff'].some(marker => text.includes(marker)),
  text => SPEC_PATH.test(text) || text.includes('no spec —') || text.includes('no spec -'),
  text => text.includes('tasks/todo.md'),
  text => text.includes('ambiguit'),
  text => text.includes('todo(shortcut)') || text.includes('deferrals: none'),
  text => ['introduced', 'pre-existing', 'boundary'].some(marker => text.includes(marker)),
  text => (text.includes('confidence') && text.includes('autofix_class')) || text.includes('failure:'),
]

/** The tier a model string names (an alias or a full id), undefined when it names none. */
export function tierOf(model: string): Tier | undefined {
  const name = model.toLowerCase()
  if (name.includes('opus')) return 'planner'
  if (name.includes('sonnet')) return 'builder'
  if (name.includes('haiku')) return 'scout'
  return undefined
}

/** The off-tier issue text for one spawn (toasted with the mod's prefix), undefined when the dispatch follows model-routing (spec D11). */
export function offTier(e: { subagentType: string; model?: string; parentModel: string }): string | undefined {
  const type = lastSegment(e.subagentType)
  const routing = ROUTING[type]
  if (routing === undefined || e.model === undefined) return undefined
  const tier = tierOf(e.model)
  const says = (expected: string): string => `${type} dispatched on ${e.model} (${tier ?? 'unknown'}); model-routing says ${expected}`
  if (routing === 'inherit') return says('inherit')
  if (routing === 'planner-floor') {
    const parent = tierOf(e.parentModel)
    return tier === 'planner' && parent !== 'planner' ? undefined : says('inherit')
  }
  return tier === undefined || tier === routing ? undefined : says(routing)
}

/** The numbers (1..7) of the contract items a reviewer dispatch prompt lacks; none for any other type. */
export function missingContractItems(subagentType: string, prompt: string): number[] {
  if (!REVIEWERS.has(lastSegment(subagentType))) return []
  const text = prompt.toLowerCase()
  return ITEM_PRESENT.flatMap((present, index) => (present(text) ? [] : [index + 1]))
}

/** Toasts each dispatch issue of one spawn and records it as a row under Gates. */
async function raise($: EngineInterface, issues: DispatchIssue[]): Promise<void> {
  for (const issue of issues) {
    $.ui.toast(`session-viz: ${issue.text}`)
    await update($, gates, current => ({ ...current, dispatch: [...current.dispatch, issue].slice(-GATES_KEPT) }))
  }
}

export function registerDispatch(on: On): void {
  // Every spawn names a type; the matcher keeps this registration distinct from the agents section's.
  on('agent.spawn', { subagentType: /./ }, async ($, e, next) => {
    const started = await next(e)
    const type = lastSegment(e.subagentType)
    const issues: DispatchIssue[] = []
    const tierText = offTier(e)
    if (tierText !== undefined) issues.push({ kind: 'off-tier', type, text: tierText })
    const missing = missingContractItems(e.subagentType, e.prompt)
    if (missing.length > 0) {
      issues.push({ kind: 'contract', type, text: `${type} dispatch missing contract item(s) ${missing.join(', ')}` })
    }
    await raise($, issues)

    return started
  })
}

/** The dispatch issues drawn under the Gates section; nothing while there are none. */
export function DispatchIssues(d: Draw, issues: DispatchIssue[]): RenderElement | null {
  if (issues.length === 0) return null
  const { Box, Text } = d.t

  return (
    <Box flexDirection="column" marginBottom={1}>
      {issues.map((issue, index) => (
        <Text key={String(index)} color="yellow">
          {fit(`⚠ ${issue.text}`, d.width)}
        </Text>
      ))}
    </Box>
  )
}
