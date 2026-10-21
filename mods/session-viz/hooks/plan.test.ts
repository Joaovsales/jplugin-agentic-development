import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { parsePlan } from './plan'

const SURFACES = ['terminal', 'desktop'] as const

const PANE = {
  plugin: 'session-viz',
  component: 'Pane' as const,
  requestId: 'session-viz',
  props: {
    title: 'Session',
    isFocused: false,
    bodyColumns: 200,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
}

/** Two plan blocks: alpha (4 slices, 7 rows, 3 done, slice 1 closed) and beta (one open row). */
const TODO = `# Todo

## Plan: alpha
> Spec: specs/alpha.md

### Slice 1/4 — First
- [x] First <!-- task-id: a.first -->
  [x] TDD: a.test § one -> one
  [x] TDD: a.test § two -> two
> Handover: landed abc..def — first is in.

### Slice 2/4 — Second
- [ ] Second <!-- task-id: a.second -->
  [x] TDD: a.test § three -> three
  [ ] Verify: run it

### Slice 3/4 — Third
- [ ] Third
  [ ] TDD: a.test § four -> four
  [ ] TDD: a.test § five -> five

### Slice 4/4 — Fourth
- [ ] Fourth
  [ ] Verify: last

## Plan: beta
> Spec: specs/beta.md

### Slice 1/1 — Only
- [ ] Only
  [ ] TDD: b.test § one -> one
`

/** The world beneath the plugin; `todo.text` is what the file holds (null: it is missing), `reads` counts the reads. */
function world(on: On, todo: { text: string | null }) {
  const statuses: Array<string | undefined> = []
  const reads = { count: 0 }
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.status', ($, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('agent.list', () => ({ value: [] }))
  on('session.repo', () => ({ value: null }))
  on('fs.read', ($, e) => {
    if (!e.path.replace(/\\/g, '/').endsWith('tasks/todo.md') || todo.text === null) return { deny: 'ENOENT: no such file' }
    reads.count += 1
    return { value: todo.text }
  })
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('prompt.submit', ($, e) => ({ text: e.text }))
  on('tool.call', { tool: 'Edit' }, () => ({ result: {} as never }))
  on('tool.call', { tool: 'Write' }, () => ({ result: {} as never }))
  const clock = mock.clock(on)
  return { statuses, reads, clock }
}

test('parse: the active block follows the recorded spec, else the last block with an open row, one line per slice', async ($, on) => {
  const w = world(on, { text: TODO })
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })

  // No spec recorded yet: the last block holding an open row is beta.
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: 'beta · slice 0/1 · rows 0/1' }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1\/1 Only · rows 0\/1$/ }), surface).toBeDefined()
    await ui.unmount()
  }
  expect(w.statuses.at(-1)).toBe('viz · idle · slice 0/1')

  // A prompt naming specs/alpha.md records the spec; the section follows it.
  await $.prompt.submit({ text: 'Invoke `/build` for `specs/alpha.md`.', wait: false, origin: { kind: 'composer' } })
  expect(w.statuses.at(-1)).toBe('viz · idle · slice 1/4')

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: 'alpha · slice 1/4 · rows 3/7' }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1\/4 First · rows 2\/2 · ✓ handover$/ }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^2\/4 Second · rows 1\/2$/ }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^3\/4 Third · rows 0\/2$/ }), surface).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^4\/4 Fourth · rows 0\/1$/ }), surface).toBeDefined()
    expect(await ui.findAll({ type: 'Text', text: /handover/ }), surface).toHaveLength(1)
    await ui.unmount()
  }
})

test('parse: grammar — CRLF, an implicit slice, a block ending at the next `## `, the spec choice, no block', () => {
  const crlf = TODO.replace(/\n/g, '\r\n')
  expect(parsePlan(crlf, 'specs/alpha.md')).toMatchObject({
    feature: 'alpha',
    spec: 'specs/alpha.md',
    closed: 1,
    total: 4,
    rowsDone: 3,
    rowsTotal: 7,
  })
  expect(parsePlan(crlf, 'specs\\alpha.md')?.feature).toBe('alpha')

  // No `### Slice` heading: one implicit slice named after the feature; the next `## ` ends the block.
  const implicit = parsePlan('## Plan: solo\n- [ ] Solo\n  [x] TDD: a\n  [ ] Verify: b\n> Handover: done\n## Notes\n  [ ] TDD: not mine\n')
  expect(implicit?.slices).toEqual([{ n: 1, total: 1, name: 'solo', rowsDone: 1, rowsTotal: 2, handover: true }])
  expect(implicit?.closed).toBe(1)

  // A hyphen opens a slice too; a recorded spec naming no block falls back to the last block with an open row.
  const hyphen = parsePlan('## Plan: h\n### Slice 1/2 - One\n  [x] TDD: a\n### Slice 2/2 - Two\n  [ ] TDD: b\n', 'specs/none.md')
  expect(hyphen?.slices.map(s => s.name)).toEqual(['One', 'Two'])

  // The last block with an open row beats a later closed one; with every block closed, the last block.
  expect(parsePlan('## Plan: a\n- [ ] A\n## Plan: b\n- [x] B\n  [x] TDD: done\n')?.feature).toBe('a')
  expect(parsePlan('## Plan: a\n  [x] TDD: x\n## Plan: b\n  [x] TDD: y\n')?.feature).toBe('b')

  expect(parsePlan('# nothing here\n')).toBeNull()
  expect(parsePlan('')).toBeNull()
})

test('re-read: an Edit or Write on tasks/todo.md re-reads after the call, another path does not', async ($, on) => {
  const todo = { text: '## Plan: one\n### Slice 1/2 — A\n- [ ] A\n  [ ] TDD: a\n### Slice 2/2 — B\n  [ ] TDD: b\n' }
  const w = world(on, todo)
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  expect(w.reads.count).toBe(1)

  const expectLine = async (line: string) => {
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      expect(await ui.find({ type: 'Text', text: line }), `${surface}: ${line}`).toBeDefined()
      await ui.unmount()
    }
  }
  await expectLine('one · slice 0/2 · rows 0/2')

  todo.text = '## Plan: one\n### Slice 1/2 — A\n- [x] A\n  [x] TDD: a\n> Handover: ok\n### Slice 2/2 — B\n  [ ] TDD: b\n'
  const other = await $.tool.call({ tool: 'Edit', file_path: 'C:/repo/src/a.ts', old_string: 'a', new_string: 'b' })
  expect(other).toMatchObject({ result: {} })
  expect(w.reads.count).toBe(1)

  const ran = await $.tool.call({ tool: 'Edit', file_path: 'C:\\repo\\tasks\\todo.md', old_string: 'a', new_string: 'b' })
  expect(ran).toMatchObject({ result: {} })
  expect(w.reads.count).toBe(2)
  expect(w.statuses.at(-1)).toBe('viz · idle · slice 1/2')
  await expectLine('one · slice 1/2 · rows 1/2')

  todo.text = '## Plan: two\n  [ ] TDD: c\n'
  await $.tool.call({ tool: 'Write', file_path: 'tasks/todo.md', content: todo.text })
  expect(w.reads.count).toBe(3)
  await expectLine('two · slice 0/1 · rows 0/1')
})

test('re-read: a missing tasks/todo.md reads no plan block and no hook fails', async ($, on) => {
  const w = world(on, { text: null })
  await $.session.start({ cwd: 'C:/repo', surface: 'terminal', isInteractive: true })
  expect(w.statuses.at(-1)).toBe('viz · idle')

  const ran = await $.tool.call({ tool: 'Write', file_path: 'C:/repo/tasks/todo.md', content: 'x' })
  expect(ran).toMatchObject({ result: {} })

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: 'no plan block' }), surface).toBeDefined()
    await ui.unmount()
  }
})
