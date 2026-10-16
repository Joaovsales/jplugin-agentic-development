/** One sub-agent of the session, as the board tracks it. */
export type Card = {
  /** The agent's id: `$.agent.list()`'s `id`, `turn.complete`'s `agentId`. */
  agentId: string
  /** The Agent tool call that spawned it: the transcript row a press scrolls to. */
  /** The spawning tool call; absent for an agent the engine listed before this mod saw it spawn. */
  toolUseId?: string
  /** The agent definition it runs as (`planner`, `code-reviewer`, ...). */
  type: string
  /** The Agent tool's short description of the task. */
  description: string
  /** The subagent whose loop spawned it; absent when the main loop did. */
  parentAgentId?: string
  status: 'running' | 'done' | 'failed'
  /** How many `[AMBIGUITY]` lines its final answer carried. */
  ambiguities: number
  /** Wall-clock length of its run once it ended, in milliseconds. */
  durationMs?: number
}

export type Stage = 'plan' | 'build' | 'review' | 'human' | 'done'

declare module 'claude-code' {
  interface PluginState {
    'factory-board': {
      cards: Card[]
      /** Agent ids (or `main`) with an AskUserQuestion dialog open right now. */
      asking: string[]
      /** The card the person pressed last, by agent id; null for none. */
      selected: string | null
    }
  }
}
