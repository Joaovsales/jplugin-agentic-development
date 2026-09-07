# Routine prompts

One file per routine in `routines.md`. Each is the **entire** prompt an
unattended routine runs — copy it into the scheduler verbatim. The prompt names
the routine and the one skill that carries its logic; it is project-agnostic.
Producer skills run inline. A consumer's `/debug` and `/build` dispatch
sub-agents where the harness offers them and run inline where it does not.

## Which prompt, which tier, how often

| Routine | Kind | Prompt | Skill | Model tier | Suggested cadence |
|---|---|---|---|---|---|
| `janitor` | producer | `janitor.md` | `/sweep --routine janitor` | Planner | weekly |
| `architect` | producer | `architect.md` | `/sweep --routine architect` | Planner | weekly |
| `fix` | consumer | `fix.md` | `/debug #N` | Builder | daily |
| `improve` | consumer | `improve.md` | `/plan` from `task-registry show <N>`, then `/build` | Builder | daily |
| `plan` | consumer | `plan.md` | `/plan` from `task-registry show <N>` | Planner | daily |

Producers run on the **Planner** tier because verification and design review are
judgement; consumers `fix` and `improve` run on the **Builder** tier because the
issue body already carries the reproduction and the proposed fix. Cadence is the
operator's — weekly for producers so consumers have a week of daily runs to drain
what they filed.

## Environment checklist

`task-registry doctor` checks the provider, its reachability, and the label
policy at the routine's first step, so a missing one fails loudly before a branch
exists; the routine itself checks the `verify-<app>` skill and the app launch.
Configure once per project:

- **Two write switches**, both required for a producer to publish issues
  unattended: `require_write_approval = false` in the project's task-tracking
  file **and** `TASK_REGISTRY_TRUSTED_CONFIG=1` in the routine's environment.
  With either missing the sweep still runs and files local records marked
  *publication pending*; the PR body names the switch to flip.
- **An authenticated `gh`** — the GitHub provider is `gh`-only. `gh auth status`
  must succeed in the routine's environment, with a token that can read and
  write issues.
- **Mapped labels pre-existing** — every label in `[labels]` and every routine
  selector (`bug`, `tech-debt`, `enhancement`, `documentation`,
  `design-decision`, `now`, `next`, `in-progress`) must
  exist in the tracker unless `allow_label_creation = true`. A missing label is
  reported, and the issue is written without it.
- **`janitor` only: an app that launches here.** The routine drives every mapped
  feature live through the project's `verify-<app>` skill, so its environment
  needs whatever that skill's doctor step needs — a database, seeded fixtures, a
  browser. A feature that cannot launch is a coverage gap, not a finding, so an
  environment that launches nothing produces a record that proves nothing.
- **`task-registry doctor` green** in that environment, once, by hand, before
  scheduling anything.

The same checklist is the *Unattended routines* section of
`.agents/skills/task-registry/references/configuration.md`.
