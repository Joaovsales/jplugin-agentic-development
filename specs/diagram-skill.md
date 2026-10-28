---
implementation_paths:
  - .agents/skills/diagram/**
  - .agents/skills/how/SKILL.md
  - .agents/skills/how/references/explainer-prompt.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/tidy/SKILL.md
  - .github/upstreams.json
  - scripts/check-upstream-drift.py
  - install.sh
  - .gitignore
  - THIRD_PARTY_NOTICES.md
  - README.md
  - tests/test-diagram-skill.sh
  - tests/test-upstream-drift.sh
  - tests/test-install-sh.sh
---

# Spec: `/diagram` — Archify as an installed diagram tool

> Origin: `/grilling` interview (2026-10-19), 23 decisions carried · Designed 2026-10-19

## Summary

jplugin gains `/diagram`, a thin skill that turns a system, flow, schema or
history into a checked, explorable standalone HTML diagram through
[Archify](https://github.com/tt-a1i/archify). Archify is installed once in user
scope as a pinned *tool*, never as a skill the harness can route to, so `/diagram`
is the only diagram entry point and the drawing instructions stay upstream's.
Diagrams of a real codebase always carry source citations verified against the
pinned commit. The homegrown `flow`/`sequence` DSL keeps drawing inline spec
fences; Archify draws the standalone diagrams. The one decision not to miss:
Node is a hard requirement for `/diagram`, a browser is not.

## Behavior

A user types `/diagram <what>` (or a phrase such as "draw the architecture",
"visualize the request flow", "map the module tree", "archify this"). The skill:

1. Locates the installed tool at `$ARCHIFY_HOME` (default
   `~/.local/share/jplugin/archify`). When it is absent, it prints the one-line
   install command and stops. When `node` is absent or older than 18, it says
   so and stops. Neither case produces a diagram or falls back to another renderer.
2. Reads upstream's authoring instructions from the install directory
   (`<home>/archify/SKILL.md` and the references it names) and follows them for
   type selection, candidate authoring and `finalize`. All ten diagram types are
   available; Archify's own type router picks.
3. Adds jplugin's conventions on top of upstream's:
   - **Evidence is mandatory for a codebase.** When the subject is a repository,
     the candidate pins `meta.repository` to the clean `HEAD` of that repository
     and every element of the primary collection (components, nodes,
     participants, states, entities, types, events or spans, per diagram type)
     carries `sources` (a path and a line); `finalize` runs
     with `--repo-root`, through the resolver's `finalize` wrapper, which runs
     the pre-finalize evidence check first whenever `--repo-root` is present and
     reads which collection is primary from the install's own schema. A
     described system (no repository) is authored freehand.
   - **Output location.** A system or architecture diagram lands at
     `docs/architecture/<slug>.html` beside its candidate
     `docs/architecture/<slug>.architecture.json` (or `<slug>.<type>.json`),
     regenerated in place. A diagram that illustrates a spec lands beside it as
     `specs/<feature>.<type>.html`. Archify's working folder `.archify/` is
     gitignored and holds receipts and captures only, reached through
     `--out-dir`; the one receipt Archify keeps beside the HTML,
     `<stem>.delivery.json`, is the provenance its `check` reads and is
     committed with the diagram.
   - **Browser resolution.** Before `finalize`, the skill sets `ARCHIFY_CHROME`
     to the first of: an existing `ARCHIFY_CHROME`, a Chrome or Chromium on
     `PATH`, the Chromium that `playwright-cli` installed. When none is found
     it runs the non-browser gates (`validate`, `deliver`, `check`) and states
     in its reply that browser evidence did not run.
   - **Diagrams only.** Archify's explainer mode is not exposed; a request for
     "a page" routes to `/html-presentation` as today.
4. `/diagram --refresh <path>` re-authors an existing committed candidate against
   the current `HEAD`: it re-reads the cited source, updates components,
   citations and the pinned revision, and re-runs `finalize`. Staleness is
   detected only through this command; `/wrap-up-session` leaves diagrams alone.
5. The reply follows Archify's output contract: a clickable link to the HTML,
   one or two sentences of takeaway for a codebase diagram, and anything that
   changes how the diagram should be read. It never claims visual review that
   did not happen.

Three existing skills gain a diagram moment:

- `/how` ends every answer with one line offering a diagram of the flow it just
  explained; nothing renders until the user says yes. Its explainer prompt stops
  suggesting Mermaid or ASCII diagrams in chat.
- `/plan` offers a diagram in one line after the spec is written, when the
  feature spans more than one component.
- `/system-design-planning` produces an architecture diagram beside its spec as
  part of its deliverable when the tool is installed, and prints the
  install command (without stopping) when it is not. Its `flow` and `sequence`
  fences are unchanged.

Installation and provenance:

- `install.sh` gains a section after the Playwright one: when `node` ≥ 18 is
  present it clones Archify at the pinned tag into `$ARCHIFY_HOME`, verifying
  the checked-out commit equals the pinned commit; when the directory already
  holds that commit it reports "present"; otherwise it prints a NOTE with the
  install command and continues. Nothing prompts and the exit code never changes.
- `.github/upstreams.json` gains an entry of `kind: "installed"` for Archify:
  `url`, `ref: refs/tags/v3.2.0`, `baseline` = the tag's commit, no `paths`,
  `source_notice`. `scripts/check-upstream-drift.py` accepts the new kind
  (`paths` forbidden, `ref` may be a tag) and reports drift for it the same way.
  Sources without `kind` keep today's vendored semantics.
- `THIRD_PARTY_NOTICES.md` gains an "Archify (installed tool)" section with the
  MIT notice; README's Sources section names it.
- `/tidy` gains a tenth check, `tools`, that compares the commit checked out in
  `$ARCHIFY_HOME` with the registry's pinned baseline. No install on this
  machine → inconclusive with the note; a different commit → Tier 1 with the
  re-install command printed, never applied.

## Inputs

- `/diagram <free-text subject>` — a described system, or a request about the
  current repository (or another path the user names).
- `/diagram --refresh <candidate.json | diagram.html>` — an existing committed
  candidate.
- Environment: `ARCHIFY_HOME` (install root override), `ARCHIFY_CHROME`
  (browser override), `node` on `PATH`.
- Upstream: `https://github.com/tt-a1i/archify` at tag `v3.2.0`, commit
  `208acba8d412335185b2056fedf54b3405df43fb`.

## Outputs

- A standalone HTML diagram, its candidate JSON and its `<stem>.delivery.json`
  at the paths above; Archify's other receipts and captures under `.archify/`.
- A chat reply per Archify's output contract, with the browser-evidence gap
  stated when it applies.
- install.sh: a cloned, pinned Archify under `$ARCHIFY_HOME`, or a NOTE.
- Drift job summary: a `drift:` line for Archify when upstream's tag moves ahead
  of the baseline.
- `/tidy` report: a `tools` row.

## Edge Cases

- Tool absent → the install command is printed and `/diagram` stops. No DSL or
  html-presentation fallback, silent or otherwise.
- `node` absent or < 18 → stated and stopped, with the Node requirement named.
- No browser → non-browser gates run; the reply says "automated checks passed
  without browser evidence". The diagram is still delivered.
- `finalize` fails → the skill follows upstream's repair contract (edit the
  connected neighbourhood, re-run with a new `--out-dir`), never claims success
  on a non-zero exit, and reports the failing gate when repair is exhausted.
- Dirty worktree when diagramming a codebase → the candidate still pins `HEAD`;
  the reply names the changed paths, and no uncommitted bytes are cited as
  evidence (upstream's rule).
- `--refresh` on a candidate whose cited component no longer exists → the
  component is removed or re-anchored from a fresh read of the source; the
  reply names what was dropped or merged.
- A request for "a page" or "an explainer" → not `/diagram`; routes to
  `/html-presentation`.
- `/system-design-planning` without the tool → the spec and its DSL diagrams are
  produced as today, plus one install-command line; the session does not stop.
- Pi and Codex sessions never ran `install.sh` → the printed install command is
  the only path; `/diagram` is otherwise harness-neutral (Node CLI, no Claude
  Code specifics).
- An `upstreams.json` entry of `kind: installed` with `paths` → the validator
  rejects it, naming the field.
- `$ARCHIFY_HOME` holds a commit other than the baseline → `/tidy tools` Tier 1
  finding; `install.sh` re-clones only when told to, never on its own.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | `/diagram` collides with `/html-presentation`, `/visual-plan`, `/visual-recap` on "make a picture" prompts | M | M | A triggerability `/eval` run once after the description is written, as information, not a gate (AC9) | 7 |
| R2 | Upstream SKILL.md changes shape between releases and `/diagram`'s conventions stop lining up | L | M | Pin by tag and commit; weekly drift line; bump is a deliberate PR | 4 |
| R3 | Reading upstream's long SKILL.md at run time costs context on every diagram | M | L | Accepted: upstream's instructions are the product; `/diagram` adds one short page | 1 |
| R4 | `playwright-cli`'s Chromium path differs across platforms | M | L | Resolution order ends in "no browser → non-browser gates", never a hard failure | 1 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Vendor, install or wrap? | Install in user scope with a thin jplugin skill; never copy the package into the repo | user | Upstream is actively released with its own update channel; design-stack set the user-scope precedent |
| 2 | User-facing skill or backend renderer? | Both, staged: `/diagram` first, consumer skills afterwards | user | One skill file is immediately useful; rewiring consumers is a second step |
| 3 | Missing Node or browser | Node is a hard requirement; a missing browser degrades to the non-browser gates, stated in the reply; never a silent fallback | user | Nothing runs without Node; a diagram with schema and route checks beats Mermaid |
| 4 | Where outputs live | `docs/architecture/` for system diagrams, beside the spec for spec diagrams; `.archify/` gitignored | user | Diagrams and their delivery receipt are documentation; review receipts and captures are scratch |
| 5 | Explainer mode | Not exposed | user | html-presentation already covers narrative pages; proactive pages would slow fast lanes |
| 6 | Diagram types | All ten; Archify's router picks | user | Curation drifts; jplugin contributes the *when*, not the *which type* |
| 7 | Name and triggers | `/diagram`, with "archify" among its trigger phrases | user | Skills are named for the job; the alias catches people who know the tool |
| 8 | Repository evidence | Mandatory for codebase diagrams; freehand only for described systems | user | Never Guess — Verify; uncited diagrams go stale silently |
| 9 | Workflow moments | `/how` offers, `/plan` offers, `/system-design-planning` produces; wrap-up does nothing | user | Offers keep fast lanes fast; wrap-up regeneration would rewrite committed documents unasked |
| 10 | Eval before merge | One triggerability eval run after the description is written, as information — run 2026-10-19, report `tasks/eval-results/diagram-triggerability.md` (3/6 target prompts fired, 0/6 neighbours collided; description rewritten) | user | Three skills plausibly claim "make a picture"; a gate was judged heavier than the risk |
| 11 | Install mechanism | Pinned clone into `~/.local/share/jplugin/archify`; not `npx skills add -g`, not a sixth design-stack source | user | A skill-scope install would be routable and collide with `/diagram`; design-stack's release ID hashes all sources together |
| 12 | Fate of the `flow`/`sequence` DSL | Kept for inline spec fences; Archify for standalone diagrams | user | Planning must work on a Python-only machine; a small flow needs no Chromium gate |
| 13 | Browser resolution | The skill resolves `ARCHIFY_CHROME` itself (PATH, then Playwright's Chromium) | user | The skill knows the harness's install layout; Archify does not |
| 14 | Provenance and drift | `upstreams.json` gains `kind: installed`; a THIRD_PARTY_NOTICES section; drift in the weekly summary and a `/tidy` check | user | Closes the design-stack gap with the same change |
| 15 | Who installs | `install.sh` when Node ≥ 18 is present; `/diagram` prints the command when the tool is missing | user | Machine-side setup lives in the installer; a skill that clones on its own is a side effect jplugin avoids |
| 16 | Pin format | Tag and commit as `install.sh` constants, tag in the resolver, 40-character commit as the `upstreams.json` baseline; the tests read the registry as their oracle and pin the other homes equal | user | The drift script already validates commits; a tag alone can be moved |
| 17 | Authoring instructions | Read upstream's SKILL.md from the install directory at run time; `/diagram` adds conventions only | user | Restating drifts every release; vendoring the docs splits one package across two pins |
| 18 | How `/how` offers | Always, in one closing line | user | Simplest rule; nothing renders unasked |
| 19 | Stale diagrams at wrap-up | Not touched; `--refresh` is the only regeneration path | user | Wrap-up regeneration would rewrite committed documents and churn diffs |
| 20 | Planning skills | `/plan` offers; `/system-design-planning` produces | user | SDP's entry bar is exactly when an architecture diagram earns its place |
| 21 | Drift reporting | Job summary plus a `/tidy` check; not the session banner | user | The banner is about the template itself |
| 22 | Install root override | `ARCHIFY_HOME`, mirroring `DESIGN_STACK_HOME` | assumed | Same shape as the existing user-scope install; tests need an isolated home |
| 23 | Escalate to `/system-design-planning`? | No; `/plan` with decisions carried | user | The `upstreams.json` change is one optional field on a file this repo owns; the decisions are already made |

## Acceptance Criteria

- AC1: `.agents/skills/diagram/SKILL.md` exists with `name: diagram`, a
  description whose trigger phrases include "diagram", "draw", "visualize" and
  "archify", universal harness, and passes `tests/test-skill-frontmatter.sh`;
  `python3 scripts/render-skills-table.py --check` passes with its README row.
- AC2: With `ARCHIFY_HOME` pointing at an empty directory, the skill's resolver
  script exits non-zero and prints exactly one install command; with `node`
  shimmed to report version 16 it exits non-zero naming the Node ≥ 18
  requirement; in both cases it writes no HTML.
- AC3: With a fixture install and a fixture `PATH` containing no browser but a
  `playwright-cli` browser directory, the resolver exports `ARCHIFY_CHROME`
  pointing at that Chromium; with neither, it exports nothing and prints the
  "without browser evidence" marker the skill's reply must carry.
- AC4: `SKILL.md` instructs the agent to read `$ARCHIFY_HOME/archify/SKILL.md`
  and names the four jplugin conventions (evidence, output paths, browser,
  diagrams only); it contains no restatement of Archify's type router, schemas
  or finalize repair contract (`tests/test-diagram-skill.sh` greps for the
  upstream read and for the absence of those headings).
- AC5: For a codebase subject, `SKILL.md` requires `meta.repository` pinned to
  `HEAD`, `sources` on every component (every element of the diagram type's
  primary collection) and `--repo-root` on `finalize`; a test fixture candidate
  without `sources` is named as rejected by the skill's pre-finalize check.
- AC6: `install.sh` on a machine with `node` ≥ 18 and an isolated `HOME` clones
  Archify into `$ARCHIFY_HOME` at commit `208acba8…` and reports "installed";
  a second run reports "present" without network; without `node` it prints a
  NOTE containing the install command and exits 0 (`tests/test-install-sh.sh`).
- AC7: `.github/upstreams.json` carries the Archify entry with
  `kind: "installed"`, `ref: "refs/tags/v3.2.0"` and the tag's commit as
  `baseline`; `scripts/check-upstream-drift.py --validate` passes; the same
  entry with a `paths` list fails validation naming `paths`
  (`tests/test-upstream-drift.sh`).
- AC8: `.gitignore` ignores `.archify/`; `THIRD_PARTY_NOTICES.md` has an Archify
  section with the MIT text; README § Sources names Archify.
- AC9: A triggerability `/eval` has been run once over at least six organic
  prompts (three that should route to `/diagram`, three that should route to
  `/html-presentation`, `/visual-plan` or `/visual-recap`) and its report is
  linked from the spec's § Decisions row 10 or from the PR description. The
  result informs the description wording and does not gate the merge.
- AC10: `/how`'s SKILL.md ends its output contract with the one-line diagram
  offer, and `references/explainer-prompt.md` no longer instructs Mermaid or
  ASCII diagrams (`tests/test-diagram-skill.sh` greps both).
- AC11: `/plan` § 4 Present carries the one-line diagram offer for
  multi-component features (`tests/test-diagram-skill.sh` greps it).
- AC12: `/system-design-planning` names the architecture diagram beside the
  spec as a deliverable and the no-tool behaviour: install command printed,
  session continues (`tests/test-diagram-skill.sh` greps both).
- AC13: `/tidy` § The checks has a `tools` row describing the `$ARCHIFY_HOME`
  commit vs registry baseline comparison, its inconclusive case and its Tier 1
  remedy; `tests/test-skill-references.sh` and `tests/test-doc-conventions.sh`
  still pass.
- AC14: `/diagram --refresh <path>` is documented in `SKILL.md` as the only
  regeneration path, and `/wrap-up-session`'s SKILL.md is unchanged by this
  feature (`git diff --stat` on it is empty at wrap-up).

## Implementation Paths

- `.agents/skills/diagram/**` — the skill page, its resolver script (tool and
  Node check, browser resolution, pre-finalize evidence check) and its
  pinned-version constant.
- `.agents/skills/how/SKILL.md`, `.agents/skills/how/references/explainer-prompt.md`
  — the closing offer; Mermaid/ASCII instruction removed.
- `.agents/skills/plan/SKILL.md` — the one-line offer in § 4 Present.
- `.agents/skills/system-design-planning/SKILL.md` — the architecture diagram as
  a deliverable and the no-tool line.
- `.agents/skills/tidy/SKILL.md` — the `tools` check row and its edge cases.
- `.github/upstreams.json`, `scripts/check-upstream-drift.py` — the `installed`
  kind and its validation.
- `install.sh` — the pinned clone section after Playwright.
- `.gitignore`, `THIRD_PARTY_NOTICES.md`, `README.md` — ignore rule, licence
  notice, skills-table row and Sources entry.
- `tests/test-diagram-skill.sh` — AC1 to AC5, AC10 to AC12 and AC14 over fixtures;
  `tests/test-upstream-drift.sh` — AC7; `tests/test-install-sh.sh` — AC6.

## Build Order

Sizing: 7 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 4: six systems, because the registry, its validator, its test, the notices file, README § Sources and the ignore rule are each a one-file root-level edit and together one provenance concern; slice 5: four systems, because the three consumer skills each take a one-paragraph offer and share one test file, and splitting them would make three slices of one sentence each.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Skill core | `/diagram` skill page, README row, and the resolver script that checks the tool and Node, then resolves the browser | `.agents/skills/diagram/**`, `README.md`, `tests/test-diagram-skill.sh` | — | 1, 2, 3 | `bash tests/test-diagram-skill.sh && bash tests/test-skill-frontmatter.sh && python3 scripts/render-skills-table.py --check` | 4 files · 2 systems · 3 ACs |
| 2 | Evidence and conventions | Upstream SKILL.md read at run time, the four jplugin conventions, the pre-finalize evidence check, and `--refresh` as the only regeneration path | `.agents/skills/diagram/**`, `tests/test-diagram-skill.sh` | 1 | 4, 5, 14 | `bash tests/test-diagram-skill.sh` | 3 files · 2 systems · 3 ACs |
| 3 | Installer | `install.sh` clones the pinned tag when Node ≥ 18 is present, reports present or a NOTE otherwise | `install.sh`, `tests/test-install-sh.sh` | — | 6 | `bash tests/test-install-sh.sh` | 2 files · 2 systems · 1 AC |
| 4 | Provenance | `kind: installed` in the upstreams registry and its validator, the notices section, README § Sources and the `.archify/` ignore rule | `.github/upstreams.json`, `scripts/check-upstream-drift.py`, `tests/test-upstream-drift.sh`, `THIRD_PARTY_NOTICES.md`, `README.md`, `.gitignore` | 1 | 7, 8 | `bash tests/test-upstream-drift.sh && python3 scripts/check-upstream-drift.py --validate` | 6 files · 6 systems · 2 ACs |
| 5 | Consumer offers | One-line diagram offers in `/how` and `/plan`, the architecture diagram as a `/system-design-planning` deliverable, Mermaid/ASCII instruction removed | `.agents/skills/how/SKILL.md`, `.agents/skills/how/references/explainer-prompt.md`, `.agents/skills/plan/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `tests/test-diagram-skill.sh` | 2 | 10, 11, 12 | `bash tests/test-diagram-skill.sh && bash tests/test-how-why-skills.sh` | 5 files · 4 systems · 3 ACs |
| 6 | Tidy tools check | The tenth `/tidy` check comparing the installed commit with the registry baseline | `.agents/skills/tidy/SKILL.md` | 4 | 13 | `bash tests/test-doc-conventions.sh && bash tests/test-skill-references.sh` | 1 file · 1 system · 1 AC |
| 7 | Triggerability eval | One `/eval` triggerability run over six organic prompts, its report linked, description wording adjusted | `.agents/skills/diagram/SKILL.md` | 5 | 9 | `bash tests/test-diagram-skill.sh && bash tests/test-skill-frontmatter.sh` | 1 file · 1 system · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/diagram-skill.md`.
Plan: `## Plan: diagram-skill` in `tasks/todo.md`, 7 slices, ready set <1, 3>.
Files: .agents/skills/diagram/**, .agents/skills/how/SKILL.md, .agents/skills/how/references/explainer-prompt.md, .agents/skills/plan/SKILL.md, .agents/skills/system-design-planning/SKILL.md, .agents/skills/tidy/SKILL.md, .github/upstreams.json, scripts/check-upstream-drift.py, install.sh, .gitignore, THIRD_PARTY_NOTICES.md, README.md, tests/test-diagram-skill.sh, tests/test-upstream-drift.sh, tests/test-install-sh.sh
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Archify is installed as a pinned tool under `$ARCHIFY_HOME` (tag v3.2.0, commit 208acba8d412335185b2056fedf54b3405df43fb), never as a skill and never copied into the repo (D1, D11, D16); Node ≥ 18 is a hard requirement and a missing browser degrades to the non-browser gates with the gap stated, with no fallback to the DSL or html-presentation (D3); `/diagram` reads `$ARCHIFY_HOME/archify/SKILL.md` at run time and restates none of it (D17); codebase diagrams pin `meta.repository` to HEAD with `sources` on every component (every element of the diagram type's primary collection, per AC5) and `--repo-root` on finalize (D8); the explainer mode is not exposed (D5); `/wrap-up-session` is not edited and `--refresh` is the only regeneration path (D19); the `flow`/`sequence` DSL and its tests are untouched (D12).
```
