/** The workflow phase the running skill puts the session in (spec D8). */
export type Phase = 'PLAN' | 'BUILD' | 'GATE' | 'WRAP-UP' | 'idle'

/** What the Phase section and the status line draw. */
export type PhaseState = {
  phase: Phase
  /** The skill running now, by the segment after its last `:`. */
  skill?: string
  /** The `/go` lane the last main-loop `[ROUTE]` line named. */
  lane?: string
  /** The `/go` chain the last main-loop `[ROUTE]` line named. */
  chain?: string
  /** The `specs/<x>.md` path the most recent prompt named (spec D9). */
  spec?: string
}

/** The three severities of a four-axis finding. */
export type Severity = 'MUST-FIX' | 'SHOULD-FIX' | 'NITPICK'

export type FindingCounts = { 'MUST-FIX': number; 'SHOULD-FIX': number; NITPICK: number }

/** What one sub-agent touched, from its `tool.call`s and `turn.step`s (spec D16). */
export type Footprint = {
  /** Files Read or Globbed, newest last, at most 40. */
  read: string[]
  /** Files Edited, Written or notebook-edited, at most 40. */
  edited: string[]
  /** `<pattern> in <path>` per Grep, at most 40. */
  grepped: string[]
  /** The first 80 characters of each Bash command, at most 40. */
  commands: string[]
  toolCalls: number
  steps: number
  messages: number
}

/** One sub-agent of the session, as the Agents section tracks it. */
export type AgentRow = {
  /** `$.agent.list()`'s `id`, `turn.complete`'s `agentId`. */
  agentId: string
  /** The spawning Agent tool call a press scrolls to; absent for an agent seen only through `$.agent.list()`. */
  toolUseId?: string
  type: string
  description: string
  /** The spawn prompt, or `(spawned before session-viz loaded)`. */
  prompt: string
  /** The Agent tool's `model` as requested, when one was. */
  model?: string
  /** What the engine resolved the agent to run on. */
  resolvedModel?: string
  parentModel?: string
  parentAgentId?: string
  status: 'running' | 'done' | 'failed'
  /** `turn.complete`'s reason, or the engine's status for an agent the hooks never saw end. */
  outcome?: string
  durationMs?: number
  /** Every `[AMBIGUITY]` line of its answer. */
  ambiguities: string[]
  /** Every `[SURFACE]` line of its answer. */
  surfaces: string[]
  findings: FindingCounts
  footprint: Footprint
}

/** One `### Slice n/N` of the active plan block. */
export type SliceRow = {
  n: number
  total: number
  name: string
  rowsDone: number
  rowsTotal: number
  /** True once the slice's `> Handover:` blockquote exists. */
  handover: boolean
}

/** The active `## Plan:` block of `tasks/todo.md`. */
export type PlanProgress = {
  feature: string
  spec?: string
  slices: SliceRow[]
  rowsDone: number
  rowsTotal: number
  /** Slices whose handover exists. */
  closed: number
  total: number
}

/** The quality receipt the branch pointer names, as the Gates section reads it. */
export type Receipt = {
  verdict: string
  /** The first eight characters of the fingerprint. */
  fp8: string
  testsExit?: number
  unresolved?: number
  designVerdict?: string
}

/** One dispatch check that toasted: off-tier (spec D11) or a missing contract item (spec D10). */
export type DispatchIssue = {
  kind: 'off-tier' | 'contract'
  type: string
  text: string
}

/** Everything the Gates section draws. */
export type Gates = {
  /** The receipt, `'unreadable'` for a malformed one, null for none. */
  receipt: Receipt | 'unreadable' | null
  /** The last `Verdict:` line seen on a main-loop answer. */
  verdict?: string
  findings: FindingCounts
  ambiguities: { agent: string; text: string }[]
  surfaces: { agent: string; text: string }[]
  dispatch: DispatchIssue[]
}

/** The last `session.measure` figures the status line draws. */
export type Measure = { percent?: number; usd?: number }

/** What has already toasted, so a hot reload repeats nothing (spec D7). */
export type Toasted = { fingerprints: string[]; turns: string[] }

declare module 'claude-code' {
  interface PluginState {
    'session-viz': {
      phase: PhaseState
      agents: AgentRow[]
      /** Agent ids (or `main`) with an AskUserQuestion dialog open right now. */
      asking: string[]
      /** The agent whose drill-down is open, by id; null for none. */
      selected: string | null
      plan: PlanProgress | null
      gates: Gates
      measure: Measure
      toasted: Toasted
    }
  }
}
