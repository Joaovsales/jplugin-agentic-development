---
implementation_paths:
  - .agents/skills/design-stack/**
  - .agents/skills/build/SKILL.md
  - .agents/skills/build/references/design-stack-gates.md
  - README.md
  - tests/test-design-stack-install.sh
  - tests/test-design-stack-catalog.sh
  - tests/test-design-stack-brief.sh
  - tests/test-design-stack-video.sh
---

# Spec: HyperFrames as a fifth design-stack source

> Origin: `/yolo` idea (2026-10-16) · Designed 2026-10-16 · Status: implemented 2026-10-16
> Parent spec: specs/ui-design-stack.md (the stack this extends)

## Summary

The shared design stack gains HyperFrames, the Apache-2.0 HTML-to-MP4 motion
framework, as a fifth verified source beside Taste, Impeccable, the design
references and img2threejs. Its 21 published agent skills appear in the catalog
as tools under `hyperframes:<skill>`, a small guard opts a task into video work
the way the 3D guard does, and an install that predates this source keeps
working offline until the owner runs an explicit update. HyperFrames is a
capability a project can use, never a visual direction a brief is written for.

## Behavior

`design_stack.py setup` and `update` stage HyperFrames from its official Git
repository into the verified release at `sources/hyperframes/`, record its
revision in the manifest beside the other four, and promote it atomically with
them. No installer runs for it: its skills are read in place, the same way the
design references and img2threejs are.

`design_stack.py catalog` lists one `tool` entry per HyperFrames skill found
at `sources/hyperframes/skills/*/SKILL.md`, with the ID `hyperframes:<dirname>`,
the frontmatter `name` as its title and the frontmatter `description` as its
fit text. The router skill `hyperframes:hyperframes` is required for the
source to validate; every other skill is discovered, so a new upstream skill
appears without changing a count in the adapter.

`design_stack.py select` and `brief` refuse a `hyperframes:` ID as the primary
direction or as a reference, exactly as they refuse `impeccable:` and `three:`
IDs today.

A new guard, `scripts/hyperframes.py`, answers two questions the skill text
asks agents to settle before touching video: whether the task opts into
HyperFrames (an explicit request in the task for a video, an MP4, motion
graphics or an explainer video, or a Motion rule that names HyperFrames; never
a bare `render`, which ordinary UI tasks use, and never a Motion rule that only
mentions an existing video element), and whether a render is
production or still a `prototype` (the composition passes `hyperframes check`
and an MP4 was rendered). It also reads the pinned CLI version from the
release's `packages/cli/package.json`, so an agent runs
`npx hyperframes@<that version>` and never a floating `latest`.

A manifest written before this source exists stays valid: `status`, `catalog`,
`select`, `brief` and `refresh` run offline against it, the catalog simply has
no `hyperframes:` entries, and `status` names the source an `update` would add.

## Inputs

- The official repository `https://github.com/heygen-com/hyperframes.git`,
  overridable through `DESIGN_STACK_HYPERFRAMES_URL` like every other source.
- The release layout: `sources/hyperframes/skills/<name>/SKILL.md` with YAML
  frontmatter `name` and `description`; `sources/hyperframes/packages/cli/package.json`
  with a `version` field.
- A task description and the project brief's Motion section, for the guard.
- The existing manifest, which may list four or five sources.

## Outputs

- Manifest `sources` carries a `hyperframes` revision after setup or update.
- Catalog entries `{"id": "hyperframes:<name>", "kind": "tool", "title", "fit",
  "source_revision", "path"}`, one per installed skill.
- `hyperframes.py` returns `should_run_hyperframes(task, brief_motion)` as a
  boolean, `production_status(gates)` as `{"label", "open_gates"}` with the
  required gates `check` and `render`, and `cli_version(release)` as the pinned
  version string.
- `status` on a four-source manifest prints `Ready <id> (offline; update adds:
  hyperframes)`.
- `/design-stack` SKILL.md documents the source path, the opt-in rule, the
  pinned-version rule and the prototype label; `/build`'s design-stack gates
  name the video guard beside the 3D guard; the README skills table row follows the new
  description.

## Edge Cases

- HyperFrames stores regression baselines in Git LFS. The clone runs shallow
  (`--depth 1`) with `GIT_LFS_SKIP_SMUDGE=1`, so setup never downloads
  baselines; the other four sources keep their full clones.
- A `skills/<name>/SKILL.md` without a frontmatter `name` uses the directory
  name as its title; a missing `description` yields an empty fit.
- A release whose `sources/hyperframes` lacks the router skill fails
  validation with the existing `catalog path is missing or leaves the verified
  release` error, so a broken upstream never promotes.
- A manifest listing a source the adapter does not know is still an error
  (`unsupported design-stack manifest`); only a missing known source is
  tolerated.
- `update` on a four-source manifest always stages all five sources; the
  revision comparison treats the missing key as changed, so the installers run
  and the new release carries five revisions.
- The task text "no video" or "remove the video" does not opt in; a Motion
  rule that only describes UI easing, or that mentions a video element without
  naming HyperFrames, does not opt in; "fix the re-render flicker" does not opt in.
- `hyperframes.py` never runs the CLI or touches the network; the production
  gates are facts the agent records after running `hyperframes check` and
  `hyperframes render` itself.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | Existing installs break on the fifth manifest key | H | H | Missing known sources are tolerated; a test boots a four-source manifest and runs `status` and `catalog` | 1 |
| R2 | A full clone of the HyperFrames monorepo is slow or pulls LFS media | M | M | Shallow clone with LFS smudge skipped for this source only; the install test asserts the flags | 1 |
| R3 | Upstream renames `skills/` or the router skill | L | M | Validation fails loudly before promotion and `UpdateRejected` keeps the previous release | 1 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Is HyperFrames a direction or a tool? | A tool, like img2threejs: `hyperframes:<skill>` entries of kind `tool`, never a primary direction or reference | assumed | It renders video from HTML; it does not describe how a product should look, so a brief cannot be written for it |
| 2 | Which upstream unit becomes a catalog entry? | Each `skills/<name>/SKILL.md` in the cloned repo | assumed | Matches how Taste skills and Impeccable commands are discovered, and spec ui-design-stack AC3 forbids a fixed count |
| 3 | Does an installer run? | No. Source is read in place like references and img2threejs | assumed | The upstream plugin install (`claude plugin install hyperframes@hyperframes`) writes into the user's live Claude config, which the stack's isolation rule forbids |
| 4 | What happens to a manifest with four sources? | It stays valid offline; `status` names what `update` adds; `update` adds it | assumed | The conservative reading of "update only after an explicit request": a plugin upgrade must not force network work on every status call |
| 5 | How is the clone bounded? | `--depth 1` and `GIT_LFS_SKIP_SMUDGE=1` for `hyperframes` only | assumed | The repo carries LFS baselines under `packages/producer/tests/`; the other sources are small and keep today's behavior |
| 6 | Does the brief change? | No template or version change; the brief accepts only `spatial`, `custom` and `taste:` IDs as its direction, so a `hyperframes:` ID is refused | assumed | The brief stores opaque IDs and the parent spec's D4 keeps v1; a video intent is a task-level opt-in, not a brief field |
| 7 | How does an agent pick the CLI version? | `hyperframes.py cli_version` reads `packages/cli/package.json` from the release and the skill tells agents to run `npx hyperframes@<version>` | assumed | The release pins a source revision; running `latest` would silently drift from it |
| 8 | Which gates mark a render production? | `check` (the composition passes `hyperframes check`) and `render` (an MP4 exists) | assumed | Mirrors the 3D guard's two-gate shape; both are commands the upstream CLI documents |
| 9 | Do the frontend agent personas change? | No | assumed | Minimal impact: the build skill already routes design-stack guards; the personas read `DESIGN.md`, which is unchanged |
| 10 | Which words opt a task in? | `video`, `mp4`, `motion graphics`, `explainer video/clip/animation` or `hyperframes` in the task; the brief's Motion rule opts in only by naming HyperFrames | assumed | A bare `render` or `explainer` matches ordinary UI work ("fix the re-render flicker", "explainer tooltip"), and a Motion rule that mentions an existing video element would opt every task on the project into video (the quality gate's design review, 2026-10-16) |

## Build Order

Sizing: 4 slices. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | HyperFrames source and catalog | The fifth source is staged shallow, its skills are catalog tools and never a direction or reference | `.agents/skills/design-stack/scripts/design_stack.py`, `.agents/skills/design-stack/scripts/catalog.py`, `.agents/skills/design-stack/scripts/brief.py`, `tests/test-design-stack-install.sh`, `tests/test-design-stack-catalog.sh`, `tests/test-design-stack-brief.sh` | — | 1, 2, 3 | `bash tests/test-design-stack-install.sh && bash tests/test-design-stack-catalog.sh && bash tests/test-design-stack-brief.sh` | 6 files · 2 systems · 3 ACs |
| 2 | Video guard | Opt-in, production-label and pinned-CLI-version answers for video tasks | `.agents/skills/design-stack/scripts/hyperframes.py`, `tests/test-design-stack-video.sh` | — | 5 | `bash tests/test-design-stack-video.sh` | 2 files · 2 systems · 1 AC |
| 3 | Stale-manifest compatibility | A four-source manifest keeps working offline and `status` names what `update` adds | `.agents/skills/design-stack/scripts/design_stack.py`, `.agents/skills/design-stack/scripts/catalog.py`, `tests/test-design-stack-video.sh` | 1, 2 | 4 | `bash tests/test-design-stack-video.sh && bash tests/test-design-stack-install.sh` | 3 files · 2 systems · 1 AC |
| 4 | Skill text and table | The skill, the build phase and the README row describe the new source and guard | `.agents/skills/design-stack/SKILL.md`, `.agents/skills/build/SKILL.md`, `README.md`, `tests/test-design-stack-video.sh` | 1, 2, 3 | 6, 7 | `python3 scripts/render-skills-table.py --check && bash tests/test-design-stack-3d.sh && bash tests/test-design-stack-video.sh` | 4 files · 2 systems · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/design-stack-hyperframes.md`.
Plan: `## Plan: design-stack-hyperframes` in `tasks/todo.md`, 4 slices, ready set <1, 2>.
Files: .agents/skills/design-stack/**, .agents/skills/build/SKILL.md, README.md, tests/test-design-stack-install.sh, tests/test-design-stack-catalog.sh, tests/test-design-stack-brief.sh, tests/test-design-stack-video.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/design-stack-hyperframes.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- D1: `hyperframes:` entries are kind `tool`; never a primary direction or a reference.
- D3: no installer runs for HyperFrames; nothing is written into the user's live Claude config.
- D4: a four-source manifest stays valid offline; only an explicit `update` adds the source.
- D5: shallow clone with `GIT_LFS_SKIP_SMUDGE=1` for `hyperframes` only; the other four clones are unchanged.
- D6: no `DESIGN.md` template or version change.
- D9: the frontend agent personas are untouched.
```

## Acceptance Criteria

- AC1: `setup` from five local fixture repositories writes a manifest whose
  `sources` has `taste`, `impeccable`, `references`, `three` and `hyperframes`,
  and the release contains `sources/hyperframes`; the `hyperframes` clone is
  invoked with `--depth 1` under `GIT_LFS_SKIP_SMUDGE=1` while the other four
  clones are not shallow.
- AC2: `catalog` on a release with fixture skills `hyperframes` and
  `motion-graphics` lists `hyperframes:hyperframes` and
  `hyperframes:motion-graphics` with kind `tool`, the frontmatter name as
  title and the frontmatter description as fit; adding a third fixture skill
  adds exactly one entry without an adapter change.
- AC3: `select --direction hyperframes:motion-graphics` and `select
  --reference hyperframes:hyperframes` both fail with `SelectionRejected`;
  `brief.validated_choice` rejects a `hyperframes:` direction.
- AC4: A manifest with four sources and a four-source release answers `status`
  with `Ready <id> (offline; update adds: hyperframes)` and `catalog` with no
  `hyperframes:` entry and exit code 0; a manifest naming an unknown source
  still fails.
- AC5: `should_run_hyperframes("Render a 30s product launch video", "")` is
  true; `("Smooth the hover transition", "Ease-out 200ms on hover")` is false;
  `("Remove the video hero", "")` is false; `production_status({"check":
  True, "render": False})["label"]` is `prototype` and both gates true is
  `production`; `cli_version` returns the `version` from a fixture
  `packages/cli/package.json`.
- AC6: `.agents/skills/design-stack/SKILL.md` names `sources/hyperframes/skills/*/SKILL.md`,
  the `hyperframes:` tool rule, `npx hyperframes@`, `hyperframes check` and the
  `prototype` label; `.agents/skills/build/references/design-stack-gates.md` names the video guard
  beside the 3D guard; `python3 scripts/render-skills-table.py --check` is
  silent.
- AC7: `bash tests/test-design-stack-install.sh`, `tests/test-design-stack-catalog.sh`,
  `tests/test-design-stack-brief.sh`, `tests/test-design-stack-3d.sh` and the
  new `tests/test-design-stack-video.sh` pass.

## Implementation Paths

- `.agents/skills/design-stack/scripts/design_stack.py` — the `SOURCES` table,
  the shallow-clone rule, the manifest compatibility read and the `status` line.
- `.agents/skills/design-stack/scripts/catalog.py` — optional HyperFrames source
  path, `hyperframes_entries` discovery and the catalog assembly.
- `.agents/skills/design-stack/scripts/brief.py` — the rejected-primary prefix list.
- `.agents/skills/design-stack/scripts/hyperframes.py` — the opt-in, production
  and pinned-version guard.
- `.agents/skills/design-stack/SKILL.md` — source path, opt-in video section,
  updated description.
- `.agents/skills/build/references/design-stack-gates.md` — the § *Phase 2: 3D and video gates* guard paragraph, which `.agents/skills/build/SKILL.md` points to.
- `README.md` — the generated skills-table row.
- `tests/test-design-stack-install.sh` — fifth fixture source, clone flags.
- `tests/test-design-stack-catalog.sh` — fixture skills, entry kinds, selection refusals.
- `tests/test-design-stack-brief.sh` — `hyperframes:` direction refusal.
- `tests/test-design-stack-video.sh` — the guard and the four-source manifest compatibility.
