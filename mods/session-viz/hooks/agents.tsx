import { atom, update } from 'claude-code'
import type { AgentInfo, EngineInterface, On, RenderElement } from 'claude-code'

import type { AgentRow, Footprint } from '../types'
import { EMPTY_FINDINGS, EVERY, INITIAL_AGENTS, INITIAL_ASKING, INITIAL_SELECTED, MAIN, fit, refreshStatus, seconds } from './state'
import type { Draw } from './state'

const agents = atom({ plugin: 'session-viz', key: 'agents' } as const, INITIAL_AGENTS)
const asking = atom({ plugin: 'session-viz', key: 'asking' } as const, INITIAL_ASKING)
const selected = atom({ plugin: 'session-viz', key: 'selected' } as const, INITIAL_SELECTED)

const SYNC_MS = 5000
const MAX_AGENTS = 200
const MAX_ENTRIES = 40
const MAX_COMMAND = 80
const MAX_PROMPT = 2000
const UNKNOWN_PROMPT = '(spawned before session-viz loaded)'

type ListName = 'read' | 'edited' | 'grepped' | 'commands'
const LISTS: readonly ListName[] = ['read', 'edited', 'grepped', 'commands']

/** An agent row plus how many entries each footprint list dropped past its cap (the contract keeps only the lists). */
type Tracked = AgentRow & { dropped?: Partial<Record<ListName, number>> }

/** Which factory stage an agent definition works in, by its name (factory-board's derivation). */
function stageOfType(type: string): 'plan' | 'build' | 'review' {
  const name = type.toLowerCase()
  if (/review|critic|security|validator/.test(name)) return 'review'
  if (/plan|explore|scout|grill/.test(name)) return 'plan'
  return 'build'
}

function statusOf(engineStatus: AgentInfo['status']): AgentRow['status'] {
  switch (engineStatus) {
    case 'pending':
    case 'running':
    case 'waiting':
    case 'idle':
      return 'running'
    case 'completed':
      return 'done'
    case 'failed':
    case 'killed':
      return 'failed'
    default:
      return engineStatus satisfies never
  }
}

function emptyFootprint(): Footprint {
  return { read: [], edited: [], grepped: [], commands: [], toolCalls: 0, steps: 0, messages: 0 }
}

/** A string field of a tool call, read by name; undefined when absent or not a string. */
function field(call: object, name: string): string | undefined {
  const value = (call as Record<string, unknown>)[name]
  return typeof value === 'string' ? value : undefined
}

/** Which footprint list a tool call lands in, and what it records there. */
function footprintEntry(call: object, tool: string): { list: ListName; entry: string } | undefined {
  switch (tool) {
    case 'Read':
    case 'Glob': {
      const entry = field(call, 'file_path') ?? field(call, 'pattern')
      return entry === undefined ? undefined : { list: 'read', entry }
    }
    case 'Edit':
    case 'Write':
    case 'MultiEdit':
    case 'NotebookEdit': {
      const entry = field(call, 'file_path') ?? field(call, 'notebook_path')
      return entry === undefined ? undefined : { list: 'edited', entry }
    }
    case 'Grep': {
      const pattern = field(call, 'pattern')
      if (pattern === undefined) return undefined
      const path = field(call, 'path')
      return { list: 'grepped', entry: path === undefined ? pattern : `${pattern} in ${path}` }
    }
    case 'Bash': {
      const command = field(call, 'command')
      return command === undefined ? undefined : { list: 'commands', entry: command.slice(0, MAX_COMMAND) }
    }
    default:
      return undefined
  }
}

/** Counts one tool call and adds its entry, keeping the newest MAX_ENTRIES and counting what fell off. */
function withEntry(row: Tracked, found: { list: ListName; entry: string } | undefined): Tracked {
  const footprint = { ...row.footprint, toolCalls: row.footprint.toolCalls + 1 }
  if (found === undefined) return { ...row, footprint }
  const grown = [...footprint[found.list], found.entry]
  const overflow = Math.max(0, grown.length - MAX_ENTRIES)
  footprint[found.list] = grown.slice(overflow)
  const dropped = { ...row.dropped, [found.list]: (row.dropped?.[found.list] ?? 0) + overflow }
  return { ...row, footprint, dropped }
}

/** Keeps at most MAX_AGENTS rows: the oldest finished rows leave first, then the oldest running. */
function capped(rows: AgentRow[]): AgentRow[] {
  const excess = rows.length - MAX_AGENTS
  if (excess <= 0) return rows
  const order = [...rows.filter(row => row.status !== 'running'), ...rows.filter(row => row.status === 'running')]
  const leaving = new Set(order.slice(0, excess))
  return rows.filter(row => !leaving.has(row))
}

/**
 * Folds the engine's own agent list into the rows: new agents join with an empty footprint and a
 * running row follows the engine. A row already done or failed keeps what turn.complete recorded.
 * Returns `known` itself when nothing changed.
 */
function merge(known: AgentRow[], live: AgentInfo[]): AgentRow[] {
  let changed = false
  const next = known.map(row => {
    const agent = live.find(one => one.id === row.agentId)
    if (agent === undefined || row.status !== 'running') return row
    const status = statusOf(agent.status)
    if (status === row.status) return row
    changed = true
    return { ...row, status, outcome: agent.status }
  })
  for (const agent of live) {
    if (next.some(row => row.agentId === agent.id)) continue
    changed = true
    const status = statusOf(agent.status)
    next.push({
      agentId: agent.id,
      type: agent.type,
      description: agent.description,
      prompt: UNKNOWN_PROMPT,
      parentAgentId: agent.parentId,
      status,
      outcome: status === 'running' ? undefined : agent.status,
      ambiguities: [],
      surfaces: [],
      findings: { ...EMPTY_FINDINGS },
      footprint: emptyFootprint(),
    })
  }
  return changed ? capped(next) : known
}

/** Applies `change` to the row of `agentId`, if it is tracked. */
function updateRow(agentId: string, change: (row: Tracked) => Tracked): (list: AgentRow[]) => AgentRow[] {
  return list => list.map(row => (row.agentId === agentId ? change(row) : row))
}

export function registerAgents(on: On): void {
  on('session.start', { cwd: EVERY }, async ($, e, next) => {
    const sync = async () => {
      const live = await $.agent.list()
      let changed = false
      await update($, agents, known => {
        const merged = merge(known, live)
        changed = merged !== known
        return merged
      })
      if (changed) await refreshStatus($)
    }
    await sync()
    $.clock.every(SYNC_MS, () => {
      sync().catch((reason: unknown) => $.ui.log(`agent sync failed: ${String(reason)}`, { to: 'debug' }))
    })

    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.agentId === undefined) return started
    const row: AgentRow = {
      agentId: started.agentId,
      toolUseId: e.tool_use_id,
      type: e.subagentType,
      description: e.description,
      prompt: e.prompt,
      model: e.model,
      resolvedModel: started.model,
      parentModel: e.parentModel,
      parentAgentId: e.parentAgentId,
      status: 'running',
      ambiguities: [],
      surfaces: [],
      findings: { ...EMPTY_FINDINGS },
      footprint: emptyFootprint(),
    }
    await update($, agents, list => capped([...list.filter(one => one.agentId !== row.agentId), row]))
    await refreshStatus($)

    return started
  })

  // A streaming event: the hook is the generator, `yield* next(e)` forwards the response.
  on('turn.step', { agentId: /./ }, async function* ($, e, next) {
    if (e.agentId !== undefined) {
      const { index, messageCount } = e
      await update(
        $,
        agents,
        updateRow(e.agentId, row => ({
          ...row,
          footprint: { ...row.footprint, steps: Math.max(row.footprint.steps, index + 1), messages: messageCount },
        })),
      )
    }

    return yield* next(e)
  })

  on('turn.complete', { agentId: /./ }, async ($, e, next) => {
    if (e.agentId !== undefined) {
      const status: AgentRow['status'] = e.reason === 'answer' ? 'done' : 'failed'
      await update(
        $,
        agents,
        updateRow(e.agentId, row => ({ ...row, status, outcome: e.reason, durationMs: e.durationMs })),
      )
      await refreshStatus($)
    }

    return next(e)
  })

  on('tool.call', { agentId: /./ }, async ($, e, next) => {
    if (e.agentId !== undefined) {
      const found = footprintEntry(e, String(e.tool))
      await update($, agents, updateRow(e.agentId, row => withEntry(row, found)))
    }

    return next(e)
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    const who = e.agentId ?? MAIN
    await update($, asking, list => (list.includes(who) ? list : [...list, who]))
    try {
      return await next(e)
    } finally {
      await update($, asking, list => list.filter(one => one !== who))
    }
  })
}

function glyph(row: AgentRow, isAsking: boolean): string {
  if (isAsking) return '⚑'
  if (row.status === 'running') return '◐'
  if (row.status === 'failed') return '✗'
  return row.ambiguities.length > 0 ? '⚑' : '✓'
}

/** `running`, `12s`, `killed 3s`: what the row's tail says. */
function tail(row: AgentRow): string {
  if (row.status === 'running') return 'running'
  const took = seconds(row.durationMs)
  if (row.status === 'done') return took === '' ? 'done' : took
  return [row.outcome ?? 'failed', took].filter(part => part !== '').join(' ')
}

/** The rows depth-first: roots in spawn order, each followed by its children; an unknown parent makes a root. */
function inTreeOrder(rows: AgentRow[]): Array<{ row: AgentRow; depth: number }> {
  const known = new Set(rows.map(row => row.agentId))
  const ordered: Array<{ row: AgentRow; depth: number }> = []
  const seen = new Set<string>()
  const visit = (row: AgentRow, depth: number): void => {
    if (seen.has(row.agentId)) return
    seen.add(row.agentId)
    ordered.push({ row, depth })
    for (const child of rows) if (child.parentAgentId === row.agentId) visit(child, depth + 1)
  }
  for (const row of rows) {
    if (row.parentAgentId === undefined || row.parentAgentId === row.agentId || !known.has(row.parentAgentId)) visit(row, 0)
  }
  for (const row of rows) visit(row, 0)
  return ordered
}

export function AgentsSection($: EngineInterface, d: Draw, rows: AgentRow[], open: string[], picked: string | null): RenderElement {
  const { Box, Text, Button } = d.t
  if (rows.length === 0) {
    return (
      <Box flexDirection="column" marginBottom={1}>
        <Text bold>AGENTS</Text>
        <Text dimColor>no sub-agents yet</Text>
      </Box>
    )
  }
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>AGENTS</Text>
      {inTreeOrder(rows).map(({ row, depth }) => {
        const indent = '  '.repeat(depth)
        const mark = row.agentId === d.view ? '▶ ' : ''
        const text = `${glyph(row, open.includes(row.agentId))} ${mark}${stageOfType(row.type)} ${row.type} · ${row.description} · ${tail(row)}`
        return (
          <Button
            key={`agent:${row.agentId}`}
            plain
            variant={row.agentId === picked ? 'primary' : undefined}
            label={indent + fit(text, d.width - indent.length)}
            onPress={() => {
              // Select it (again to clear) and bring its spawning row into view.
              void update($, selected, current => (current === row.agentId ? null : row.agentId))
              if (row.toolUseId !== undefined) {
                $.ui
                  .scroll({ to: { requestId: row.toolUseId }, block: 'center' })
                  .catch((reason: unknown) => $.ui.log(`scroll to ${row.toolUseId} failed: ${String(reason)}`, { to: 'debug' }))
              }
            }}
          />
        )
      })}
    </Box>
  )
}

/** `read [a.md, b.md] +2 more`, cut to `width` before the `+n more` so the count stays visible; undefined for an empty list. */
function listLine(row: Tracked, list: ListName, width: number): string | undefined {
  const entries = row.footprint[list]
  if (entries.length === 0) return undefined
  const more = row.dropped?.[list] ?? 0
  const suffix = more > 0 ? ` +${more} more` : ''
  return fit(`${list} [${entries.join(', ')}]`, width - suffix.length) + suffix
}

/** The spawn prompt's first MAX_PROMPT characters as lines, then `… +n chars` when it was longer. */
function promptLines(prompt: string): string[] {
  const lines = prompt.slice(0, MAX_PROMPT).split('\n').filter(line => line.trim() !== '')
  return prompt.length > MAX_PROMPT ? [...lines, `… +${prompt.length - MAX_PROMPT} chars`] : lines
}

function detailLines(row: Tracked, width: number): string[] {
  const { footprint } = row
  const counts = Object.entries(row.findings)
    .filter(([, count]) => count > 0)
    .map(([severity, count]) => `${severity} ${count}`)
  return [
    `${row.type} · ${row.description}`,
    `requested ${row.model ?? 'inherit'} · resolved ${row.resolvedModel ?? '?'}`,
    `parent ${row.parentModel ?? '?'} · under ${row.parentAgentId ?? 'main'}`,
    [
      row.status,
      row.outcome,
      seconds(row.durationMs),
      `${footprint.toolCalls} tool calls`,
      `${footprint.steps} steps`,
      `${footprint.messages} messages`,
    ]
      .filter(part => part !== undefined && part !== '')
      .join(' · '),
    ...promptLines(row.prompt),
    ...LISTS.map(list => listLine(row, list, width)).filter((line): line is string => line !== undefined),
    ...row.ambiguities,
    ...row.surfaces,
    ...(counts.length === 0 ? [] : [`findings ${counts.join(' · ')}`]),
  ]
}

export function DrillDown(d: Draw, rows: AgentRow[], picked: string | null): RenderElement {
  const { Box, Text } = d.t
  const row = picked === null ? undefined : rows.find(one => one.agentId === picked)
  if (row === undefined) {
    return (
      <Box flexDirection="column">
        <Text bold>AGENT</Text>
        <Text dimColor>no agent selected</Text>
      </Box>
    )
  }
  return (
    <Box flexDirection="column">
      <Text bold>AGENT</Text>
      {detailLines(row, d.width).map(line => (
        <Text wrap="truncate-end">{fit(line, d.width)}</Text>
      ))}
    </Box>
  )
}
