---
name: refresh
description: "Context reset for a session running out of room: snapshot working state to disk, then continue the work in a fresh context rebuilt from that snapshot. Distinct from /checkpoint, which saves progress and stops — reach for /refresh when the work continues but the context must be recycled. Triggers on: 'this conversation is getting too long', 'you are losing track', 'start clean and keep going', 'context is full', 'reset and continue', or when /build's architectural circuit breaker trips."
disable-model-invocation: false
---

# /refresh — Context Reset

Formalizes the full-context-reset pattern for long-running work: when the context
window is filling and compaction alone is not enough, snapshot all working state
to disk and rebuild from a clean slate. A reset costs one handoff artifact but
buys a fresh, focused context.

> **Backstop, not routine.** Capable models rarely need a manual reset — Claude
> Code's native auto-compact (~75% utilisation) plus the `PreCompact` flush hook
> cover most cases. Reach for `/refresh` on genuinely long builds, or when
> `/build`'s architectural circuit breaker trips.

## Steps

### 1. Snapshot working state

Run the shared flush to write the current snapshot to `tasks/checkpoint.md`:

```bash
bash .claude/hooks/pre-compact.sh </dev/null
```

This captures the git branch, working-tree status, in-progress (`[~]`) and
pending (`[ ]`) tasks, and the active spec — the same artifact the `PreCompact`
hook writes automatically. Verify the file exists before continuing.

### 2. Confirm durable state

A reset loses chat history, never disk. Before resetting, confirm everything
needed to resume lives on disk:
- `tasks/checkpoint.md` — just written (state + how-to-resume)
- `tasks/todo.md` — task plan with completion marks
- `tasks/solutions/` — typed learnings (grep frontmatter, load only what's relevant)
- `specs/<feature>.md` — the contract

If any in-flight decision exists only in chat, append it to `tasks/checkpoint.md`
now (Open Questions / Blockers).

### 3. Hand off to a fresh context

Emit the minimal resume instruction, then start a clean context:

```
🔄 CONTEXT RESET — resume from disk
1. Read tasks/checkpoint.md (state + how-to-resume)
2. Read tasks/todo.md; continue from the first [~] (else [ ]) item
3. Grep tasks/solutions/ frontmatter for learnings relevant to the active task
Do NOT replay prior work — the checkpoint is the source of truth.
```

In Claude Code, run `/clear` (hard reset) or `/compact` (softer) once the
snapshot is on disk. The SessionStart hook detects `source=compact` and prints a
"RESUMING AFTER COMPACTION" pointer to the checkpoint.

### 4. Confirm

Reply: "Context reset — state snapshotted to `tasks/checkpoint.md`. Resume from disk."
