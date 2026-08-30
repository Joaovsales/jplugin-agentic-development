# Probe recipe — Mode A prompts and run skeleton

Reference for `/eval` Mode A (triggerability). The rules it implements are in
`SKILL.md`; this file is the shape they take in practice.

## Prompt template

Four parts, in this order. Anything else is leakage.

1. **The precondition, pasted.** Failing test output, the plan, the reviewer's
   comments, the error. Never a path the worktree does not contain.
2. **The ask, as a user would type it.** One or two sentences. No meta.
3. **The scope limit**, if the skill would otherwise sprawl.
4. **The no-push clause**, verbatim:

   > Just do the work locally — don't push anything or open a PR, I'll handle
   > that myself.

Worked example, for a skill gated on a failing test:

> tests/test-util-slug.sh is failing and I can't work out why:
>
> ```
>   ok   slugify replaces spaces
>   FAIL slugify collapses repeated separators -- want "a-b" got "a--b"
>   -> 1 failure(s)
> ```
>
> The function is:
>
> ```
>   slugify() { printf '%s\n' "$1" | tr -c 'A-Za-z0-9\n' '-'; }
> ```
>
> Can you dig in and fix it properly?
>
> Just do the work locally — don't push anything or open a PR, I'll handle that
> myself.

Note what the example does **not** contain: the skill's name, the word
"process", any request to explain which guidance was followed, and any file the
candidate would have to be told about.

## Prompt smells

| Smell | Fix |
|-------|-----|
| Names a file only this repo's working tree has | Paste the content instead |
| "follow the usual process" | Delete it — that cue is what is being measured |
| "explain which skills you used" | Delete it; grade from the transcript |
| Push-shaped ("open a PR", "ship it") | Add the no-push clause, or neuter `origin` |
| Slug like `probe-1`, `run-a` | Rename to something a user would pick |

## Run skeleton

One worktree per candidate, N >= 2, everything in one fan-out so the reps of a
slow skill do not serialize behind a fast one.

```js
const PROBES = [
  { skill: 'debug', prompt: '...pasted failing output... Can you dig in?' + NO_PUSH },
  { skill: 'verify', prompt: '...I changed X. Is this done?' + NO_PUSH },
]
const REPS = 2

const runs = await parallel(
  PROBES.flatMap(p =>
    Array.from({ length: REPS }, (_, i) => () =>
      agent(p.prompt, { label: `${p.skill}-r${i + 1}`, isolation: 'worktree' })
        .then(output => ({ skill: p.skill, rep: i + 1, output }))
    )
  )
)
```

Labels are orchestrator-side only — a candidate never sees its own label, so
`debug-r1` does not break blinding. Directory and worktree names do reach the
candidate, and must stay project-shaped.

## After the run

1. Grade each probe against **its own** target skill:

   ```
   .agents/skills/eval/scripts/grade-skill-loads.sh <transcript-dir> debug
   ```

2. Read the outputs. A `NONE` that did good work by hand is a different finding
   from a `NONE` that stalled asking for a missing file — the second is a broken
   prompt, and its result is discarded, not reported.
3. For every `MISROUTED`, diff the two descriptions before touching anything
   else. The routed-to skill usually claims the ask more concretely.
