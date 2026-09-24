---
implementation_paths:
  - AGENTS.md
  - CLAUDE.md
  - .agents/references/**
  - .agents/hooks/**
  - hooks/hooks.json
  - .agents/skills/sync/SKILL.md
  - .agents/skills/sync/scripts/sync-managed-block.py
  - .agents/skills/quality-gate/**
  - .agents/skills/wrap-up-session/**
  - .agents/skills/software-design-expert-review/**
  - .agents/skills/sweep/**
  - .agents/skills/tidy/**
  - .agents/skills/auto-push/**
  - .agents/skills/yolo/**
  - .agents/skills/build/**
  - .agents/skills/plan/**
  - .agents/skills/setup-deployment/**
  - .agents/skills/verify-deployment/**
  - .agents/skills/verify-evidence/**
  - .agents/skills/task-registry/**
  - .agents/skills/system-design-planning/**
  - .agents/skills/grilling/SKILL.md
  - .agents/skills/receive-review/SKILL.md
  - .agents/skills/memory-maintain/SKILL.md
  - .agents/skills/refresh/SKILL.md
  - .agents/skills/maintain-verification-skill/SKILL.md
  - .agents/agents/*.md
  - .claude/agents/*.md
  - .claude/settings.json
  - .claude/deployments/*.md
  - install.sh
  - scripts/install-codex.sh
  - scripts/render-codex.py
  - scripts/render-skills-table.py
  - project-template/CLAUDE.md
  - project-template/AGENTS.md
  - README.md
  - PI_SETUP.md
  - .github/workflows/sync-template.yml
  - tests/test-instruction-budget.sh
  - tests/test-skills-table.sh
  - tests/test-sync-managed-block.sh
  - tests/test-doc-conventions.sh
  - tests/test-model-tiers.sh
  - tests/test-review-context.sh
  - tests/test-agents.sh
  - tests/test-routine-skills.sh
  - tests/test-settings-json.sh
  - tests/test-install-sh.sh
  - tests/test-codex-install.sh
  - tests/test-syncable-paths.sh
  - tests/test-session-start.sh
  - tests/test-pre-compact.sh
  - tests/test-pre-push-gate.sh
  - tests/test-tdd-retirement.sh
  - tests/test-sweep-routines.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-memory-maintain-doc.sh
  - tests/test-refresh-skill.sh
---

# Spec: Single instruction file for every harness

> Origin: prompt — three grilling rounds (Q1–Q23), decisions final · Designed 2026-09-21 · Review status: **draft, critic pass applied, reviewer decisions recorded 2026-09-22** (dispatched `critic`: 3 MUST-FIX, 6 SHOULD-FIX, 2 NITPICK — 11 applied as edits, recorded as D14–D22, 0 declined; the four open items closed by the reviewer, see *Decisions*)
> Visual: specs/single-instruction-file.plan.html
> Not folded in — filed as follow-up issues after approval: auto-running the managed-block write on a project's first session (Q12), a repository-qualification guard for auto-sync (Q13), a graphify `PreToolUse` warning on root-level `Grep`/`Glob` while a fresh graph exists (Q23), and decommissioning the legacy `.claude/project.md` readers once downstream projects have migrated (D3).

## Problem

Every Claude Code session in this repository loads about 15k tokens of instructions from four files — `CLAUDE.md` (493 lines, 29 KB, 54 % review-protocol text), a stale `~/.claude/CLAUDE.md` copy, `.claude/project.md`, and a session banner that restates the skills table a third time — while Pi and Codex each read a different subset and no harness reads the same rules as another. After this change every harness reads one `AGENTS.md`: template rules inside a marker-delimited managed block under 200 lines, project rules below it, `CLAUDE.md` reduced to the single import line `@AGENTS.md`, protocol detail moved to `.agents/references/`, and the Claude Code hooks shipped by the `jplugin` plugin instead of copied per machine and per project. Out of scope: the three follow-ups named above, re-baselining `feat/106`, and any change to skill bodies beyond repointing citations and reading the reference files at dispatch time.

**Current state** — every path below was read at `7980eff`.

```text
 Claude Code session                          Pi session                    Codex session
 ───────────────────                          ──────────                    ─────────────
 ~/.claude/CLAUDE.md   (install.sh:195 copy;  CLAUDE.md natively            ~/.codex/AGENTS.md
   stale: lacks /system-design-planning)        (CLAUDE.md:5)                 (install-codex.sh:53
 CLAUDE.md:1-493                              AGENTS.md:1-70 "Pi only"        render_global :102-126,
   @.claude/project.md  :10  ─► 175 lines       Task Tracking :14              slices CLAUDE.md from
   @CLAUDE.local.md     :11                      Code Economy  :23 (dup of      "## Session Start Checklist")
                                                 project.md:67)                AGENTS.md:1-70
 ~/.claude/settings.json SessionStart ─► ~/.claude/hooks/session-start.sh (install.sh:236)
 .claude/settings.json  Stop, PreCompact ─► .claude/hooks/{session-stop,pre-compact}.sh
 session-start.sh:440-472  SKILLS AVAILABLE (30 hard-coded echo lines) · :474-477 "Ready." footer
 session-start.sh:278-281  reads `## Deployment Targets` from .claude/project.md only
 Skills catalogs: CLAUDE.md:453-493 · README.md:285-320 · session-start.sh:440-472 (three, hand-kept)
 Plugin: .claude-plugin/plugin.json → skills only; no hooks/ dir, no hooks.json
 Tests pinning the above: 118 CLAUDE.md references across 15 files (tests/*.sh)
```

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Managed block size | ≤ 200 lines between the markers in `AGENTS.md` | user (Q1–Q4); Anthropic memory docs "target under 200 lines" | **new** `tests/test-instruction-budget.sh` counts lines between `<!-- jplugin-agentic-development:begin -->` and `:end -->` |
| Whole-file size | `AGENTS.md` ≤ 16 KiB — half of Codex's `project_doc_max_bytes` default (32 KiB, from the Codex config docs; **inferred** — not re-verified in this recon), so a project's own rules have as much room as the template's | user (Q4) | same test, `wc -c` |
| `CLAUDE.md` is a pointer | exactly one non-blank line, `@AGENTS.md`; nothing else, ever | user (Q2) | same test, byte-compares the file to `@AGENTS.md\n` (CRLF tolerated) |
| No rule loads twice on any harness | Claude Code reads `CLAUDE.md` and follows the import once — with both files present only `CLAUDE.md` is read natively (memory docs § AGENTS.md); `AGENTS.md` carries no `@` line; the banner restates no rule and no skill list | Claude Code docs; user (Q1) | budget test: `AGENTS.md` has no line starting `@`; `tests/test-doc-conventions.sh` asserts the banner script has no `SKILLS AVAILABLE` block |
| Every removed rule keeps exactly one home | each section leaving `CLAUDE.md` / `.claude/project.md` is in the managed block, in one `.agents/references/*.md`, or in one skill — never in two, never in none | inferred; placements in *Ownership* accepted by the reviewer 2026-09-22 | repointed structural assertions (heading present in the named file); **new** citation test: every `` `<file>` § *<Heading>* `` in `.agents/` and `AGENTS.md` resolves to a `## `/`### ` heading in that file |
| Paths skills name are deliverable | `.agents/references/` and `.agents/hooks/` are syncable roots; no `SKILL.md` names a bare `scripts/…` path | `tasks/solutions/architecture/a-skill-may-not-name-a-path-sync-does-not-deliver.md` | `tests/test-syncable-paths.sh` (list agreement across the six hand copies + drift check) |
| Project text survives `/sync` byte-identical | everything outside the two markers in `AGENTS.md` is untouched by the managed-block write; the write is idempotent; the one-shot migration moves **every** line of `.claude/project.md` except the four generic sections and the file's own header, so no team text is lost (D15) | user (Q22 A) | **new** `tests/test-sync-managed-block.sh`: fixture with project text above and below the block; run twice; `cmp` outside-block bytes and the second run reports `unchanged`; migration fixture with a `## Tech Stack` section ends with that section below the end marker |
| No downstream window between slices | every slice carries the downstream-facing half of its own change: the `/sync` and CI write of the block ships **with** the pointer `CLAUDE.md` (slice 2); the `settings.json` hook migration ships **with** the retirement of `.claude/hooks/` (slice 3); `install.sh` step 1 is removed **with** the pointer (slice 2) (D14, D16, D17) | critic finding; inferred | slice criteria: on the slice-2 branch, a fixture project's `/sync` Step 5 ends with a block in `AGENTS.md`, never a pointer to a block-less file; on slice 3, a fixture `.claude/settings.json` with the old `Stop`/`PreCompact` entries ends without them |
| Unmigrated downstream projects keep working | a project with no markers gets the block appended on its next `/sync`; a `Task tracking instructions:` pointer or `## Deployment Targets` table still in `.claude/project.md` is still read, with a one-line deprecation notice, until the migration step moves it | reviewer 2026-09-22 (D3 A) | `tests/test-task-registry.sh` pointer fixtures at `.claude/project.md` (lines 577, 617, 1804) keep passing and gain the notice assertion; sync fixture without markers ends with exactly one block |
| Skill triggerability does not regress | `/eval` triggerability run on `/plan`, `/build`, `/quality-gate` with the new `AGENTS.md` scores ≥ the run against the current `CLAUDE.md` | user (Q21 A) | manual gate before merging slice 2; report path recorded in the slice-2 PR body |
| Each hook event fires once | `SessionStart`, `PreCompact`, `Stop` are registered in the plugin's `hooks/hooks.json` only; `.claude/settings.json` registers none of them and `install.sh` writes no `SessionStart` into `~/.claude/settings.json`; a downstream `settings.json` still carrying `bash .claude/hooks/<name>.sh` entries has them removed by the same `/sync` that retires the scripts | user (Q14–Q16); hooks docs: hooks from all sources merge and all run | `tests/test-settings-json.sh` asserts absence; `tests/test-install-sh.sh` asserts `~/.claude/settings.json` gains no `session-start.sh`; the `session_id` guard (`session-start.sh:47-107`) covers the banner only — `pre-compact.sh` and `session-stop.sh` have none, so the settings migration is the mechanism, pinned by a `/sync` fixture (D16) |
| Hooks stay portable | hook scripts remain bash, invoked as `bash "${CLAUDE_PLUGIN_ROOT}/.agents/hooks/<name>.sh"`, reading project state from the cwd Claude Code passes | inferred — tests run under Git Bash on Windows (`tests/run.sh`, #136) | `tests/test-session-start.sh`, `tests/test-pre-compact.sh` run the scripts from their new path |
| Failure-only banner | when nothing is wrong the banner is ≤ 12 lines: header, counts, tasks, git; drift, missing-block and graphify lines appear only on their condition; the missing-block line fires only in a repository that has adopted the workflow — `.claude/settings.json` enables `jplugin@jplugin-agentic-development` or `.agents/skills/` exists — because the plugin is installed at user scope and its hook runs in every repository the user opens (D18) | `AGENTS.md` § Observability Discipline | `tests/test-session-start.sh` fixtures: current block, no remote, no graph → no ⚠ line; a repository with neither signal and no `AGENTS.md` → no ⚠ line |
| Rollback | every slice is one PR of tracked files, reverted with `git revert`; installed-copy removal (slice 5) happens only after one confirmation and the removed copies are re-creatable by the previous `install.sh` | inferred | slice-5 test: `install.sh` under `N` at the prompt leaves every copy in place and reports `Kept(n)` |

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `AGENTS.md` — managed block (template) | Session Start Checklist; Workflow (PRD → Plan → Build → Wrap Up); Review Gate Taxonomy with a three-line stub pointing at the two references; Core Principles (Never Guess, Code Graph First naming the `graphify` CLI, APOSD list, Observability Discipline, Minimal Impact, No Silent Failures, File & Git Hygiene, one line each naming Clean Code and SOLID as standards `/quality-gate` checks); Quality Gate checklist; Key Directories; Agents rule (one paragraph, pointing at the routing reference); Task Tracking — the "`tasks/todo.md` is an index" rule and the pointer convention; Code Economy, Surgical Changes, Ambiguity Protocol, Large-Artifact Handoff, compressed to one clause of rationale each; the namespace sentence (`/jplugin:name` on Claude Code) | — |
| `AGENTS.md` — below the end marker (project) | `Task tracking instructions: <path>`; `## Deployment Targets`; team rules; in this repository also the Code Graph note that this shell/markdown repo has no code graph | — |
| `CLAUDE.md` | nothing — the one-line import | `AGENTS.md` |
| `.agents/references/finding-model.md` | four axes; emission format; confidence anchors; gates; resolving an anchor-75 finding; Independence Accounting | — |
| `.agents/references/review-dispatch-contract.md` | the seven items; empty-vs-absent; bounded items; repo-survey exception; share intent, withhold conclusions | `finding-model.md` for item 7 |
| `.agents/references/model-routing.md` | tiers; Ceiling; Floors; the Agents table with its Model column; Claude Code and Pi dispatch rules | `PI_SETUP.md` § Sub-Agent Routing for concrete IDs (unchanged) |
| `.agents/skills/task-registry/references/configuration.md` | provider-resolution order, pointer-file search order, refusal on dangling pointer (moved from `CLAUDE.md:410-450`) | `AGENTS.md` project section, legacy `.claude/project.md` |
| `.agents/skills/quality-gate/SKILL.md` § 1.2 / § 1.3 | the Clean Code and SOLID checklists (already there at `:88-99`; `CLAUDE.md` stops duplicating them) | `finding-model.md` |
| `.agents/hooks/{session-start,pre-compact,session-stop}.sh` | banner content and the checkpoint flush (moved from `.claude/hooks/`) | `AGENTS.md` (block presence, Deployment Targets), `tasks/`, git, `graphify-out/graph.json` |
| `hooks/hooks.json` (plugin root = repo root) | Claude Code registration of the three events | `.agents/hooks/*.sh` via `${CLAUDE_PLUGIN_ROOT}` |
| `.agents/skills/sync/scripts/sync-managed-block.py` | replacing the text between the markers; writing the one-line `CLAUDE.md`; the one-shot migration of `.claude/project.md` content below the end marker | template `AGENTS.md`, project `AGENTS.md`, `.claude/project.md` |
| `scripts/render-codex.py` | Codex agent TOML rendering and `hooks.json` merge (unchanged); `render_global` **removed** with the global Codex `AGENTS.md` it wrote | `.agents/agents/` |
| `scripts/render-skills-table.py` (template repository only) | the README skills table between `<!-- skills-table:begin -->` / `:end -->` | `.agents/skills/*/SKILL.md` frontmatter `name`, `description` |
| `install.sh` | plugin registration, `~/.agents/`, Pi config, graphify wiring, scaffold; **new** removal of stale pre-plugin copies after one confirmation | `~/.claude/`, `~/.codex/` |
| `project-template/` | scaffold seeds: one-line `CLAUDE.md`; `AGENTS.md` with a `# Project Instructions` title and empty project sections, **no** managed block (D2) | — |
| `/tidy` | `inventory` check now runs the generator; **new** `graph` check: graph staleness | `graphify-out/graph.json`, `git log -1` |

### Interaction

```text
 Claude Code start ─(1)─► CLAUDE.md ─@─► AGENTS.md [ managed block | project rules ]      both files read once
                   ─(2)─► plugin hooks/hooks.json SessionStart ─► .agents/hooks/session-start.sh ─► banner
 Pi start          ─(3)─► AGENTS.md natively · ~/.pi/agent/AGENTS.md personal (PI_SETUP.md:120)
 Codex start       ─(4)─► ~/.codex/AGENTS.md (personal text only; block no longer rendered) ─► AGENTS.md
 /sync in project  ─(5)─► git show workflow/<branch>:AGENTS.md ─► sync-managed-block.py ─► AGENTS.md between markers   NEW
                   ─(6)─► sync-managed-block.py --migrate ─► .claude/project.md content → below end marker → file deleted  NEW
 dispatching skill ─(7)─► cat .agents/references/finding-model.md § Emission format ─► pasted as item 7 of the reviewer prompt  NEW
 install.sh        ─(8)─► lists ~/.claude/CLAUDE.md, ~/.claude/hooks/session-start.sh, SessionStart entry, ~/.codex/AGENTS.md block ─► one [y/N] ─► removed / kept  NEW
 /tidy, CI         ─(9)─► render-skills-table.py --check ─► README table == frontmatter, or exit 1 with the diff  NEW
```

Every arrow is a synchronous local read or write; no network call except the `git fetch` `/sync` Step 2 already performs.

| Arrow | Mode | On failure | On duplicate / re-run |
|-------|------|------------|-----------------------|
| (1) | sync | `AGENTS.md` missing → Claude Code loads nothing from the project; in an adopting repository the banner (2) prints the missing-block line naming `/sync`; elsewhere it prints nothing (D18) | n/a — one read per session |
| (2) | sync | plugin not installed → no banner, no hooks; rules still load through (1). Script error → hook exit non-zero, Claude Code shows stderr, session continues | the banner's double-invocation guard keys on `session_id` (`session-start.sh:47-107`); `pre-compact.sh` and `session-stop.sh` have no guard, so a leftover project-level registration is removed by `/sync` (arrow 5, D16) rather than tolerated |
| (5) | sync | source has no markers → exit 2 `template AGENTS.md carries no managed block`; target has one marker of the two, or two begin markers → exit 2 naming the file, **nothing written**; write is tempfile + rename (`write_text`, `render-codex.py:35-49` pattern) | idempotent: second run prints `AGENTS.md: unchanged`, `CLAUDE.md: unchanged`, exit 0 |
| (6) | sync | `.claude/project.md` absent → `migration: nothing to move`; a `## Deployment Targets` heading already below the end marker **and** in `project.md` → exit 2, both locations named, nothing written; the same `/sync` step drops `Stop` / `PreCompact` / `SessionStart` entries whose command matches `.claude/hooks/<name>.sh` from `.claude/settings.json` (D16) | migration runs once: after the move `project.md` is deleted (with the rest of the sync's approved changes), so a re-run finds nothing |
| (7) | sync | the skill resolves the reference in order — project `.agents/references/`, then `${CLAUDE_PLUGIN_ROOT}/.agents/references/` on Claude Code, then `~/.agents/references/` (the copy `install.sh` step 3 writes) on Pi and Codex — and only when all three are missing stops before dispatch: `review dispatch refused: finding-model.md not found in <the three paths> — run /sync`; never dispatches a reviewer with no output format (D19) | n/a |
| (8) | sync | `N` at the prompt → `Kept(n)`; a `~/.claude/CLAUDE.md` whose first lines lack the `Template-managed` header is **never** listed — it is personal (D9) | second run finds nothing → `Clean` |
| (9) | sync | a `SKILL.md` without `name` or `description` → exit 2 naming the directory | idempotent; `--check` writes nothing |

### Failure unit

- **`AGENTS.md`** — if it is missing or its block is stale, every harness in that project runs on stale or absent rules; nothing else stops. The banner line is the only signal, by design (Q12 A: no auto-run).
- **Plugin** — if `jplugin` is not installed, Claude Code loses the banner, the checkpoint flush and the unpushed-commits warning together with the skills it already depended on since #156; the rules do not depend on it.
- **`.agents/references/`** — if a reference is missing, the review dispatches that need it refuse to run; `/build`'s inline gates and `/plan` are unaffected.
- **`/sync`** — a refused managed-block write leaves the project exactly as it was; the rest of the sync (skills, agents) is unaffected because the script runs as its own Step 5 sub-step.

## Component contracts

### Managed block (markdown, both directions of `/sync`)

```text
<!-- jplugin-agentic-development:begin -->
## <heading>            # `## ` and `### ` only — the project's `# ` title stays the sole H1
…
<!-- jplugin-agentic-development:end -->
```

| Aspect | Contract |
|--------|----------|
| Inputs | the template repository's own `AGENTS.md` is the source; the block is whatever lies between its markers |
| Invariants | ≤ 200 lines; no line starts with `@`; no line matches the registry's own `POINTER_RE` (`Task tracking instructions:\s*([^\s`<>]+)`, case-insensitive, mid-line — `config.py:36`), so the convention is documented with a `<path>` placeholder, never an example path; no `# ` heading; contains the namespace sentence; contains the two machine-parsed lines verbatim — the `[AMBIGUITY] … \| options: … \| picked: … \| reason: …` emission format and the `TODO(shortcut):` marker — because `/build:314` cites the section instead of restating them (D21); heading set is fixed (see *Data models*) |
| Legacy | markers with the `coding-agent-workflow` slug (`render-codex.py:23-24`, `LEGACY_BEGIN`/`LEGACY_END`) are recognised on read and replaced by the current slug on write |
| Versioning | none — the block is replaced wholesale; the template's git history is its version |

### `sync-managed-block.py` (`.agents/skills/sync/scripts/`)

```bash
python3 sync-managed-block.py --source <template-AGENTS.md | -> --target AGENTS.md \
    [--claude-md CLAUDE.md] [--migrate .claude/project.md] [--dry-run]
```

| Aspect | Contract |
|--------|----------|
| Inputs | `--source`: a file, or `-` for stdin (`git show workflow/<branch>:AGENTS.md | …`, the pattern `sync-retire.py` already uses); `--target`: the project's `AGENTS.md`, created if absent |
| Outcomes (stdout, one line each) | `AGENTS.md: replaced` · `AGENTS.md: appended` (no markers found) · `AGENTS.md: unchanged` · `CLAUDE.md: written` · `CLAUDE.md: unchanged` · `migration: moved <n> section(s), .claude/project.md deleted` · `migration: nothing to move` |
| Exit 2 (before any write) | source lacks a complete marker pair; target has an unmatched marker or more than one begin marker; `--migrate` finds `## Deployment Targets` both in `project.md` and below the end marker; `--claude-md` target is a directory |
| Raises | only I/O errors — a permission failure is reported with the path, never swallowed |
| Idempotency | second run with the same source is a no-op reporting `unchanged`; `--dry-run` prints the same outcome lines prefixed `would ` and writes nothing |
| Writes | tempfile + `os.replace` per file; text outside the markers is copied byte-for-byte, including line endings. Order is fixed so a crash between writes duplicates and never loses: `AGENTS.md` first (block and migrated sections), then `CLAUDE.md`, then the `project.md` delete last — after step one every rule exists in `AGENTS.md`, so an interrupted run leaves `project.md` as a redundant copy the next run removes |
| Migration (`--migrate`) | moves **everything** in `project.md` below its header (the leading `# ` title and the `> ` blockquote that describes the file, through the first `---`) except the four generic sections `### Code Economy`, `### Surgical Changes`, `### Ambiguity Protocol`, `### Large-Artifact Handoff` and the `### Task Tracking` prose that explains the pointer's placement (the block now owns all five); the moved text — pointer line, `## Deployment Targets`, every other `## `/`### ` section a team added — is appended below the end marker in its original order with headings unchanged; the pointer line, if present, is written first so `POINTER_FILES` finds it in `AGENTS.md`; `project.md` is deleted only after the moved text is on disk. A `## Project-Specific Rules` heading already present below the end marker is reused, not duplicated (D15) |

### `CLAUDE.md`

```text
@AGENTS.md
```

One line, LF or CRLF. `/sync` writes it whenever it differs (D4). `CLAUDE.local.md` keeps working: Claude Code loads it natively as a memory file, so the import line it had in `CLAUDE.md:11` is not needed.

### Reference files (`.agents/references/<name>.md`)

| Aspect | Contract |
|--------|----------|
| Structure | `# <Title>` then one sentence of purpose, then the fixed `## ` headings listed in *Data models* |
| Citation form, everywhere in `.agents/`, `.claude/agents/`, `AGENTS.md` | `` `.agents/references/<name>.md` § *<Heading>* `` — the string tests grep for |
| Read at dispatch | a skill that dispatches `code-reviewer`, `critic`, `security-reviewer`, or `software-design-expert-review` reads `finding-model.md` § *Emission format* and pastes it into the prompt as item 7; it reads `review-dispatch-contract.md` for items 1–6. Resolution order: `.agents/references/` in the project, then `${CLAUDE_PLUGIN_ROOT}/.agents/references/` (Claude Code — the skill body and the reference then come from the same plugin version), then `~/.agents/references/` (Pi, Codex); refusal only when all three miss (D19) |
| Versioning | none — synced wholesale under the `.agents/references/` root |

### `hooks/hooks.json` (plugin root)

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/.agents/hooks/session-start.sh\"" }] }],
    "PreCompact":   [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/.agents/hooks/pre-compact.sh\"" }] }],
    "Stop":         [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/.agents/hooks/session-stop.sh\"" }] }]
  }
}
```

| Aspect | Contract |
|--------|----------|
| Inputs | the same stdin JSON a settings hook receives (`session_id`, `cwd`, `source`); scripts keep parsing it with `json_string_field` (`session-start.sh:34-38`) |
| Working directory | the project — scripts keep their project-relative reads (`tasks/`, `.claude/.sync-check-cache`, `.claude/deploy-nudge-dismissed`) |
| Banner lines (session-start) | always: header, learning-store counts, active tasks, git line. Conditional, one line each, only on the condition: template drift (existing, now comparing the block — D6); `⚠  AGENTS.md has no jplugin-agentic-development managed block — run /sync` **only in an adopting repository** — `.claude/settings.json` enables `jplugin@jplugin-agentic-development`, or `.agents/skills/` exists (D18); `⚠  code graph stale: graphify-out/graph.json is older than HEAD — run graphify`; `⚠  graphify installed but no graph — run graphify` only when the tree has files in graphify's code-extension set. Removed: `SKILLS AVAILABLE` block, `Ready.` footer |
| Command string | the slice-3 test runs each `hooks.json` command through `bash -c` with `CLAUDE_PLUGIN_ROOT` set to a path containing a space and, on Windows, backslashes — the scripts' own tests run them by path and would not catch a quoting fault in the registration (D20) |
| Codex | `install-codex.sh:61-72` copies the three scripts from `.agents/hooks/` instead of `.claude/hooks/`; `codex/hooks/session_start.py:15` names the same adapter file names |
| Versioning | plugin `version` in `.claude-plugin/plugin.json` — hooks change → bump |

### `render-skills-table.py` (`scripts/`, template repository only)

```bash
python3 scripts/render-skills-table.py [--check]      # rewrites README.md between the markers, or exits 1 with a diff
```

| Aspect | Contract |
|--------|----------|
| Inputs | every `.agents/skills/*/SKILL.md`; frontmatter `name` and `description` parsed the way `render-codex.py:52-99` parses agent frontmatter; a directory with `harness:` other than `universal` gets that value in a third column |
| Outcomes | table sorted by directory name; `--check` exit 0 when identical, exit 1 with a unified diff |
| Exit 2 | a `SKILL.md` missing `name` or `description`, or `README.md` missing the marker pair |
| Naming from skills | `/tidy` names it as `python3 <template-clone>/scripts/render-skills-table.py` (the `<template-clone>` convention keeps it out of `test-syncable-paths.sh`'s scanner) |

### `install.sh` — removal of stale pre-plugin copies

| Aspect | Contract |
|--------|----------|
| Lists | `~/.claude/CLAUDE.md` when its first five lines contain `Template-managed`, **or** when its only non-blank line is `@AGENTS.md` — a pointer that step 1 wrote before slice 2 removed it (D9, D17); `~/.claude/hooks/session-start.sh` together with the `SessionStart` entry whose command ends `hooks/session-start.sh` in `~/.claude/settings.json` — one item, removed or kept together so no dangling command is left behind; the managed block (either slug) inside `~/.codex/AGENTS.md` — the file itself is never deleted (D8) |
| Prompt | one `Delete them? [y/N]` for the whole list, the `remove_legacy_skill_copies` shape (`install.sh:149-178`); outcome `Clean` / `Kept(n)` / `Removed(n)` printed in the summary; on `Kept` the summary adds `the kept SessionStart entry still fires the old banner alongside the plugin's` |
| Never | writes `~/.claude/CLAUDE.md`, `~/.claude/hooks/`, or a `SessionStart` entry; steps 1 and 5 (`install.sh:192-196`, `:233-277`) are removed, not skipped |
| `install-codex.sh` | stops rendering `~/.codex/AGENTS.md` (`:53-54` removed); `render_global` and `LEGACY_*` marker constants move to `sync-managed-block.py`, which `render-codex.py` no longer needs |

### Readers of project configuration

| Reader | Today | After |
|--------|-------|-------|
| `task-registry` `POINTER_FILES` (`config.py:35`) | `(".claude/project.md", "AGENTS.md", "CLAUDE.md")` | `("AGENTS.md", ".claude/project.md")` — `CLAUDE.md` dropped (it is a pointer); `project.md` kept as legacy with `doctor` printing `pointer found in .claude/project.md — /sync will move it to AGENTS.md` (D3) |
| `session-start.sh:278-281`, `/setup-deployment` Step 4, `/verify-deployment:38`, `/verify-evidence:65`, `/wrap-up-session:748`, `.claude/deployments/*.md` | `.claude/project.md` § Deployment Targets | `AGENTS.md` first (exact-match regex unchanged), then `.claude/project.md` with the same one-line notice; `/setup-deployment` **writes** to `AGENTS.md` only, below the end marker |
| `/build:314`, agents citing Code Economy / Surgical Changes / Ambiguity Protocol | `` `.claude/project.md` § *…* `` | `` `AGENTS.md` § *…* `` |

## Data models

### `AGENTS.md`

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| title | `# ` heading, 0..1 | the only H1 in the file | budget test: `grep -c '^# '` ≤ 1 |
| managed block | marker pair, 0..1 | exactly one begin and one end, begin before end | `sync-managed-block.py` exit 2; budget test in this repository requires exactly one |
| block body | markdown | ≤ 200 lines; no `@` line; no live pointer; fixed heading set below | budget test; `test-routine-skills.sh:511-513` repointed from `CLAUDE.md` to the extracted block |
| project rules | markdown below the end marker | may carry one `Task tracking instructions:` line and one `## Deployment Targets` | `test-routine-skills.sh:503-508`; deployment regex |

**Fixed heading set of the block, in order** — the budget test pins presence and order; wording inside is free:
`## Session Start Checklist` · `## Workflow: PRD → Plan → Build → Wrap Up` · `## Review Gate Taxonomy` · `## Core Principles` · `## Quality Gate` · `## Key Directories` · `## Agents` · `## Task Tracking` · `## Code Economy` · `## Surgical Changes` · `## Ambiguity Protocol` · `## Large-Artifact Handoff` · `## Skills`.

### Reference files — fixed headings

| File | `## ` headings, in order |
|------|--------------------------|
| `finding-model.md` | Four axes · Emission format · Confidence anchors · Gates · Resolving an anchor-75 finding · Independence Accounting |
| `review-dispatch-contract.md` | The seven items · Empty is not absent · Bounded items · Repo-survey dispatch · Share intent, withhold conclusions |
| `model-routing.md` | Tiers · Ceiling · Floors · Agents · Rules |

`tests/test-agents.sh:83-90` parses the Agents table from `model-routing.md` § Agents with the same `awk`; `tests/test-model-tiers.sh:69-72,108-113,194,213-220` and `tests/test-review-context.sh:36-100` repoint file names and keep their structural assertions (headings, table rows, `deferrals: none`, `no spec —`); their prose-wording assertions (`assert_prose_contains` on sentences) are **repointed** to the reference file in slice 1, because slice 1 moves the text verbatim and repointing costs the same as deleting — `test-model-tiers.sh:108-110` is the only static guard the Floors rule names for itself. Slice 2 deletes only the assertions whose sentence the block compression removes, and only from the block — the reference files keep their full text (D22).

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| two managed blocks in one `AGENTS.md` | script refuses on begin-count ≠ 1 before writing; budget test |
| `CLAUDE.md` with content beyond the import | budget test byte-compare; `/sync` rewrites it |
| a live `Task tracking instructions:` pointer inside the block | budget test; `test-routine-skills.sh` repointed extract |
| a `## Deployment Targets` table in two places | `--migrate` exit 2; readers take `AGENTS.md` first and print the notice for the legacy copy |
| a rule with two homes (e.g. Clean Code list in both the block and `/quality-gate`) | citation test + review; the block names the standard in one line and cites the skill |
| a hook registered in the plugin and in `.claude/settings.json` | `test-settings-json.sh` asserts the three events are absent from the template's project file; downstream, the `/sync` that retires `.claude/hooks/` removes the matching entries in the same run (D16) — only `session-start.sh` has a `session_id` guard, `pre-compact.sh` and `session-stop.sh` have none |
| a `settings.json` entry pointing at a script the retirement pass deleted | the entry removal and the script retirement are one `/sync` step; a hand-kept entry is reported by the banner's drift line, never silently tolerated |
| a reviewer dispatched without the output format | dispatching skills stop when the reference is missing (arrow 7) |

### Transitions — a project's instruction-file state

| From | To | Trigger |
|------|----|---------|
| `unmanaged` (no markers) | `managed` | `/sync` Step 5 → `AGENTS.md: appended`; `CLAUDE.md: written` |
| `legacy-markers` (`coding-agent-workflow` slug) | `managed` | `/sync` Step 5 → `AGENTS.md: replaced` with the current slug |
| `managed` | `stale` | the template's block changes (banner drift line, D6) |
| `stale` | `managed` | `/sync` Step 5 → `AGENTS.md: replaced` |
| `managed` + `.claude/project.md` present | `managed`, `project.md` absent | `/sync` Step 6.6 `--migrate`, inside the same approval as the rest of the sync |
| `broken` (unmatched marker) | `broken` | `/sync` refuses (exit 2, file and line named); a human repairs the file — never auto-repaired |

### Transitions — an installed copy on a machine

| From | To | Trigger |
|------|----|---------|
| `template-managed` `~/.claude/CLAUDE.md` | absent | `install.sh` removal step, `y` at the prompt |
| `template-managed` | `template-managed` | `N` at the prompt → `Kept(n)`, listed again next run |
| `personal` `~/.claude/CLAUDE.md` (no header) | `personal` | never listed, never touched |
| `~/.codex/AGENTS.md` with block | same file, block stripped | `y` at the prompt; personal text above and below preserved byte-for-byte |
| `~/.claude/settings.json` with the old `SessionStart` entry + script | both absent | `y` at the prompt — one item; `N` keeps both and the summary names the double banner |

### Transitions — a downstream project's `.claude/settings.json` hooks block

| From | To | Trigger |
|------|----|---------|
| entries `bash .claude/hooks/{session-stop,pre-compact}.sh` present, scripts present | entries absent, scripts absent | the slice-3-or-later `/sync`: Step 5's settings merge drops entries whose command matches `.claude/hooks/<name>.sh`, Step 6.4 retires the scripts — same approved run (D16) |
| entries present, scripts present | unchanged | `/sync` declined at Step 4 — nothing is written, hooks keep firing once (plugin not yet the only registration) |
| entries absent, plugin installed | unchanged | steady state — each event fires once from `hooks/hooks.json` |
| entries present, scripts absent (hand-deleted) | entries absent | next `/sync` — the merge does not require the script to exist |

### Migration and compatibility

Forward, per project: one `/sync` appends the block, writes the pointer `CLAUDE.md`, and (Step 6.6) moves `project.md` content and deletes the file — all under the single approval `/sync` Step 4 already asks for. Forward, per machine: one `install.sh` run removes the stale copies after one confirmation. Reverse: `/sync` never commits — the user does — so the rollback unit in a project is the commit the user made after the sync; `git revert` of it restores `CLAUDE.md`, `AGENTS.md`, `.claude/project.md` and the `settings.json` hook entries together, which is why `/sync` Step 6 asks for one commit covering the whole run. The previous `install.sh` tag re-creates the machine copies. Old layout under new tooling: readers keep the `.claude/project.md` fallback with a notice (D3), so an unmigrated project loses nothing; `AGENTS.md` without a block loads only project rules until the first sync, and the banner says so on every session.

## Build order

| # | Slice | Delivers | Depends on | Contract exposed | Size |
|---|-------|----------|------------|------------------|------|
| 1 | References move | `.agents/references/{finding-model,review-dispatch-contract,model-routing}.md` with verbatim text; `CLAUDE.md` sections replaced by three-line stubs; `.agents/references/` a syncable root; 11 citing files + `test-review-context.sh`, `test-model-tiers.sh`, `test-agents.sh`, `test-doc-conventions.sh` M1/M2 repointed; dispatching skills read the reference at dispatch time; citation test | — | reference-file headings; citation form | M |
| 2 | Single `AGENTS.md` + its delivery | the managed block (< 200 lines) in `AGENTS.md`; Pi `AGENTS.md` content and `project.md` project sections merged below the end marker; `.claude/project.md` deleted; `CLAUDE.md` → `@AGENTS.md`; `project-template/` seeds; every `.claude/project.md` reader repointed with the legacy notice; **`sync-managed-block.py` (replace / append / pointer — no `--migrate` yet), `/sync` Step 5 calling it instead of checking out `CLAUDE.md`, `sync-template.yml` mirroring through it, and the syncable-paths block rows `AGENTS.md (managed block)` and `CLAUDE.md (pointer)` — so the first downstream sync after this merge delivers the block with the pointer, never the pointer alone (D14)**; **`install.sh` step 1 removed (D17)**; `render_global` reads the block from `AGENTS.md` so `install-codex.sh` keeps working until slice 5; skills-table assertions repointed to `README.md`; budget test; block-invariant greps for `POINTER_RE`, the `[AMBIGUITY]` format and `TODO(shortcut):`; `/eval` gate | 1 | managed-block format; `CLAUDE.md` pointer; script CLI (partial) | L |
| 3 | Plugin hooks + slim banner + hook retirement | `hooks/hooks.json`; scripts moved to `.agents/hooks/` (syncable root); `.claude/hooks/` marked `RETIRED` in the syncable-paths block; `.claude/settings.json` without `Stop`/`PreCompact`; **`/sync` Step 5 settings merge drops downstream entries matching `.claude/hooks/<name>.sh` (D16)**; banner without skills list and footer, with the adoption-gated missing-block line (D18) and graphify lines; `/tidy` `graph` check; `install-codex.sh` copies from the new path; reference-resolution fallback chain in the dispatching skills (D19); command-string test (D20); plugin `version` bump | 2 | `hooks/hooks.json`; banner lines | M |
| 4 | `/sync` project migration + drift | `sync-managed-block.py --migrate` (everything but the five generic sections — D15); `/sync` Step 6.6 runs it inside the approved run; drift check by block text (D6); `test-sync-managed-block.sh` gains the migration fixtures (`## Tech Stack` section, doubled targets table → exit 2) | 2, 3 | script CLI (complete) | M |
| 5 | `install.sh` stops copying | step 5 removed (step 1 went in slice 2); removal step with one confirmation, pointer-content `~/.claude/CLAUDE.md` included; `install-codex.sh` no longer renders the global file; `render_global` deleted; README Layer 1 rewritten; `/tidy` `installed` check updated; `test-install-sh.sh`, `test-codex-install.sh` repointed | 3, 4 | `install.sh` prompt and outcome words | M |
| 6 | README skills table generator | `scripts/render-skills-table.py`; markers in `README.md`; `tests/test-skills-table.sh` drift test; `/tidy` `inventory` runs the generator as its Tier 0 fix | 2 | script CLI | S |

Slice 1 carries no behavioural risk — it moves text and repoints strings — and it is what makes slice 2's file small enough to evaluate; the riskiest unknown, skill triggerability, is measured inside slice 2 before its merge (D7).

### Slice criteria

- Slice 1: each reference file has its fixed heading set; `grep -rn 'CLAUDE.md` § \*\(Finding Model\|Review Dispatch Contract\|Model Routing\|Independence Accounting\)' .agents .claude/agents` is empty; `test-review-context.sh` requires `` `.agents/references/review-dispatch-contract.md` `` at every dispatch site; the `assert_prose_contains` assertions of `test-model-tiers.sh`, `test-review-context.sh` and `test-doc-conventions.sh` M1/M2 pass against the reference files (repointed, none deleted); `test-agents.sh` yields ≥ 10 names from `model-routing.md`; `test-syncable-paths.sh` passes with `.agents/references/` in all six copies; the citation test resolves every `§` citation; `/quality-gate`, `/wrap-up-session`, `/software-design-expert-review`, `/sweep` state the refusal line for a missing reference; `bash tests/run.sh` green.
- Slice 2: `test-instruction-budget.sh` passes (block ≤ 200 lines, file ≤ 16 KiB, `CLAUDE.md` byte-equal, heading set in order, no `@` line, ≤ 1 H1, no `POINTER_RE` match in the block, the `[AMBIGUITY]` format line and `TODO(shortcut):` present); `.claude/project.md` is absent and `git grep -l '\.claude/project\.md'` outside `tasks/`, `specs/` and the legacy-notice lines is empty; `test-routine-skills.sh` AC7 asserts the pointer in `AGENTS.md` below the end marker; `session-start.sh` finds `## Deployment Targets` in `AGENTS.md` and prints the notice for a fixture with it only in `project.md`; `test-sync-managed-block.sh` (first half): append on no markers, replace on current and legacy markers, `unchanged` on re-run, outside-block bytes identical (`cmp`), exit 2 on unmatched marker with nothing written, `--dry-run` writes nothing, `CLAUDE.md: written`; a fixture project synced from this branch ends with a block in `AGENTS.md` and the pointer `CLAUDE.md` in the same run; `/sync` SKILL.md Step 5 no longer lists `CLAUDE.md` in `git checkout`; `sync-template.yml` calls the script; `test-syncable-paths.sh` passes with the new rows; `install.sh` has no `cp … CLAUDE.md` and `test-install-sh.sh` asserts `~/.claude/CLAUDE.md` is not created; `test-codex-install.sh` asserts `Session Start Checklist` still lands in `$CODEX_HOME/AGENTS.md`; the `/eval` triggerability report shows no regression for `/plan`, `/build`, `/quality-gate` and its path is in the PR body; suite green.
- Slice 3: `hooks/hooks.json` is valid JSON with exactly the three events, each command starting `bash "${CLAUDE_PLUGIN_ROOT}/.agents/hooks/`; each command runs through `bash -c` with `CLAUDE_PLUGIN_ROOT` set to a path containing a space (and backslashes on Windows) and exits 0; `.claude/hooks/` has no `*.sh` and its row in the syncable-paths block begins `RETIRED`; `test-settings-json.sh` asserts no `SessionStart`, `PreCompact`, `Stop` in `.claude/settings.json`; a `/sync` fixture `.claude/settings.json` carrying `bash .claude/hooks/session-stop.sh` and `bash .claude/hooks/pre-compact.sh` ends with neither entry and its other keys byte-identical; `test-session-start.sh` fixture with a current block and no graph prints no `⚠` line and no `SKILLS AVAILABLE`; fixture with `graph.json` older than HEAD prints the stale line; adopting fixture with no block prints the missing-block line and a non-adopting fixture (no `.agents/skills/`, no `jplugin@` in settings, no `AGENTS.md`) prints no `⚠` line; a dispatching skill with the project reference removed resolves it from `${CLAUDE_PLUGIN_ROOT}` before refusing; `test-pre-compact.sh` passes from the new path; `/tidy` `graph` check is in its checks table; suite green.
- Slice 4: `test-sync-managed-block.sh` (second half): `--migrate` moves the pointer line, the targets table and a `## Tech Stack` section below the end marker in that order and deletes `project.md`; the four generic sections and the `### Task Tracking` prose are not moved; exit 2 on a doubled targets table with `project.md` intact; re-run reports `migration: nothing to move`; the banner drift line compares block hashes — a template commit touching only text below the end marker produces no drift line; suite green.
- Slice 5: `test-install-sh.sh`: `~/.claude/settings.json` gains no `session-start.sh`; a pre-seeded template-headed `~/.claude/CLAUDE.md` and a pre-seeded one whose only line is `@AGENTS.md` are both listed and removed on `y`, kept on `N` with `Kept(n)` and the double-banner note; a personal one is never listed; the `SessionStart` entry and its script are removed together; `test-codex-install.sh`: `$CODEX_HOME/AGENTS.md` not created, a pre-seeded one with a block ends with the block stripped and personal text intact; `render_global` absent from `render-codex.py`; README shows no `~/.claude/CLAUDE.md` in the Layer 1 tree; suite green.
- Slice 6: `render-skills-table.py --check` exits 0 on HEAD; removing one row from README makes it exit 1 with a diff; a fixture skill without `description` exits 2 naming the directory; `test-skills-table.sh` runs the check; `/tidy` `inventory` names the generator with the `<template-clone>` prefix; suite green.

## Decisions

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| D1 Home of the hook scripts | A `.agents/hooks/` (harness-neutral, syncable root, Codex copies from it) / B `hooks/` beside `hooks.json` at the plugin root | A — keeps "shared core under `.agents/`, adapters per harness" (`tasks/solutions/architecture/claude-code-primary.md`); `/build` (`SKILL.md:177`) and `/refresh` (`SKILL.md:26`) name `pre-compact.sh` and must name a syncable path | B is right if Codex and Pi never run these scripts — Codex does (`install-codex.sh:61-72`) |
| D2 Scaffold seed carries the block | A seed `project-template/AGENTS.md` with the block, pinned equal by a drift test / B seed without; the banner's missing-block line nudges `/sync` | **decided: B** (reviewer 2026-09-22) — Q12 A chose no automatic write, and `~/.agents/project-template/` is a stale install-time copy anyway, so a seeded block would be old on arrival and `/sync` stays the block's only writer | A is right if new projects must have rules before their first `/sync` |
| D3 Legacy `.claude/project.md` readers | A keep reading it after `AGENTS.md`, with a one-line notice, until a follow-up removes it / B cut now | **decided: A** (reviewer 2026-09-22) — the migration needs the user's `y`; a declined migration must not break `/task-registry` or deployment verification. The removal is filed as a follow-up issue after approval and carries: the readers to delete (`task-registry.py` `POINTER_FILES` second entry; the `## Deployment Targets` fallback in `/verify-deployment` and `session-start.sh`), the notice text they print, the removal condition (every tracked downstream project has run the slice-4 `--migrate`, or one release has passed), and the fixtures to delete (`tests/test-task-registry.sh` pointer fixtures at `.claude/project.md`, lines 577, 617, 1804, plus the notice assertion slice 4 adds) | B is right once every downstream project has synced past slice 4 |
| D4 `/sync` and a `CLAUDE.md` that is not the pointer | A always write `@AGENTS.md` (today's overwrite-wholesale contract, shown in the Step 4 diff) / B write only when the file carries the `Template-managed` header | A — `CLAUDE.md` has been template-managed since the first sync; B would leave a project reading a stale 493-line file forever | B is right if a downstream project is known to hand-write `CLAUDE.md` |
| D5 Citation string | `` `.agents/references/<name>.md` § *Heading* `` | as stated — greppable, resolvable by the citation test | — |
| D6 Drift signal for `AGENTS.md` | A path-based (`git diff --name-only … -- AGENTS.md`, as for `CLAUDE.md` today) / B compare `sha256` of the block in the fetched template ref with the project's | B — A flags drift whenever the template edits its own project rules below the markers | A is right if the fetch cache cannot expose the template's file content (it can: `git show workflow/<branch>:AGENTS.md`) |
| D7 Riskiest slice first (review card B4) | A reorder so the eval spike is slice 1 / B keep the user's order; run the eval inside slice 2 before merge | B — user decision Q20 A; slice 1 is a pure move | A is right if the eval needs the reference move undone to compare fairly — it does not, both variants are evaluated as whole files |
| D8 `~/.codex/AGENTS.md` | A strip the block, keep the file / B delete the file | A — the file holds personal Codex instructions (`test-codex-install.sh:31`) | B is right only if the file is provably template-only |
| D9 `~/.claude/CLAUDE.md` deletion guard | A list it only when its first five lines contain `Template-managed` / B list whenever it exists | A — a hand-written global file is the user's | B is wrong on every machine that never ran `install.sh` |
| D10 Skills catalog for Pi and Codex readers | A none in-file; README table (generated) is the one catalog, harnesses discover skills from frontmatter / B keep a table in the block | **decided: A** (reviewer 2026-09-22) — Pi loads `~/.agents/skills` (`PI_SETUP.md:141`), Codex loads `.agents/skills` from `install-codex.sh:50`; a table in the block is the third copy this spec removes. Verified 2026-09-22 against the Codex skills documentation (`learn.chatgpt.com/docs/build-skills`): Codex scans `.agents/skills` from the working directory up to the repository root and `~/.agents/skills`, and puts each skill's `name` and `description` into the model's context for implicit selection, budgeted at 2 % of the context window | B was right only if Codex did not surface skill descriptions — it does, so the caveat is removed |
| D11 Superseded architecture record | `tasks/solutions/architecture/layered-config-claude-md-template-claude-project-md-project.md` describes the three-file layering | write its successor via `/learn` at wrap-up of slice 2 (managed block / below-marker / `CLAUDE.local.md` + `~/.pi/agent/AGENTS.md`) and mark the old one superseded | — |
| D12 Compression target for the block | ≈ 125 lines: checklist 6, workflow 20, taxonomy stub 10, principles 22, quality gate 8, key dirs 12, agents 6, task tracking 8, code economy 14, surgical 6, ambiguity 7, handoff 5, skills sentence 2 | as estimated; the 200-line ceiling leaves 75 lines of slack for the reviewer's additions | — |
| D13 Generator location | `scripts/` (template-only) named from `/tidy` with the `<template-clone>` prefix / inside `.agents/skills/tidy/scripts/` | `scripts/` — the README it renders exists only in the template repository | the skill dir is right if downstream READMEs ever carry the table |

| D14 (critic, MUST-FIX) Downstream window between slices 2 and 4 | A ship the pointer `CLAUDE.md` in slice 2 and the `/sync` change in slice 4 / B fold the block write (`sync-managed-block.py` without `--migrate`, `/sync` Step 5, `sync-template.yml`, syncable-paths rows) into slice 2 | B — with A, every downstream `/sync` and every CI auto-merge between the two merges would replace 493 lines of rules with a pointer to a block-less file, and the drift line would nudge users into exactly that sync (`sync/SKILL.md:278`, `sync-template.yml:64`) | A is right only if no downstream project syncs between the two merges — not controllable |
| D15 (critic, MUST-FIX) What `--migrate` moves | A an enumerated subset (pointer, targets table, `###` children of Project-Specific Rules) then delete / B everything except the five generic sections and the file header, then delete | B — `project.md`'s own header invites team sections (`.claude/project.md:6-8`); A destroys any `## ` a team added, contradicting the byte-identical constraint | A is right if `project.md` were template-owned — it is the one file `/sync` never touched |
| D16 (critic, MUST-FIX) Downstream `.claude/settings.json` hook entries | A leave them (Step 5 merge preserves `hooks`, `sync/SKILL.md:290-291`) and rely on the `session_id` guard / B the same `/sync` that retires `.claude/hooks/` drops entries whose command matches `.claude/hooks/<name>.sh` | B — after retirement the entries would run deleted scripts on every `Stop` and `PreCompact`; before it, `pre-compact.sh` and `session-stop.sh` have no guard and the checkpoint flush would run twice | A is right only for `session-start.sh`, the one guarded script |
| D17 (critic, SHOULD-FIX) `install.sh` step 1 between slices 2 and 5 | A remove step 1 in slice 5 with step 5 / B remove step 1 in slice 2 and list a pointer-only `~/.claude/CLAUDE.md` as stale | B — with A a re-run of `install.sh` after slice 2 overwrites the global rules with `@AGENTS.md` pointing at nothing (`install.sh:195`), and D9's header test would then call that file personal | A is right if nobody re-runs `install.sh` between the merges — not controllable |
| D18 (critic, SHOULD-FIX) Missing-block line in every repository | A print whenever `AGENTS.md` lacks the block / B print only in an adopting repository (`jplugin@` enabled in `.claude/settings.json`, or `.agents/skills/` present) | B — the plugin is installed `--scope user` (`install.sh:87`) so the hook runs in every repository the user opens; A prints `run /sync` in repositories that never adopted the workflow, which is the false-positive class the failure-only rule forbids. The signal is the minimal one; the fuller repository guard stays the Q13 follow-up | A is right if the plugin were installed per project |
| D19 (critic, SHOULD-FIX) Reference resolution when the plugin is ahead of the project | A read `.agents/references/` from the project only and refuse otherwise / B resolve project → `${CLAUDE_PLUGIN_ROOT}/.agents/references/` → `~/.agents/references/`, refuse only when all three miss | B — the plugin cache refreshes on the `version` bump independently of the project's next `/sync` (`sync/SKILL.md:296-297`); A would block `/quality-gate`, `/wrap-up-session` and `/sweep` review dispatch, and with them the pre-push gate, in every downstream until it syncs | A is right if skills always ran from the project tree — on Claude Code they run from the plugin cache |
| D20 (critic, NITPICK) `hooks.json` command quoting on Windows | A trust `bash "${CLAUDE_PLUGIN_ROOT}/…"` / B test the registered command string with a spaced, backslashed root | B — the script tests run scripts by path and would never exercise the registration; one `bash -c` fixture closes it | — |
| D21 (critic, SHOULD-FIX, anchor 75 → resolved) Machine-parsed lines in the compressed block | A "wording inside is free" / B pin the `[AMBIGUITY] … \| options … \| picked … \| reason` line and the `TODO(shortcut):` marker as block invariants | B — `/build:314` cites the section instead of restating the format (read: it says "Per … § *Ambiguity Protocol*, sub-agents emit a single line"), so the block is the only home of a format the orchestrator parses; the anchor-75 dependency the critic named was read and confirmed | A is right if `/build` carried the format itself — it does not |
| D22 (critic, SHOULD-FIX) Prose assertions on moved sections | A delete `assert_prose_contains` assertions in slice 1 / B repoint them to the reference files in slice 1; delete in slice 2 only those whose sentence the block compression removes, and only against the block | B — slice 1 is a verbatim move, so repointing is free; `test-model-tiers.sh:108-110` is the only static guard the Floors rule names for itself (`CLAUDE.md` § Floors) | A is right if the references were compressed too — they are not |

**Open**: none. Reviewer decisions 2026-09-22: *Ownership* placements accepted as laid out; D2 B; D3 A with a decommissioning follow-up issue; D10 A with the caveat removed after verification. Declined critic findings: none.

## Acceptance Criteria

- `AGENTS.md` at the repository root carries the template rules between `<!-- jplugin-agentic-development:begin -->` and `<!-- jplugin-agentic-development:end -->`, in ≤ 200 lines, with the fixed heading set in order, and the file is ≤ 16 KiB.
- `CLAUDE.md` is byte-equal to `@AGENTS.md` plus a line ending, and `tests/test-instruction-budget.sh` fails on any other content.
- `.claude/project.md` does not exist; its four generic sections live in the block and its project sections below the end marker.
- `.agents/references/finding-model.md`, `review-dispatch-contract.md`, `model-routing.md` exist with their fixed headings, `.agents/references/` is a syncable root, and no file under `.agents/` or `.claude/agents/` cites `CLAUDE.md` § for those sections.
- Every skill that dispatches a reviewer reads `finding-model.md` § Emission format at dispatch time and refuses to dispatch when the file is missing.
- `hooks/hooks.json` at the plugin root registers `SessionStart`, `PreCompact` and `Stop` against `.agents/hooks/*.sh`; `.claude/hooks/` holds no scripts and `.claude/settings.json` registers none of the three events.
- The session banner prints no skills list and no footer; it prints one line when the block is missing, one when `graphify-out/graph.json` is older than HEAD, and nothing extra when nothing is wrong.
- `sync-managed-block.py` replaces only the text between the markers, appends a block when none exists, writes the one-line `CLAUDE.md`, migrates `.claude/project.md` content once, is idempotent, and refuses with exit 2 and no write on an unmatched marker.
- `install.sh` writes neither `~/.claude/CLAUDE.md`, nor `~/.claude/hooks/session-start.sh`, nor a `SessionStart` entry; `install-codex.sh` writes no `~/.codex/AGENTS.md`; one confirmation removes the stale copies and `N` keeps them.
- `scripts/render-skills-table.py --check` exits 0 on HEAD and `tests/test-skills-table.sh` fails when README drifts from the skill frontmatter.
- `bash tests/run.sh` is green after every slice, and the slice-2 PR body links an `/eval` triggerability report showing no regression on `/plan`, `/build`, `/quality-gate`.

## Implementation Paths

- `AGENTS.md`, `CLAUDE.md`, `project-template/{AGENTS.md,CLAUDE.md}` — the instruction files and their scaffold seeds.
- `.agents/references/*.md` — the three protocol references; `.agents/skills/task-registry/references/configuration.md` — provider resolution moved from `CLAUDE.md`.
- `.agents/hooks/*.sh`, `hooks/hooks.json` — hook scripts and their plugin registration; `.claude/settings.json` loses the two events.
- `.agents/skills/sync/SKILL.md`, `.agents/skills/sync/scripts/sync-managed-block.py`, `.github/workflows/sync-template.yml` — managed-block replacement and migration.
- `install.sh`, `scripts/install-codex.sh`, `scripts/render-codex.py` — stop writing global copies; remove stale ones.
- `scripts/render-skills-table.py`, `README.md` — generated skills table.
- `.agents/skills/{quality-gate,wrap-up-session,software-design-expert-review,sweep,tidy,auto-push,yolo,build,plan,setup-deployment,verify-deployment,verify-evidence}/SKILL.md`, `.agents/agents/*.md`, `.claude/agents/*.md`, `.claude/deployments/*.md`, `PI_SETUP.md` — repointed citations and readers.
- `tests/test-instruction-budget.sh`, `tests/test-sync-managed-block.sh`, `tests/test-skills-table.sh` — new; the seventeen existing tests listed in the frontmatter — repointed.
