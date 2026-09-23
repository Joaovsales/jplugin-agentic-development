# jplugin for agentic development

A reusable, project-agnostic configuration system that enforces **spec-driven, TDD-first development** across all your projects — with persistent memory, specialized agents, and a structured session lifecycle. Works with Claude Code, Codex, Pi, Cursor, and other AI coding tools.

---

## What's Included

| Layer | What it does |
|-------|-------------|
| **AGENTS.md** (managed block) | Core rules: Spec → Plan → TDD workflow, Clean Code, SOLID, quality gate — one file read by Claude Code (through the `@AGENTS.md` line in `CLAUDE.md`), Pi and Codex; `/sync` rewrites only the block |
| **Skills** (`.agents/skills/`) | Cross-harness workflows for planning, building, verification, review, learning, synchronization, and project-specific verification recipes |
| **Agents** (`.claude/agents/`) | 8 specialized subagents for planning, coding, review, debugging, security |
| **Hooks** (`.agents/hooks/`) | Session banner, checkpoint flush and unpushed-commit warning, registered once by the plugin's `hooks/hooks.json` |
| **Learning store** (`tasks/solutions/`) | Typed per-document learnings, grep-first retrieval, written via `/learn` |

Codex uses the same canonical `.agents/` sources through the explicit adapter
`bash scripts/install-codex.sh`; no Codex-specific project rules are required.

## Codex Setup

From the workflow repository, install the shared user-level configuration:

```bash
git clone <this-repo-url> ~/jplugin-agentic-development
cd ~/jplugin-agentic-development
bash scripts/install-codex.sh
```

The adapter installs skills in `~/.agents/skills/`, converts canonical Markdown
agents into `~/.codex/agents/*.toml`, and merges optional lifecycle hooks into
`~/.codex/hooks.json`. It writes no `~/.codex/AGENTS.md`: the shared rules reach
Codex through the managed block `/sync` writes into each project's `AGENTS.md`
(a block an earlier adapter rendered into `~/.codex/AGENTS.md` is offered for
removal by `install.sh`). Existing personal content is preserved and rerunning
the command is idempotent. Review the hook commands with Codex's `/hooks` command
before enabling them.

For a non-default Codex directory, set `CODEX_HOME` before running the script.
For an existing project, run `bash ~/jplugin-agentic-development/scripts/scaffold-project.sh`
from inside the repository: it adds the neutral `project-template/AGENTS.md`
seed and the rest of the scaffold without touching files already present. The
Codex adapter registers no git alias; `git scaffold` and `newproject` come from
`install.sh` (below), which you can run as well.

Update all installed workflow artifacts with:

```bash
cd ~/jplugin-agentic-development
git pull
bash scripts/install-codex.sh
```

---

## Using This as Your Default for Every Project

Run `install.sh` once. It sets up three layers of enforcement: layers 1 and 3 activate automatically for every future project, and layer 2 is the one explicit `git scaffold` step that `newproject` runs for you.

### Step 1 — Clone and install

```bash
git clone <this-repo-url> ~/jplugin-agentic-development
cd ~/jplugin-agentic-development
bash install.sh
```

Then paste the printed `newproject()` function into your `~/.bashrc` or `~/.zshrc`:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

### Step 2 — Start every new project with

```bash
newproject my-app
cd my-app
claude
```

That's it. Claude is fully oriented from the first message.

---

## What `install.sh` Does

### Layer 1 — Global Claude config (`~/.claude/`)

Copies the agents into `~/.claude/agents/`, and registers this checkout as a Claude Code plugin marketplace with the `jplugin` plugin installed at user scope. Claude Code reads all of it for **every session in every project** — no per-project setup needed. Nothing else is written under `~/.claude/`: the shared rules live in the managed block of each project's `AGENTS.md` (written by `/sync`), and the session hook runs from the plugin's `hooks/hooks.json`.

```
~/.claude/
├── agents/            ← all agents available in every project
└── plugins/           ← Claude Code's own records: the jplugin-agentic-development
                         marketplace (this checkout) and the installed jplugin plugin
```

An earlier `install.sh` also wrote `~/.claude/CLAUDE.md`, `~/.claude/hooks/session-start.sh` with a `SessionStart` entry in `~/.claude/settings.json`, and (through the Codex adapter) a managed block in `~/.codex/AGENTS.md`. Nothing reads those copies now — the hook copy fires a second banner beside the plugin's — so the installer lists whichever it finds and deletes them only after you answer `y`. A personal `~/.claude/CLAUDE.md` without the template header is never listed, and `~/.codex/AGENTS.md` itself is never deleted, only its block.

Skills are **not** copied into `~/.claude/skills/` any more: the plugin manifest (`.claude-plugin/plugin.json`) points Claude Code at `.agents/skills/` in the checkout, so every skill is invoked as `/jplugin:<name>` (bare `/<name>` also resolves while no other skill claims the name). If an earlier install left copies in `~/.claude/skills/`, the installer lists them and deletes them only after you answer `y`; anything there the template never shipped is never touched. Without the `claude` CLI on `PATH` the plugin step prints a note and skips.

**Requires Claude Code 2.1.227 or newer** (plugin `skills` paths). **Developing skills in the checkout:** run `claude --plugin-dir <checkout>` — the checkout's own `.claude/settings.json` declares the github marketplace, which replaces the directory registration `install.sh` made, so a plain session loads the cached release, not your edits.

The **SessionStart hook** runs from the plugin (`hooks/hooks.json`) at the start of every Claude Code session. It prints:
- Learning-store counts from `tasks/solutions/` (documents + needs_review)
- Pending and in-progress tasks from `tasks/todo.md`
- Current git branch and uncommitted change count
- One warning line per problem, and nothing when there is none: template drift, an `AGENTS.md` without the managed block in an adopting project, a stale code graph

### Layer 2 — Project scaffold (`git scaffold`)

Copies `project-template/` to `~/.agents/project-template/` and registers a global git alias, `git scaffold`, that copies it into the current repository. Git has no post-init hook, so bootstrap is an explicit command rather than a side effect of `git init`. It only ever **adds** files — anything already present is kept byte-for-byte, so it is safe to re-run in any repo:

```
tasks/todo.md            ← active task plan
tasks/solutions/         ← typed learning store (schema in its README.md)
tasks/history.md         ← session narrative log
tasks/concepts.md        ← concept glossary (swept once by /memory-maintain, then accreted)
specs/                   ← feature specification directory
AGENTS.md               ← project instructions for every harness (/sync adds the shared block)
CLAUDE.md               ← the single line @AGENTS.md (Claude Code's import)
.gitignore, .gitattributes, .ignore
```

The installer also sets `git config --global init.templateDir ~/.git-templates` so new repositories receive the pre-push hook.

### Layer 3 — `newproject` shell function

```bash
newproject() {
  local name="${1:?Usage: newproject <project-name>}"
  mkdir -p "$name" && cd "$name" || return 1
  git init -q && git scaffold || return 1   # explicit bootstrap: git has no post-init hook
  echo "# $name" > README.md
  git add . && git commit -q -m "chore: init project with coding-agent scaffold" || return 1
}
```

Wraps `git init` plus `git scaffold` (layer 2) and makes an initial commit. One command from zero to a scaffolded project that can be opened with Claude, Codex, Pi, or another supported harness.

### Optional — graphify code graph

`graphify` builds a queryable code graph so the agent can traverse a repo instead of grepping it. It is entirely optional — everything above works without it.

The split matters: **the CLI installs once per machine, the graph is per project and per clone.**

```bash
pip install graphify        # once per machine

# inside each project (per clone — none of this is shared)
graphify update .           # build/refresh graphify-out/graph.json
graphify claude install     # rules section (install.sh moves it into AGENTS.md) + PreToolUse hook
graphify hook install       # re-index on commit/checkout
```

`install.sh` runs the per-project wiring for you when the `graphify` CLI is on your `PATH`, and skips it silently when it isn't.

---

## Keeping It Up to Date

Re-running `install.sh` is safe — it overwrites `~/.claude/` with the latest version:

```bash
cd ~/jplugin-agentic-development
git pull
bash install.sh
```

**Releasing skills to synced projects.** Claude Code pins each project's copy of the plugin
to `version` in `.claude-plugin/plugin.json` and refreshes it only when that value changes, so
bump `version` in the same commit as any skill change every synced project should pick up.
`/sync` merges the marketplace declaration into the project; Claude Code caches the new
release on the project's next open. A marketplace `ref` is never written — it would have to
be a branch or tag, and the version is the pin.

The repository was renamed from its original slug. A clone made before the rename still
works through GitHub's redirect, but point it at the current name once so the redirect is
not load-bearing:

```bash
git remote set-url origin https://github.com/Joaovsales/jplugin-agentic-development.git
```

If you pasted `newproject` into your shell rc before `git scaffold` existed, replace it with the function the installer prints: the old one relied on a post-init hook git never runs, so it committed unscaffolded repos.

---

## Adding to an Existing Project

No need to use `newproject`. From inside the repository:

```bash
git scaffold
```

It adds every missing scaffold file and leaves existing ones untouched, so a project that already has its own `AGENTS.md` or `.gitignore` keeps them. Nothing is overwritten; to replace a file deliberately, delete it first and run `git scaffold` again.

Then edit `AGENTS.md` to fill in your project's stack and test commands, and run
`/sync` once to add the shared rules block.

---

## Session Workflow

```
Feature Request
    │
    ▼
/brainstorm ──► explore options → multi-option proposals → design approval
    │
    ▼
/plan ──► interviews you → writes spec → /slice → § Build Order + plan block → build prompt
    │
    ▼  (fresh session started with the build prompt)
/build ──► pre-flight files the slices → ready set → TDD + sub-agents → handovers → quality-gate → spec validation
    │
    ▼  (all tasks done)
/security-scan ──► audit changed files for OWASP issues
    │
    ▼
/wrap-up-session ──► verify → code review → sync learnings → merge worktree → push
```

---

## Skill Interdependency

```mermaid
flowchart TD
    A[Feature Request] --> B["/brainstorm\nDivergent design exploration"]
    B --> C["/plan\nSpec + task breakdown"]
    C --> D["/build\nAutonomous TDD orchestrator"]
    D --> E["/security-scan\nOWASP audit"]
    E --> F["/wrap-up-session\nReview, test, push"]

    %% Skills called by /build
    D -->|"after each task"| D2["code-reviewer\nSpec compliance + quality"]
    D -->|"on failure"| D3["/debug\nRoot cause analysis"]
    D -->|"after all tasks"| D4["/quality-gate\nStructural + anti-pattern + design review"]
    D -->|"before claims"| D5["/verify-evidence\nEvidence-based verification"]

    %% Skills called by /debug
    D3 -->|"uses"| D5

    %% Skills called by /wrap-up-session
    F -->|"step 1"| F1["/learn\nPersist patterns to memory"]
    F -->|"step 4"| F2["code-reviewer\n4 parallel review agents"]
    F -->|"step 5.5"| D5
    F -->|"step 6.5"| F3["Worktree merge to main"]

    %% Standalone skills
    G["/checkpoint\nSnapshot for handoff"]
    H["/receive-review\nProcess review feedback"]
    I["/writing-skills\nAuthor new skills"]
    J["/sync\nPull from template repo"]
    K["/start-qa\nManual QA launch"]
    L["/folder-context-optimization\nCleanup unused files"]

    style A fill:#f9f,stroke:#333
    style D fill:#4CAF50,stroke:#333,color:#fff
    style F fill:#2196F3,stroke:#333,color:#fff
    style D5 fill:#FF9800,stroke:#333,color:#fff
```

**Core workflow** (top row): brainstorm → plan → build → security-scan → wrap-up-session

**Alternate entry**: `/system-design-planning` replaces brainstorm → plan when the change crosses a component boundary, changes a persisted data model, or changes an external contract

**Internal calls**: /build delegates to sub-agents for TDD, invokes code-reviewer for 2-stage review, /debug on failures, /quality-gate after all tasks, and /verify-evidence before any completion claims.

Project verification maps use a two-speed update path. `/build` and
`/wrap-up-session` invoke `/maintain-verification-skill --scope changed` before
E2E checks for user-facing session changes. Invoke
`/maintain-verification-skill` without that option for a full audit of every
mapped feature.

**Standalone skills** (bottom): Can be invoked independently at any time.

---

## Skills

Invoke with `/skill-name` in any session (Claude Code: `/jplugin:<name>`; bare `/<name>` also resolves while no other skill claims it). The table is generated from each skill's `SKILL.md` frontmatter by `python3 scripts/render-skills-table.py` — edit the `description` there, never a row; a blank *Harness* cell means every harness:

<!-- skills-table:begin -->
| Skill | What It Does | Harness |
|-------|-------------|---------|
| `/auto-push` | Semi-autonomous pipeline. User describes an idea; agent runs /plan and PAUSES for explicit approval. After approval, /build and /wrap-up-session run autonomously through commit and push. |  |
| `/brainstorm` | Explore a feature idea through divergent design thinking before committing to a spec. Use before /plan for non-trivial features requiring design decisions. |  |
| `/build` | Execute the task plan from tasks/todo.md autonomously using TDD with sub-agent delegation. Use in the session the build prompt starts. |  |
| `/checkpoint` | Snapshot current session progress to tasks/checkpoint.md for handoff or pause. |  |
| `/create-verification-skill` | Generate a project-local verification skill that drives the real app through its user surface. Use when a repository has no grounded way to prove UI, CLI, desktop, API, mobile, or library behavior. |  |
| `/debug` | Systematically investigate, diagnose, and fix bugs using root cause analysis. Use when debugging errors, test failures, runtime issues, or when the user reports a bug. Integrates with the typed learning store (tasks/solutions/). |  |
| `/eval` | Blinded A/B evaluation of a skill, prompt, or workflow change before promoting it. Candidates run in sanitized worktrees on organic prompts and never learn they are being measured; grading comes from session transcripts, not self-report. Two runnable modes: triggerability (does the harness route to this skill at all) and variant lift (does variant A beat variant B). Use before merging a skill edit, when a skill seems never to fire, or when deciding whether a rewrite actually helped. Triggers on: 'does this skill even fire', 'A/B this prompt', 'did the rewrite improve anything', 'evaluate my skills', 'run an eval'. |  |
| `/folder-context-optimization` | Sweep a folder to identify legacy/unused files, propose archival, and update docs. Use when a directory feels bloated or disorganized. |  |
| `/grill-me` | A relentless interview to sharpen a plan, decision, or idea, typed by the user and never started by the agent. Use when the user says 'grill me' about something. |  |
| `/grilling` | Interview the user relentlessly about a plan, decision, or idea until a shared understanding is reached, working the design tree in frontier rounds with a recommended answer on every question. Use when the user wants to stress-test their thinking, uses any 'grill' phrasing, or when another skill needs the decisions behind a piece of work settled before it acts. |  |
| `/html-presentation` | Generate a polished, self-contained HTML presentation (report or slide-deck) from structured content. Use when another skill or the user needs to publish a session review, design audit, project summary, or any narrative as a beautiful HTML document with strong visual and information-design quality. Triggers on: 'make an html presentation', 'generate a report', 'turn this into slides', or invocation by another skill (e.g. software-design-expert-learn). |  |
| `/learn` | Extract durable learnings from the current session and persist them as typed documents in tasks/solutions/. |  |
| `/maintain-verification-skill` | Reconcile a project verification skill after changed user behavior or run a full source-and-live feature audit. Use after user-facing changes or when auditing a verify-app feature map. |  |
| `/memory-maintain` | Sweep the typed learning store (tasks/solutions/) — resolve needs_review documents, merge duplicates, prune stale or contradicted entries. Invoked at every session start and wrap-up; self-gates on session count. |  |
| `/plan` | Interview user, write a feature spec, slice it into session-sized build steps, and end with a build prompt for a fresh session. Use for any non-trivial feature before coding. |  |
| `/prd` | Interview the user about a greenfield project, produce a structured PRD, ordered backlog, and agent context file. Use as the entry point for new projects. |  |
| `/quality-gate` | The post-build review gate: run when all tasks in tasks/todo.md are done, before wrap-up or commit. Three sequential phases — structural quality and reuse (simplify), AI anti-pattern cleanup (deslop), and APOSD design audit — emitting four-axis findings (severity, confidence, autofix_class, owner). Triggers on: 'review before I call it done', 'thorough review of what I just built', 'I finished the tasks, check the code', 'run the quality gate', 'post-build review'. |  |
| `/receive-review` | Process incoming code review feedback with technical rigor. Use when receiving review comments on PRs, from users, or from automated review tools. |  |
| `/refresh` | Context reset for a session running out of room: snapshot working state to disk, then continue the work in a fresh context rebuilt from that snapshot. Distinct from /checkpoint, which saves progress and stops — reach for /refresh when the work continues but the context must be recycled. Triggers on: 'this conversation is getting too long', 'you are losing track', 'start clean and keep going', 'context is full', 'reset and continue', or when /build's architectural circuit breaker trips. |  |
| `/security-scan` | OWASP-focused security audit scoped to the files changed in this session, worked through an explicit per-category checklist (input validation, authn/authz, secrets, crypto, dependencies, error handling). Use before committing or deploying changed code. Triggers on: 'security scan', 'check for vulnerabilities', 'any security issues in what I changed', 'is this safe to ship', 'OWASP audit'. |  |
| `/setup-deployment` | One-time interactive bootstrap for deployment verification. Scans the project for deployment signal files, asks the user to confirm detected services and project IDs, and writes the routing table into AGENTS.md below the managed block. | claude |
| `/slice` | Break a spec's acceptance criteria and implementation paths into session-sized slices — a Build Order table, a plan block in tasks/todo.md, and a build prompt — then, in a later session, file one task per slice through /task-registry. Use after a spec carries § Decisions and § Acceptance Criteria, or to refresh the Build Order and plan block after the spec changes. |  |
| `/software-design-expert-learn` | End-of-session code review and design tutorial based on 'A Philosophy of Software Design' by John Ousterhout. Use when the user wants to review all code written in the current session, understand design trade-offs, learn software design principles, or improve code review skills. Triggers on: 'review my code', 'explain the design', 'why did we do it this way', 'session review', 'code critique', 'design critique', or explicit /skill:software-design-expert-learn invocation. |  |
| `/software-design-expert-review` | Run a focused APOSD design review on recently changed files. Scans for the 10 red flags from 'A Philosophy of Software Design' plus Error Design (R11), emits four-axis findings (severity, confidence, autofix_class, owner), and produces a GO / HOLD / STOP verdict. Can be invoked manually or called by /build Phase 3.5. |  |
| `/start-qa` | Discover project config, restart app, and launch browser for manual QA testing. |  |
| `/sweep` | Producer routine engine — verify the codebase through one lens (janitor for bugs, architect for design) and file every proven finding as a registry task with a reproduction and a proposed fix. Use unattended from the janitor and architect routines, or by hand for a weekly audit. |  |
| `/sync` | Pull latest skills, hooks, agents, and config from the jplugin-agentic-development template repo. |  |
| `/system-design-planning` | Turn an issue or a feature idea into an upstream architecture review — system design, component contracts, data models, constraints, and a dependency-ordered build plan — rendered as a self-contained HTML document, then ends with a build prompt for a fresh session. Nothing is filed and nothing is built in this session; the reviewer approves by starting the build session with that prompt. Use instead of /brainstorm + /plan when the change crosses a component boundary, adds or changes a persisted data model, or introduces or changes an external contract. |  |
| `/task-registry` | Resolve one task against an external tracker (GitHub Issues) or a local Markdown store. Use when reading a task's full record, recording discovered work as a task, checking which tracker is configured, or selecting and claiming the next issue for a routine. |  |
| `/tidy` | Harness hygiene sweep for a jplugin-agentic-development repository — the template, its mirror, and any project that vendored the harness through /sync. Nine checks over the surfaces that duplicate by design (skills tables, retired skills, installed copies under ~/.claude and ~/.agents, backticked paths, worktrees, stray files, the task registers, the code graph). Mechanical drift is fixed and committed one concern per commit, machine-side remedies are printed as commands and never run, larger drift is filed through /task-registry. Use by hand after a retirement or rename, or from a scheduled routine; --report sweeps without writing anything. |  |
| `/verify-deployment` | Wait for post-push deployment builds to resolve, fetch logs on failure, and loop a code-debugger fix cycle up to 3 iterations before escalating. Service-agnostic — driven by runbook files in .claude/deployments/. | claude |
| `/verify-evidence` | Enforce evidence-based verification before any completion claims. Supports --scope deployment and --scope e2e. Use before committing, creating PRs, marking tasks done, or claiming success. |  |
| `/verify-task-registry` | Verify this repository's task-registry CLI through isolated local task creation, reading, and routine selection with retained PTY evidence. |  |
| `/visual-plan` | Turn an existing text spec into a rich, self-contained HTML visual plan — narrative, file map, architecture sketch, and open questions — for review before implementation. Use after /plan has already written specs/<feature>.md. |  |
| `/visual-recap` | Turn a completed branch's git diff into a self-contained HTML visual recap — narrative, file-tree, and annotated key changes. Use after implementation to produce a richer review artifact than a plain diff. |  |
| `/wrap-up-session` | Close session with code review, testing, fixes, and a clean commit. Use at the end of any coding session. |  |
| `/writing-skills` | Author new skills with proper structure, iron laws, and reference docs. Use when creating or improving skills for the workflow. |  |
| `/yolo` | Fully autonomous loop. User describes an idea; the agent runs /plan, /build, and /wrap-up-session in a Ralph-style loop until the backlog is empty or a circuit breaker trips. No user prompts between phases. |  |
<!-- skills-table:end -->

---

## Philosophy

This workflow is built on patterns that prevent common AI agent failure modes:

**Iron Laws** — Non-negotiable rules that the agent cannot rationalize away. Each critical skill has one:
- TDD: "No production code without a failing test first"
- Debug: "No fixes without root cause investigation first"
- Verify: "No completion claims without fresh verification evidence"

**Rationalization Tables** — Pre-addressed excuses. When the agent thinks "just this once" or "I'll test after", the skill already contains the rebuttal.

**Two-Stage Review** — Every task in `/build` passes through spec compliance review AND code quality review before proceeding.

**Evidence Over Claims** — The `/verify-evidence` skill bans phrases like "should work" or "looks correct". Only actual command output counts.

**Memory Across Sessions** — the typed learning store (`tasks/solutions/`) persists one document per learning with grep-first retrieval, so the agent doesn't repeat mistakes or bulk-load stale context. Old-format projects convert with the template repo's `scripts/migrate-learning-store.py`.

---

## Agents

Claude delegates to these automatically (or you can invoke them via the Agent tool):

| Agent | Best For |
|-------|---------|
| `planner` | Spec writing, task breakdown, architecture decisions |
| `backend-developer` | APIs, databases, auth, performance, security |
| `frontend-developer` | React/Vue/Angular components, responsive UI |
| `frontend-design-validator` | Verify UI matches design references |
| `code-reviewer` | Post-implementation quality review (invoked proactively) |
| `code-debugger` | Debugging failing tests and runtime errors |
| `security-reviewer` | OWASP checks, auth flows, injection vectors |
| `critic` | Adversarial quality gate for plans, code, specs |
| `context-document-optimizer` | Compress large docs for token efficiency |
| `software-design-expert-review` | Read-only APOSD design audit — depth, leakage, error design |

---

## Hooks

| Hook | Trigger | What It Does |
|------|---------|-------------|
| `session-start.sh` | Session start (the plugin's `hooks/hooks.json`) | Prints learning-store counts, active tasks and the git line, plus one warning line per problem: template drift, a missing managed block, a stale code graph |

---

## Directory Structure

```
.
├── install.sh                       ← Run once to set up global Claude config
├── AGENTS.md                        ← Core rules in the managed block; project rules below it
├── CLAUDE.md                        ← @AGENTS.md
├── project-template/                ← Scaffold copied into new projects
│   ├── AGENTS.md                    ← Project instructions seed (no block — /sync adds it)
│   ├── CLAUDE.md                    ← @AGENTS.md
│   └── tasks/
│       ├── todo.md
│       ├── history.md
│       ├── concepts.md
│       └── solutions/
├── .agents/
│   ├── hooks/                       ← lifecycle hook scripts (session-start, pre-compact, session-stop)
│   └── skills/                      ← canonical skills, each with SKILL.md + optional reference docs
├── hooks/
│   └── hooks.json                   ← registers SessionStart, PreCompact and Stop against .agents/hooks/
├── .claude-plugin/
│   ├── plugin.json                  ← the jplugin manifest (skills: ./.agents/skills)
│   └── marketplace.json             ← the marketplace entry Claude Code installs from
├── .claude/
│   ├── AGENTS.md                    ← Agent reference documentation
│   ├── settings.json                ← env + plugin declaration (no hooks — see hooks/hooks.json)
│   └── agents/                      ← 8 specialized subagents
├── tasks/
│   ├── todo.md                      ← Active task plan
│   ├── history.md                   ← Session narrative log
│   ├── concepts.md                  ← Concept glossary (project vocabulary)
│   └── solutions/                   ← Typed learning store (written via /learn)
└── specs/                           ← Feature specifications
```

---

## Known Issues

### Raw SessionStart JSON printed into the transcript (upstream — not fixable here)

The **claude-mem** plugin (marketplace `thedotmack`) registers more than one `SessionStart` hook. Their stdout lands on a single stream and gets concatenated, so Claude Code receives two JSON objects back to back:

```
{"continue":true,"suppressOutput":true,"status":"ready"}{"continue":true,"suppressOutput":true}
```

That is not a single valid JSON object, so it can't be parsed as a hook response — Claude Code prints it into the transcript as raw text instead of suppressing it.

Effect is cosmetic noise only. Nothing in this repo emits it, and no change here can suppress it; the fix belongs in claude-mem upstream. Don't go hunting for it in `.agents/hooks/`.

---

## Sources

- [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) — Command/agent/skill architecture
- [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) — Memory system, hook lifecycle, continuous learning
- [obra/superpowers](https://github.com/obra/superpowers) — Iron laws, verification patterns, brainstorming workflow, systematic debugging
- [cursor/plugins — pstack](https://github.com/cursor/plugins/tree/68836ddaf5697224520f1847d90cdb90ca8babaa/pstack) — Lauren Tan's MIT-licensed verification-skill creator, maintainer, feature-map pattern, and blinded eval playbook (adapted from revision `68836ddaf5697224520f1847d90cdb90ca8babaa`; see `THIRD_PARTY_NOTICES.md`)
- [mattpocock/skills](https://github.com/mattpocock/skills/tree/c55ee46073ed923f86ce59a5eb3b6d895095d1b7) — Matt Pocock's MIT-licensed `grilling` interview primitive, `grill-me` front door and domain-modeling discipline (adapted from revision `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`; see `THIRD_PARTY_NOTICES.md`)
