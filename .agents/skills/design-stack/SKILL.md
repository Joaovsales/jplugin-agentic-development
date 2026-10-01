---
name: design-stack
description: Set up, update, and browse the shared UI design sources used by jplugin. Installs Taste, Impeccable, design references, and img2threejs once in user scope.
harness: universal
---

# /design-stack — Shared UI design sources

Use this skill for UI project design setup. The adapter lives in jplugin; upstream
sources live in one user-scoped verified release. Never copy those repositories
into a project or fetch them during an ordinary UI plan/build. Backend and CLI
projects do not need this setup.

## Setup and status

Run `python3 .agents/skills/design-stack/scripts/design_stack.py setup` once on
the user's machine. A verified release contains Taste skills, Impeccable commands,
awesome-design-md references, and img2threejs. Setup reads the current release
offline if it already exists. `status` is also offline. If the first setup cannot
reach or validate the sources, report `SetupRequired` and stop UI setup.

The default shared root is `~/.local/share/jplugin/design-stack`. The manifest
records one SHA per source and points to a release in `releases/`. Read the
manifest's `catalog_path` to browse installed sources; do not infer that the
latest upstream content is installed. The source paths are:

- `sources/taste/skills/*/SKILL.md` — Taste directions and archetypes.
- `sources/impeccable/.agent/skills/impeccable/SKILL.md` — Impeccable command skill.
- `sources/references/design-md/*/DESIGN.md` — design references.
- `sources/three/SKILL.md` — img2threejs capability, used only on request.

Taste's upstream installation uses `npx skills add`; Impeccable's uses
`npx impeccable install`. The adapter invokes these official CLIs against a
cloned revision in an isolated staging directory with a staging HOME and project
cwd, then validates their staged skill/command outputs before promotion. Installed
entrypoints live under the release's staging home in `.agent/`, `.agents/`, or
`.claude/`; read them from the verified release, never from the current project.
The references and 3D source use their official Git repositories. The project
never receives installer output.

## Update

Run `python3 .agents/skills/design-stack/scripts/design_stack.py update` only
after an explicit update request. The adapter stages all four sources, compares
their revisions, runs the installers on a changed set, validates entrypoints,
and atomically promotes the release pointer. A failed or timed-out update reports
`UpdateRejected` and leaves the previous release usable. An unchanged revision
set skips installation.

Never edit a project's `DESIGN.md` as part of shared setup or update. Its visual
rules change only through an owner-selected project refresh.
