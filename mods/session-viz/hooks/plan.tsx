import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, RenderElement } from 'claude-code'

import type { PlanProgress, SliceRow } from '../types'
import { EVERY, INITIAL_PHASE, INITIAL_PLAN, SPEC_PATH, fit, refreshStatus } from './state'
import type { Draw } from './state'

const plan = atom({ plugin: 'session-viz', key: 'plan' } as const, INITIAL_PLAN)
const phase = atom({ plugin: 'session-viz', key: 'phase' } as const, INITIAL_PHASE)

const TODO = 'tasks/todo.md'

/** The tools that change the file their `file_path` names. */
const WRITERS = /^(?:Edit|Write|MultiEdit)$/
/** A path ending `tasks/todo.md`, either slash. */
const TODO_PATH = /tasks[\\/]todo\.md$/

/** `## Plan: <feature>` — opens a block; any later line starting `## ` ends it. */
const PLAN_HEAD = /^## Plan:\s*(.*)$/
/** `> Spec: specs/<x>.md` — the spec the block was planned from. */
const SPEC_LINE = /^>\s*Spec:\s*(\S+)/
/** `### Slice 2/5 — <name>` (the dash is U+2014; a hyphen is accepted too). */
const SLICE_HEAD = /^### Slice\s+(\d+)\/\d+\s*[—-]\s*(.*)$/
/** `- [ ] <name> …` — the slice header row: open or done, never counted as a row. */
const HEADER_ROW = /^- \[([ xX])\]/
/** `  [x] TDD: …` / `  [ ] Verify: …` — the rows that are counted. */
const COUNTED_ROW = /^\s+\[([ xX])\]\s+(?:TDD|Verify):/
/** `> Handover: …` — closes the slice it sits under. */
const HANDOVER = /^>\s*Handover:/

type Block = { feature: string; spec?: string; slices: SliceRow[]; implicit: SliceRow; open: boolean }

const newSlice = (n: number, name: string): SliceRow => ({ n, total: 0, name, rowsDone: 0, rowsTotal: 0, handover: false })

const slashed = (path: string): string => path.replace(/\\/g, '/')

function toProgress(block: Block): PlanProgress {
  const found = block.slices.length === 0 ? [block.implicit] : block.slices
  const slices = found.map(row => ({ ...row, total: found.length }))
  return {
    feature: block.feature,
    ...(block.spec === undefined ? {} : { spec: block.spec }),
    slices,
    rowsDone: slices.reduce((sum, row) => sum + row.rowsDone, 0),
    rowsTotal: slices.reduce((sum, row) => sum + row.rowsTotal, 0),
    closed: slices.filter(row => row.handover).length,
    total: slices.length,
  }
}

/** The active `## Plan:` block of a todo file (D9): the recorded spec's, else the last with an open row, else the last; null with none. */
export function parsePlan(text: string, spec?: string): PlanProgress | null {
  const blocks: Block[] = []
  let block: Block | undefined
  let slice: SliceRow | undefined
  for (const line of text.replace(/\r/g, '').split('\n')) {
    const opened = PLAN_HEAD.exec(line)
    if (opened !== null) {
      const feature = opened[1]!.trim()
      block = { feature, slices: [], implicit: newSlice(1, feature), open: false }
      blocks.push(block)
      slice = block.implicit
      continue
    }
    if (block === undefined) continue
    if (line.startsWith('## ')) {
      block = undefined
      continue
    }
    const named = SPEC_LINE.exec(line)
    const heading = SLICE_HEAD.exec(line)
    const header = HEADER_ROW.exec(line)
    const row = COUNTED_ROW.exec(line)
    if (named !== null && block.spec === undefined) block.spec = named[1]
    else if (heading !== null) {
      slice = newSlice(Number(heading[1]), heading[2]!.trim())
      block.slices.push(slice)
    } else if (header !== null) block.open ||= header[1] === ' '
    else if (row !== null && slice !== undefined) {
      slice.rowsTotal += 1
      if (row[1] === ' ') block.open = true
      else slice.rowsDone += 1
    } else if (HANDOVER.test(line) && slice !== undefined) slice.handover = true
  }

  const recorded = spec === undefined ? undefined : slashed(spec)
  const chosen =
    blocks.find(b => recorded !== undefined && b.spec !== undefined && slashed(b.spec) === recorded) ??
    blocks.findLast(b => b.open) ??
    blocks.at(-1)
  return chosen === undefined ? null : toProgress(chosen)
}

/** Reads tasks/todo.md, parses it against the recorded spec and stores the result; a missing file stores null. */
async function reload($: EngineInterface): Promise<void> {
  const { spec } = await read($, phase)
  const parsed = await $.fs.read(TODO).then(
    text => parsePlan(text, spec),
    () => null,
  )
  await update($, plan, () => parsed)
  await refreshStatus($)
}

export function registerPlan(on: On): void {
  on('session.start', { cwd: EVERY }, async ($, e, next) => {
    const result = await next(e)
    await reload($)

    return result
  })

  on('tool.call', { tool: WRITERS, file_path: TODO_PATH }, async ($, e, next) => {
    const ran = await next(e)
    await reload($)

    return ran
  })

  // The one writer of the recorded spec (spec D9): the Phase section draws it, and the plan is re-read against it here, in order.
  on('prompt.submit', { text: SPEC_PATH }, async ($, e, next) => {
    const result = await next(e)
    const spec = SPEC_PATH.exec(e.text)?.[0]
    if (spec !== undefined) await update($, phase, current => ({ ...current, spec }))
    await reload($)

    return result
  })
}

export function PlanSection(d: Draw, progress: PlanProgress | null): RenderElement {
  const { Box, Text } = d.t
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>PLAN</Text>
      {progress === null ? (
        <Text dimColor>no plan block</Text>
      ) : (
        <Text>{fit(`${progress.feature} · slice ${progress.closed}/${progress.total} · rows ${progress.rowsDone}/${progress.rowsTotal}`, d.width)}</Text>
      )}
      {progress?.slices.map(row => (
        <Text key={String(row.n)} dimColor={row.handover}>
          {fit(`${row.n}/${row.total} ${row.name} · rows ${row.rowsDone}/${row.rowsTotal}${row.handover ? ' · ✓ handover' : ''}`, d.width)}
        </Text>
      ))}
    </Box>
  )
}
