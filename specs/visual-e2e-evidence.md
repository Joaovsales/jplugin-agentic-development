---
implementation_paths:
  - .claude/browsers/playwright-cli.md
  - .agents/skills/verify-evidence/SKILL.md
  - .agents/skills/verify-evidence/scripts/e2e_evidence.py
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/wrap-up-session/scripts/publish_evidence.py
  - install.sh
  - .gitignore
  - project-template/.gitignore
  - tests/test-browser-runbook.sh
  - tests/test-e2e-classifier.sh
  - tests/test-e2e-evidence.sh
  - tests/test-publish-evidence.sh
  - tests/test-install-sh.sh
---

# Spec: Visual E2E Evidence

## Behavior

`/verify-evidence --scope e2e` drives the browser through **`playwright-cli`**
(`@playwright/cli`, Microsoft's shell-driven version of Playwright MCP) as its
first-choice backend. Because it is a shell command and not an MCP server,
Claude Code, Codex and Pi use it the same way, with no per-harness setup. It runs
headless, so unattended runs (`/yolo`, routines, cloud containers) get a
full-fidelity browser and can pass VISUAL acceptance criteria.

A VISUAL AC passes only with a real PNG on disk: after the walkthrough reaches the
state the AC describes, the backend saves a screenshot to
`tasks/e2e-artifacts/<short-sha>/<AC-id>.png`. The `tasks/e2e-log.md` entry
references that file on a `Screenshot:` line. No file, no PASS.

At `/wrap-up-session`, § *E2E coverage* checks the log with `e2e_evidence.py`.
§ *The Pull Request* then publishes the referenced PNGs to the project's
`e2e-evidence` branch, which is orphaned (it shares no history with `master`). The
PR body gets a `## Visual evidence` section that embeds each screenshot under its
AC. The screenshots never land on the feature branch or on `master`.

This works in every project the harness runs in. Nothing is specific to one app.

## Inputs

- Spec ACs, classified VISUAL / DOM-FUNCTIONAL by the existing fail-closed
  classifier (unchanged).
- The available backends, detected at run time:
  - `command -v playwright-cli` for the Playwright CLI
  - Chrome MCP tools exposed in the session
  - Lightpanda MCP tools exposed in the session
- `tasks/e2e-log.md` entries and the PNGs they reference.
- The `origin` remote URL, which gives the GitHub `owner/repo` used in links.
- An optional project line below the AGENTS.md end marker:
  `E2E evidence: local`. It opts the project out of publishing.

## Outputs

- A backend order of **Playwright CLI → Chrome MCP → Lightpanda → STOP**, stated
  in `verify-evidence/SKILL.md`, plus a runbook at
  `.claude/browsers/playwright-cli.md`:
  - `fidelity: full`
  - `screenshot: file`
  - `detect_command: command -v playwright-cli`
  - the pinned version
- For each VISUAL PASS: a PNG at `tasks/e2e-artifacts/<short-sha>/<AC-id>.png`
  and a `Screenshot: <path>` line in its log entry.
- `e2e_evidence.py check [--log <path>] [--sha <short-sha>]`: exits 0 silently
  when every VISUAL PASS entry has its file at
  `tasks/e2e-artifacts/<entry-sha>/<AC-id>.png`. Otherwise it exits 1 with one
  line per offending entry; a missing log exits 2. `--sha` scopes the check to
  one walkthrough, since the log is append-only across sessions.
- `publish_evidence.py --sha <short-sha> [--repo <dir>]`, where `--sha` is
  required and names the commit the walkthrough ran at (wrap-up has committed
  since, so HEAD would name a directory with no PNGs):
  - pushes one commit to `origin/e2e-evidence` (creating the orphan branch if it
    doesn't exist) that adds every `tasks/e2e-artifacts/<short-sha>/*.png` as
    `<short-sha>/<AC-id>.png`; an unchanged tree links the existing tip
  - prints a markdown `## Visual evidence` section whose image links are pinned
    to that commit: `https://github.com/<owner>/<repo>/blob/<commit>/<short-sha>/<AC-id>.png?raw=true`
  - writes one `evidence:` line to stderr: `published <n> to <owner/repo>`
    with ` — public repo` or ` — visibility unknown` (when `gh` cannot say),
    `local <n>`, `none`, or `publish failed (<git error>)` (exit 1)
- An optional `install.sh` step (6b) that installs the pinned `@playwright/cli`
  (0.1.22) and its Chromium, and never blocks the install.
- `.gitignore` entries for `tasks/e2e-artifacts/` and `.playwright-cli/`, in both
  this repo and `project-template/`.

## Edge Cases

- **Only Chrome MCP is available.** Its screenshots are session IDs, not files, so
  a VISUAL AC is `BLOCKED` ("requires a file-capable full-fidelity browser").
  Playwright MCP is not a backend at all; the CLI replaces it.
  DOM-FUNCTIONAL ACs still run on it.
- **Only Lightpanda is available.** Unchanged: VISUAL is `BLOCKED` and
  DOM-FUNCTIONAL runs.
- **`playwright-cli` is installed but its Chromium is missing.** The first command
  fails. This is reported as a step failure that names
  `playwright-cli install-browser chromium`, and the run does not silently drop
  to Chrome.
- **A VISUAL PASS entry's PNG was deleted or never written.** `e2e_evidence.py
  check` fails and names the entry. Wrap-up treats that AC as having no
  walkthrough, and the existing run/acknowledge prompt applies.
- **No VISUAL PASS in the session.** The publisher pushes nothing and prints
  nothing, and the PR body has no `## Visual evidence` section.
- **The project sets `E2E evidence: local`.** Nothing is pushed. The PR body lists
  the local PNG paths under `## Visual evidence (local only)`.
- **`origin` is not GitHub.** Same as `local`: paths are listed, nothing is
  embedded, and one line explains why.
- **The `e2e-evidence` push is rejected (non-fast-forward, because another session
  published first).** The publisher refetches, rebuilds its commit on the new tip
  and retries once. A second rejection prints `evidence: publish failed`. Any
  other git failure (unreachable remote, denied access) fails on the first
  attempt with its own message. The PR is still created, and this failure never
  blocks the PR.
- **Re-running the publisher for the same short-sha.** It overwrites the same
  paths in a new commit. The evidence branch never gets a force-push.
- **The feature branch is rebased after publishing.** The links still resolve,
  because they point at the evidence commit, not the feature commit.
- **The repo is public.** Screenshots are public. The wrap-up report prints
  `evidence: published <n> to <owner/repo> — public repo` so that's never
  silent; when `gh` cannot answer it prints `— visibility unknown` rather than
  implying private. `E2E evidence: local` is the opt-out.
- **A `Screenshot:` path outside the layout.** `check` fails it and names the
  expected `tasks/e2e-artifacts/<entry-sha>/<AC-id>.png`, because the publisher
  reads that layout and would otherwise never publish the file.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where are screenshots published? | An orphan `e2e-evidence` branch in each project's own repo, embedded in the PR by commit-pinned blob URLs | user | Agnostic across projects, keeps images out of `master`, and inherits the repo's access control |
| 2 | Can a Chrome-only session pass a VISUAL AC? | No. Playwright goes first, and a Chrome-only VISUAL AC is `BLOCKED` | user | Chrome MCP can't write a PNG to disk, so it can't meet "no file, no PASS" |
| 3 | Which agents get Playwright? | All of them: Claude Code, Codex and Pi | user | The harness is agent-agnostic |
| 4 | MCP or CLI? | `@playwright/cli` driven from the shell, not `@playwright/mcp` | assumed | Every agent has a shell; Pi has no native MCP (it would need `pi-mcp-adapter`), and Codex would need its own `config.toml` registration. One path instead of three. Smoke-tested 2026-09-29: headless open → click → eval → `screenshot --filename` wrote a 1280×720 PNG |
| 5 | Before/after screenshots? | After only, one per VISUAL AC | assumed | YAGNI. "Before" means running the base commit's app, which doubles the walkthrough |
| 6 | Clean up the evidence branch? | Never. It only grows | assumed | The links in merged PRs must keep resolving |
| 7 | Screenshots for DOM-FUNCTIONAL ACs? | Not required; allowed if the backend can take one | assumed | They pass on text assertions, and requiring pictures adds noise |
| 8 | Version pinning | `install.sh` and the runbook pin one `@playwright/cli` version | assumed | It's 0.x and its command surface can change |
| 9 | Opt out of publishing | An `E2E evidence: local` line below the AGENTS.md end marker | assumed | Same convention as `Full suite:`. Privacy is never on the chopping block, so publishing must be switchable per project |
| 10 | Does publishing need a separate approval? | No. It runs under the same authorization as the wrap-up push | assumed | Same remote and same session, and the report states it |
| 11 | Gitignore the artefacts on the feature branch? | Yes, both `tasks/e2e-artifacts/` and `.playwright-cli/` | assumed | The evidence branch is the only place PNGs are committed |
| 12 | Which PNGs does the publisher publish? | Every PNG under `tasks/e2e-artifacts/<sha>/` for the given `--sha`, not every `Screenshot:` path in the log | build ambiguity | The log is append-only across sessions; `check` enforces the same layout, so the two cannot diverge |

## Acceptance Criteria

1. `verify-evidence/SKILL.md` § Backend resolution lists **Playwright CLI (1) →
   Chrome MCP (2) → Lightpanda (3) → none**. Playwright CLI is detected with
   `command -v playwright-cli`, not by the presence of MCP tools.
2. `.claude/browsers/playwright-cli.md` exists with frontmatter `name:
   playwright-cli`, `fidelity: full`, `screenshot: file`, `detect_command`, a
   pinned version and `platforms`. Its body gives the open / goto / click / fill /
   eval / console / screenshot / close commands. `tests/test-browser-runbook.sh`
   validates every runbook in `.claude/browsers/`, not only Lightpanda.
3. The outcome matrix gets a row: Chrome MCP only + VISUAL → `BLOCKED`, never
   `PASS`. `tests/test-e2e-classifier.sh` pins it.
4. § Evidence Format requires a `Screenshot: tasks/e2e-artifacts/<short-sha>/<AC-id>.png`
   line on every VISUAL PASS, and Iron Law 5 is extended to say "a VISUAL PASS
   without its PNG on disk is not a PASS".
5. `e2e_evidence.py check [--log tasks/e2e-log.md]`:
   - exits 0 silently when every VISUAL PASS entry references an existing PNG
     at `tasks/e2e-artifacts/<entry-sha>/<AC-id>.png`
   - exits non-zero, naming the entry and AC, when the `Screenshot:` line is
     missing, names another path, or the file is absent
   - `--sha` limits the check to one walkthrough's entries
   - ignores DOM-FUNCTIONAL and BLOCKED entries

   Pinned by `tests/test-e2e-evidence.sh` with fixture logs.
6. `/wrap-up-session` § *E2E coverage* runs `e2e_evidence.py check`. A failing
   entry counts as "no e2e walkthrough" and goes to the existing
   run/acknowledge prompt.
7. Against a bare-repo fixture remote, `publish_evidence.py`:
   - creates the orphan `e2e-evidence` branch on first run, whose commit has no
     parent from the feature branch
   - adds a child commit on later runs
   - never force-pushes
   - leaves the feature branch's tree and HEAD untouched
   - prints a `## Visual evidence` section with one `![AC-id](…/blob/<evidence-commit>/<short-sha>/<AC-id>.png?raw=true)`
     per PNG

   Pinned by `tests/test-publish-evidence.sh`.
8. The publisher prints nothing and pushes nothing when there are no VISUAL PASS
   PNGs. It prints local paths only, and pushes nothing, when AGENTS.md has
   `E2E evidence: local` or `origin` is not GitHub. Pinned by
   `tests/test-publish-evidence.sh`.
9. On a non-fast-forward rejection, the publisher refetches, rebuilds and retries
   once. A second failure exits non-zero with `evidence: publish failed`, and
   wrap-up still creates the PR. Pinned by a fixture that advances the remote
   between fetch and push.
10. `/wrap-up-session` § *The Pull Request* inserts the publisher's section into
    the PR body before `gh pr create` and on every re-sync, passing the
    short-sha § *E2E coverage* checked. The wrap-up report carries an
    `Evidence:` line (`published <n> to <owner/repo>` plus a `public repo` or
    `visibility unknown` marker, or `local <n>`, `none`, or `publish failed`).
11. `install.sh` has an optional step that installs the pinned `@playwright/cli`
    globally, then runs `playwright-cli install-browser chromium`. When `npm` is
    missing it prints a NOTE and continues with exit 0. `tests/test-install-sh.sh`
    pins both paths.
12. `.gitignore` and `project-template/.gitignore` contain `tasks/e2e-artifacts/`
    and `.playwright-cli/`.
13. `bash tests/run.sh` is green — proved by `/wrap-up-session` § *Full suite* through `cached-suite.sh`, never by a slice checkpoint.

## Implementation Paths

- `.claude/browsers/playwright-cli.md`: adapter runbook for the first-choice
  backend (the contract and the command crib)
- `.agents/skills/verify-evidence/SKILL.md`: backend order, outcome matrix,
  Evidence Format `Screenshot:` line, Iron Law 5
- `.agents/skills/verify-evidence/scripts/e2e_evidence.py`: the mechanical
  "no file, no PASS" check
- `.agents/skills/wrap-up-session/SKILL.md`: § E2E coverage calls the check;
  § The Pull Request calls the publisher and adds the report line
- `.agents/skills/wrap-up-session/scripts/publish_evidence.py`: orphan-branch
  publish plus the PR body section
- `install.sh`: optional Playwright CLI and Chromium install
- `.gitignore`, `project-template/.gitignore`: keep artefacts off feature branches
- `tests/test-browser-runbook.sh`, `tests/test-e2e-classifier.sh`,
  `tests/test-e2e-evidence.sh`, `tests/test-publish-evidence.sh`,
  `tests/test-install-sh.sh`: pin the contract

## Build Order

Sizing: 5 slices. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Playwright CLI backend | The Playwright CLI runbook, backend order Playwright CLI → Chrome → Lightpanda, and the Chrome-only VISUAL `BLOCKED` row, with the runbook test covering every runbook | `.claude/browsers/playwright-cli.md`, `.agents/skills/verify-evidence/SKILL.md`, `tests/test-browser-runbook.sh`, `tests/test-e2e-classifier.sh` | — | 1, 2, 3 | `bash tests/test-browser-runbook.sh && bash tests/test-e2e-classifier.sh` | 4 files · 2 systems · 3 ACs |
| 2 | Screenshot evidence check | The `Screenshot:` line and "no file, no PASS" in Evidence Format and Iron Law 5, `e2e_evidence.py check`, and the gitignore entries | `.agents/skills/verify-evidence/SKILL.md`, `.agents/skills/verify-evidence/scripts/e2e_evidence.py`, `tests/test-e2e-evidence.sh`, `.gitignore`, `project-template/.gitignore` | 1 | 4, 5, 12 | `bash tests/test-e2e-evidence.sh && bash tests/test-e2e-classifier.sh` | 5 files · 2 systems · 3 ACs |
| 3 | Evidence branch publisher | `publish_evidence.py` pushes PNGs to the orphan `e2e-evidence` branch and prints the PR section, with opt-out, non-GitHub fallback and one retry | `.agents/skills/wrap-up-session/scripts/publish_evidence.py`, `tests/test-publish-evidence.sh` | — | 7, 8, 9 | `bash tests/test-publish-evidence.sh` | 2 files · 2 systems · 3 ACs |
| 4 | Wrap-up wiring | § E2E coverage runs the check; § The Pull Request embeds the evidence section and reports `evidence:` | `.agents/skills/wrap-up-session/SKILL.md` | 2, 3 | 6, 10, 13 | `bash tests/test-e2e-evidence.sh && bash tests/test-publish-evidence.sh && bash tests/test-doc-conventions.sh` | 1 file · 1 system · 3 ACs |
| 5 | Optional Playwright install | `install.sh` installs the pinned `@playwright/cli` and Chromium, or prints a NOTE when npm is missing | `install.sh`, `tests/test-install-sh.sh` | — | 11 | `bash tests/test-install-sh.sh` | 2 files · 2 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/visual-e2e-evidence.md`.
Plan: `## Plan: visual-e2e-evidence` in `tasks/todo.md`, 5 slices, ready set 1, 3, 5.
Files: .claude/browsers/playwright-cli.md, .agents/skills/verify-evidence/SKILL.md, .agents/skills/verify-evidence/scripts/e2e_evidence.py, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/wrap-up-session/scripts/publish_evidence.py, install.sh, .gitignore, project-template/.gitignore, tests/test-browser-runbook.sh, tests/test-e2e-classifier.sh, tests/test-e2e-evidence.sh, tests/test-publish-evidence.sh, tests/test-install-sh.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/visual-e2e-evidence.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Drive the browser with `@playwright/cli` from the shell, never `@playwright/mcp` (Decision 4).
The evidence branch is never force-pushed, and publish failure never blocks the PR (Decisions 6, AC 9).
Screenshots are "after" only, for VISUAL ACs only (Decisions 5, 7).
```
