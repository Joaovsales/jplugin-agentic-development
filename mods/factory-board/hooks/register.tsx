import { atom, read, update } from 'claude-code'
import type { AgentInfo, EngineInterface, Register, SessionMessage } from 'claude-code'

import type { Card, Stage } from '../types'

const PANE = 'factory-board'
const MAIN = 'main'
const SYNC_MS = 5000
const MAX_CARDS = 100
const TAIL_ROWS = 6

const cards = atom({ plugin: 'factory-board', key: 'cards' } as const, [] as Card[])
const asking = atom({ plugin: 'factory-board', key: 'asking' } as const, [] as string[])
const selected = atom({ plugin: 'factory-board', key: 'selected' } as const, null as string | null)

const COLUMNS: ReadonlyArray<{ stage: Stage; title: string }> = [
  { stage: 'plan', title: 'PLAN' },
  { stage: 'build', title: 'BUILD' },
  { stage: 'review', title: 'REVIEW' },
  { stage: 'human', title: 'HUMAN' },
  { stage: 'done', title: 'DONE' },
]

const MIN_COLUMN = 16

/** Which factory stage an agent definition works in, by its name. */
function stageOfType(type: string): Stage {
  const name = type.toLowerCase()
  if (/review|critic|security|validator/.test(name)) return 'review'
  if (/plan|explore|scout|grill/.test(name)) return 'plan'
  return 'build'
}

/** The column a card sits in right now. */
function stageOf(card: Card, isAsking: boolean): Stage {
  if (isAsking) return 'human'
  if (card.status !== 'running') return card.ambiguities > 0 ? 'human' : 'done'
  return stageOfType(card.type)
}

function statusOf(engineStatus: AgentInfo['status']): Card['status'] {
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

function countAmbiguities(answer: string): number {
  return answer.split('\n').filter(line => line.trimStart().startsWith('[AMBIGUITY]')).length
}

function glyph(card: Card, isAsking: boolean): string {
  if (isAsking) return '⚑'
  if (card.status === 'running') return '◐'
  if (card.status === 'failed') return '✗'
  return card.ambiguities > 0 ? '⚑' : '✓'
}

function fit(text: string, width: number): string {
  const line = text.replace(/\s+/g, ' ').trim()
  if (width <= 1) return line.slice(0, Math.max(0, width))
  return line.length <= width ? line : `${line.slice(0, width - 1)}…`
}

function cardLabel(card: Card, isAsking: boolean, isViewed: boolean, width: number): string {
  const mark = isViewed ? '▶ ' : ''
  return fit(`${glyph(card, isAsking)} ${mark}${card.type} · ${card.description}`, width)
}

function seconds(ms: number | undefined): string {
  return ms === undefined ? '' : ` · ${Math.round(ms / 1000)}s`
}

/**
 * Fold the engine's own agent list into the cards: new agents join and running cards follow the
 * engine. A card already done or failed keeps the status its turn.complete recorded.
 */
function merge(known: Card[], live: AgentInfo[]): Card[] {
  const next = known.map(card => {
    const agent = live.find(one => one.id === card.agentId)
    if (agent === undefined || card.status !== 'running') return card
    const status = statusOf(agent.status)
    return status === card.status ? card : { ...card, status }
  })
  for (const agent of live) {
    if (next.some(card => card.agentId === agent.id)) continue
    next.push({
      agentId: agent.id,
      type: agent.type,
      description: agent.description,
      parentAgentId: agent.parentId,
      status: statusOf(agent.status),
      ambiguities: 0,
    })
  }
  return next.slice(-MAX_CARDS)
}

function summary(message: SessionMessage): string {
  if (message.text.trim() !== '') return message.text
  if (message.toolUses.length > 0) return message.toolUses.map(use => use.tool).join(', ')
  if (message.toolResults !== undefined && message.toolResults.length > 0) {
    return `${message.toolResults.length} tool result(s)`
  }
  return '(no text)'
}

async function transcriptTail($: EngineInterface, agentId: string): Promise<string[]> {
  const found = await $.session.messages({ agentId })
  if (!Array.isArray(found)) return [`transcript unavailable: ${found.deny}`]
  return found.slice(-TAIL_ROWS).map(message => `${message.role === 'user' ? '›' : '•'} ${summary(message)}`)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'factory-board',
      description: 'Show the sub-agents of this session as a Kanban board',
    })
    const sync = async () => {
      const live = await $.agent.list()
      if (live.length === 0) return
      await update($, cards, known => merge(known, live))
    }
    await sync()
    void $.ui.open({ id: PANE, title: 'Factory' })
    $.clock.every(SYNC_MS, () => void sync())

    return next(e)
  })

  on('command.run', { command: 'factory-board' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Factory', focus: true })

    return { text: 'Factory board opened.' }
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.agentId === undefined) return started
    const card: Card = {
      agentId: started.agentId,
      toolUseId: e.tool_use_id,
      type: e.subagentType,
      description: e.description,
      parentAgentId: e.parentAgentId,
      status: 'running',
      ambiguities: 0,
    }
    await update($, cards, list =>
      [...list.filter(one => one.agentId !== card.agentId), card].slice(-MAX_CARDS),
    )

    return started
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) {
      const agentId = e.agentId
      const status: Card['status'] = e.reason === 'answer' ? 'done' : 'failed'
      const ambiguities = countAmbiguities(e.answer)
      await update($, cards, list =>
        list.map(card =>
          card.agentId === agentId ? { ...card, status, ambiguities, durationMs: e.durationMs } : card,
        ),
      )
      if (ambiguities > 0) $.ui.toast(`${ambiguities} [AMBIGUITY] line(s) from a sub-agent — see the HUMAN column`)
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

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const [list, open, picked] = await Promise.all([read($, cards), read($, asking), read($, selected)])
    const width = e.props.bodyColumns
    const viewing = e.props.view?.agentId
    const isWide = width >= COLUMNS.length * MIN_COLUMN
    const columnWidth = isWide ? Math.floor(width / COLUMNS.length) : width
    const detail = picked === null ? undefined : list.find(card => card.agentId === picked)
    const tail = detail === undefined ? [] : await transcriptTail($, detail.agentId)

    return (
      <Box flexDirection="column">
        {open.includes(MAIN) && (
          <Text color="yellow" bold>
            ⚑ the main session is waiting for your answer
          </Text>
        )}
        {list.length === 0 && <Text dimColor>No sub-agents yet. Cards appear as the session spawns them.</Text>}
        <Box flexDirection={isWide ? 'row' : 'column'}>
          {COLUMNS.map(column => {
            const inColumn = list.filter(card => stageOf(card, open.includes(card.agentId)) === column.stage)
            return (
              <Box flexDirection="column" width={columnWidth} paddingRight={1}>
                <Text bold dimColor={inColumn.length === 0}>
                  {column.title} {inColumn.length}
                </Text>
                {inColumn.map(card => (
                  <Button
                    key={`card:${card.agentId}`}
                    plain
                    variant={card.agentId === picked ? 'primary' : undefined}
                    label={cardLabel(card, open.includes(card.agentId), card.agentId === viewing, columnWidth - 2)}
                    onPress={() => {
                      // Select it (again to clear) and bring its spawning row into view.
                      void update($, selected, current => (current === card.agentId ? null : card.agentId))
                      if (card.toolUseId !== undefined) {
                        $.ui
                          .scroll({ to: { requestId: card.toolUseId }, block: 'center' })
                          .catch((reason: unknown) =>
                            $.ui.log(`scroll to ${card.toolUseId} failed: ${String(reason)}`, { to: 'debug' }),
                          )
                      }
                    }}
                  />
                ))}
              </Box>
            )
          })}
        </Box>
        {detail !== undefined && (
          <Box flexDirection="column" marginTop={1} borderStyle="round" borderDimColor paddingX={1}>
            <Text bold>
              {detail.type} · {detail.description}
            </Text>
            <Text dimColor>
              {detail.status}
              {seconds(detail.durationMs)} · agent {detail.agentId}
              {detail.parentAgentId === undefined ? '' : ` · spawned by ${detail.parentAgentId}`}
              {detail.ambiguities > 0 ? ` · ${detail.ambiguities} [AMBIGUITY]` : ''}
            </Text>
            {tail.map(line => (
              <Text wrap="truncate-end">{fit(line, Math.max(1, width - 4))}</Text>
            ))}
            <Text dimColor>Open its full transcript from the engine's tasks list; press the card again to close this.</Text>
          </Box>
        )}
      </Box>
    )
  })
}
