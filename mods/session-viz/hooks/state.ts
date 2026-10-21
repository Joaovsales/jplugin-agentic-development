import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface } from 'claude-code'

import type { AgentRow, FindingCounts, Gates, Measure, PhaseState, PlanProgress, Severity, Toasted } from '../types'

export const PANE = 'session-viz'
export const TITLE = 'Session'
export const MAIN = 'main'
/** From this many body columns the drill-down is a right column beside the sections (spec D6). */
export const WIDE_COLUMNS = 120

/** The severities of a four-axis finding, in the order the Gates section lists them. */
export const SEVERITIES: readonly Severity[] = ['MUST-FIX', 'SHOULD-FIX', 'NITPICK']

/** One count per severity, each from `count`. */
export function findingCounts(count: (severity: Severity) => number): FindingCounts {
  return Object.fromEntries(SEVERITIES.map(severity => [severity, count(severity)])) as FindingCounts
}

export const EMPTY_FINDINGS = findingCounts(() => 0)

/** Entries kept per Gates list (ambiguities, surfaces, dispatch issues); the oldest leave first. */
export const GATES_KEPT = 50

export function emptyGates(): Gates {
  return { receipt: { state: 'none' }, findings: { ...EMPTY_FINDINGS }, ambiguities: [], surfaces: [], dispatch: [] }
}

// Every value a drawing or a toast decision reads lives in $.state (spec D4): a hot reload
// starts the module's own variables over and keeps these. The engine's validator reads each
// `atom(...)` reference in the file that calls `read` or `update` on it, so every module
// declares the atoms it touches with `{ plugin: 'session-viz', key }` written out and one of
// these initials; the contract is `types/index.d.ts`.
export const INITIAL_PHASE: PhaseState = { phase: 'idle' }
export const INITIAL_AGENTS: AgentRow[] = []
export const INITIAL_ASKING: string[] = []
export const INITIAL_SELECTED: string | null = null
export const INITIAL_PLAN: PlanProgress | null = null
export const INITIAL_MEASURE: Measure = {}
export const INITIAL_TOASTED: Toasted = { fingerprints: [], turns: [] }

const phase = atom({ plugin: 'session-viz', key: 'phase' } as const, INITIAL_PHASE)
const agents = atom({ plugin: 'session-viz', key: 'agents' } as const, INITIAL_AGENTS)
const plan = atom({ plugin: 'session-viz', key: 'plan' } as const, INITIAL_PLAN)
const measure = atom({ plugin: 'session-viz', key: 'measure' } as const, INITIAL_MEASURE)

/** The elements every surface's table has; what a section draws with. */
export type Table = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button'>

/** What a section's render receives: the surface's elements, the columns it may fill, the agent in view. */
export type Draw = {
  t: Table
  width: number
  view?: string
}

/** One line of at most `width` cells, ending in `…` when cut. */
export function fit(text: string, width: number): string {
  const line = text.replace(/\s+/g, ' ').trim()
  if (width <= 1) return line.slice(0, Math.max(0, width))
  return line.length <= width ? line : `${line.slice(0, width - 1)}…`
}

/** `12s` for 12000 ms; '' for none. */
export function seconds(ms: number | undefined): string {
  return ms === undefined ? '' : `${Math.round(ms / 1000)}s`
}

/** A spec path as a prompt, a plan block or a dispatch names it: `specs/<x>.md`. */
export const SPEC_PATH = /specs\/[^\s`'"<>|()]+\.md/

/**
 * A matcher that selects every event. The engine refuses a second matcher-less hook on one
 * event in a plugin, and register.tsx holds the matcher-less session.start, so every other
 * section's hook on a shared event carries one.
 */
export const EVERY = /^/

/** The segment after the last `:`: `jplugin:build` → `build`, `build` → `build`. */
export function lastSegment(name: string): string {
  return name.slice(name.lastIndexOf(':') + 1)
}

/**
 * The status line: `viz · <PHASE> · <skill> · slice k/N · ctx NN% · $X.XX · agents R/T`,
 * every unknown field left out.
 */
export function statusLine(ph: PhaseState, pl: PlanProgress | null, me: Measure, ag: AgentRow[]): string {
  const running = ag.filter(row => row.status === 'running').length
  const parts: Array<string | undefined> = [
    'viz',
    ph.phase,
    ph.skill,
    pl === null ? undefined : `slice ${pl.closed}/${pl.total}`,
    me.percent === undefined ? undefined : `ctx ${me.percent}%`,
    me.usd === undefined ? undefined : `$${me.usd.toFixed(2)}`,
    ag.length === 0 ? undefined : `agents ${running}/${ag.length}`,
  ]
  return parts.filter((part): part is string => part !== undefined).join(' · ')
}

/** Rebuilds the status line from the atoms: the shell's first draw at session.start; every later redraw comes through `updateStatus`. */
export async function refreshStatus($: EngineInterface): Promise<void> {
  const [ph, pl, me, ag] = await Promise.all([read($, phase), read($, plan), read($, measure), read($, agents)])
  $.ui.status(statusLine(ph, pl, me, ag))
}

/** The atoms the status line draws from, by key. */
type StatusKey = 'phase' | 'agents' | 'plan' | 'measure'

/**
 * Updates one of the status line's atoms and redraws the line when the value changed (an updater
 * returning `current` draws nothing): the one way a section writes a status-line field. Each atom is
 * named at its own `update` call because the engine's scan lists what the module writes from them.
 */
export async function updateStatus($: EngineInterface, key: 'phase', change: (current: PhaseState) => PhaseState): Promise<void>
export async function updateStatus($: EngineInterface, key: 'agents', change: (current: AgentRow[]) => AgentRow[]): Promise<void>
export async function updateStatus($: EngineInterface, key: 'plan', change: (current: PlanProgress | null) => PlanProgress | null): Promise<void>
export async function updateStatus($: EngineInterface, key: 'measure', change: (current: Measure) => Measure): Promise<void>
export async function updateStatus($: EngineInterface, key: StatusKey, change: (current: never) => unknown): Promise<void> {
  let changed = false
  const tracked =
    <T>(apply: (current: T) => T) =>
    (current: T): T => {
      const next = apply(current)
      changed = next !== current
      return next
    }
  switch (key) {
    case 'phase':
      await update($, phase, tracked(change as (current: PhaseState) => PhaseState))
      break
    case 'agents':
      await update($, agents, tracked(change as (current: AgentRow[]) => AgentRow[]))
      break
    case 'plan':
      await update($, plan, tracked(change as (current: PlanProgress | null) => PlanProgress | null))
      break
    case 'measure':
      await update($, measure, tracked(change as (current: Measure) => Measure))
      break
  }
  if (changed) await refreshStatus($)
}
