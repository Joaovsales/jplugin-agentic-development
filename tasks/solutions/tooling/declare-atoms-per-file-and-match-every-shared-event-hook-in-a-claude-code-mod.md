---
title: Declare atoms per file and give every shared-event hook a matcher in a Claude Code mod
date: 2026-10-19
problem_type: tooling
module: mods/session-viz/hooks, mods/factory-board/hooks
tags: [claude-code-mod, plugin-validate, function-hooks, state-atoms, matchers]
applies_when: writing or splitting a Claude Code function-hooks mod (`hooks/hooks.json` → `register.tsx`) across several source files, or when `claude plugin validate` refuses a module that type-checks
---

## The rules the validator enforces (Claude Code 2.1.303)

`claude plugin validate` reads the module the way the engine loads it and refuses
patterns `tsc` accepts. This session hit four, each costing a rewrite:

1. **`$` never goes into a value.** `const left = { $, t, width }` is refused
   ("$ itself is put in an object"). `$` is spelled `$.noun.method(...)` at the
   call site or passed as a plain positional argument
   (`mods/session-viz/hooks/register.tsx:82`, `AgentsSection($, left, …)`).
2. **`read`/`update` bind to an atom declared in the same file.** An atom
   imported from another module is refused ("update takes a source the scan can
   read … written there or in a const of this file"). Every file that touches
   state declares `const agents = atom({ plugin: 'session-viz', key: 'agents' } as const, INITIAL_AGENTS)`
   with the `{ plugin, key }` literal written out; the shared module exports only
   the initial values and helpers (`mods/session-viz/hooks/state.ts:18-34`). The
   state is the host's, keyed by plugin and key, so several declarations of one
   atom read and write the same value.
3. **One matcher-less hook per event per plugin.** A second `on('agent.spawn', hook)`
   in another file is refused ("registered twice without a matcher"). A matched
   hook is a distinct registration, and the matcher may be a const imported from
   another file: `on('session.start', { cwd: EVERY }, …)` with
   `export const EVERY = /^/` (`mods/session-viz/hooks/state.ts`), or a real
   filter such as `{ agentId: /./ }` on the sub-agent events
   (`mods/session-viz/hooks/agents.tsx:196-226`).
4. **A `turn.step` hook is an async generator**: `async function* ($, e, next) { const result = yield* next(e); …; return result }`
   (`mods/session-viz/hooks/phase.tsx:64`). A plain async function loads nothing.

Two engine facts the review needed and the types answer: `$.ui.toast` returns
`void` (nothing to await or catch) and `$.clock.every` returns a `Timer` with
`cancel` (`claude-code.d.ts`, grep `TimerCall`). In the test harness a
`$.ui.scroll` raised from a mounted pane's `onPress` is not answered by an
`on('ui.scroll')` bottom; assert the `.catch` debug log line instead
(`mods/session-viz/hooks/agents.test.ts:172`).

## Consequence of ignoring it

A module that type-checks and reads well fails to load, and the failure surfaces
only at `validate` (or as a dim transcript line at hot reload), after the code is
written. Splitting a mod into section files without rules 2 and 3 produces a
merge that validates per file and fails as a whole.

## Related

- The spec that drove this: `specs/session-viz-mod.md` D13 (module split); the
  decision to declare atoms per file is recorded there as an `[AMBIGUITY]` line in
  the slice 1 handover (`tasks/todo.md`, `## Plan: session-viz-mod`).
- Parallel slices over one mod: [dispatch-disjoint-slices-in-scratchpad-copies-and-verify-centrally](../process/dispatch-disjoint-slices-in-scratchpad-copies-and-verify-centrally.md).
