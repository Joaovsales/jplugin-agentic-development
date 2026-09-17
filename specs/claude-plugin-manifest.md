---
implementation_paths:
  - .claude-plugin/**
  - .claude/settings.json
  - .claude/hooks/auto-test-runner.sh
  - .claude/hooks/auto-test-runner.ps1
  - .claude/hooks/session-start.sh
  - .claude/deployments/README.md
  - .agents/skills/setup-deployment/**
  - .agents/skills/verify-deployment/**
  - .agents/skills/sync/SKILL.md
  - .agents/skills/sync/scripts/sync-retire.py
  - .agents/skills/tidy/SKILL.md
  - .agents/skills/writing-skills/SKILL.md
  - .agents/skills/create-verification-skill/SKILL.md
  - .agents/skills/maintain-verification-skill/SKILL.md
  - .agents/skills/verify/SKILL.md
  - .agents/skills/task-registry/scripts/registry/config.py
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/templates/task-tracking.md
  - .agents/agents/README.md
  - .agents/git-hooks/pre-push
  - .github/workflows/sync-template.yml
  - codex/hooks/session_start.py
  - scripts/install-codex.sh
  - scripts/render-codex.py
  - scripts/scaffold-project.sh
  - install.sh
  - CLAUDE.md
  - README.md
  - PI_SETUP.md
  - tests.md
  - tests/test-plugin-manifest.sh
  - tests/test-repo-identity.sh
  - tests/test-install-sh.sh
  - tests/test-codex-install.sh
  - tests/test-sync-retirement.sh
  - tests/test-syncable-paths.sh
  - tests/test-skill-references.sh
---

# Spec: Claude Code plugin manifest over the canonical skill tree

> Origin: prompt · Designed 2026-09-16 · Review status: **draft — critic pass: 12 findings, 12 applied, 0 declined · reviewer round 1: 2 findings applied (repo identity, legacy retirement)**
> Visual: specs/claude-plugin-manifest.plan.html

## Problem

Claude Code users of this workflow read skills from `.claude/skills/`, a
byte-identical copy of the canonical `.agents/skills/` tree that a convention,
an allowlist and `tests/test-skill-parity.sh` keep aligned; installed copies are
already drifting (`~/.claude/skills/` still carries `deslop`, `simplify`, `tdd`
and `verify-e2e`, which the repository no longer ships). This change ships the
repository as a Claude Code plugin named `jplugin` whose manifest points at
`.agents/skills/`, declares that plugin in the one settings file `/sync` already
delivers to every project, removes the template's `.claude/skills/` copy, adopts
the repository's current identity `jplugin-agentic-development` everywhere the
old name `coding-agent-workflow` still appears, and retires the compatibility
shims that only existed for the two-tree layout or for projects synced before
earlier renames. Out of scope: moving agents or hooks into the plugin, renaming
any skill, project-local skills a project writes into its own `.claude/skills/`
(`verify-<app>` and the like stay exactly as they are), and the Pi and Codex
install paths, which read `~/.agents/skills/` and do not change.

**Current state** — every path below was read this session.

```text
 .agents/skills/<name>/SKILL.md  (canonical, 33 skills)
        │
        ├─ cp ─► .claude/skills/<name>/SKILL.md   byte copy + README.md,
        │        setup-deployment, verify-deployment (tests/test-skill-parity.sh:16)
        │              │
        │              └─ Claude Code project scan   (.claude/skills only — docs; binary has no ".agents" path)
        │
        ├─ install.sh:107  cp .claude/skills/. ─► ~/.claude/skills/     (Claude Code, user scope)
        ├─ install.sh:123  cp .agents/*       ─► ~/.agents/            (Pi: PI_SETUP.md:18 skills=["~/.agents/skills"])
        └─ scripts/install-codex.sh:50        ─► ~/.agents/skills/     (Codex)

 /sync  ── Syncable Paths block (.agents/skills/sync/SKILL.md:99-108) lists BOTH trees + .claude/settings.json
        ── sync-retire.py:604 parses that block for roots; :533 tolerates ONE empty root, but an
           empty root is SKIPPED (:615 project_only over `scanned`; :624 history over `scanned`)
        ── .github/workflows/sync-template.yml:56 mirrors .claude/skills, never deletes
        ── session-start.sh:356 drift check diffs the same list
        ── tests/test-syncable-paths.sh:88-113 pins 7 copies of the list, one of them .claude/skills/sync/SKILL.md

 identity  ── GitHub repo is Joaovsales/jplugin-agentic-development (gh repo view); 87 occurrences of the
              old name remain in 17 tracked files; local `origin` still points at coding-agent-workflow.git
 legacy    ── retired skills in history: auto-improve, route, tdd, deslop, simplify, verify-e2e, aposd-guardrail
           ── .claude/hooks/auto-test-runner.{sh,ps1} header says DEPRECATED; README.md:345,369 list it as live
           ── sync SKILL.md:195-262 Steps 2.5 (.claude/commands/ migration) and 2.6 (CLAUDE.md Deployment Targets
              migration); session-start.sh:275 CLAUDE.md legacy fallback; deployments/README.md:151 legacy note
           ── install.sh:57-92 --prune-skills flag; tests.md root placeholder (README.md:376 only)
```

**Two pinning models exist today.** Claude Code is *project-pinned*: the
project's `.claude/skills/` shadows `~/.claude/skills/`. Pi and Codex are
*machine-pinned*: they read `~/.agents/skills/` and run project-relative scripts
from the project's `.agents/skills/`. This spec keeps Claude Code project-pinned
(see *Decisions*), which is what rules out a machine-level plugin as the only
delivery path.

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Pi and Codex keep working | `install.sh` step 3 and `scripts/install-codex.sh:50` still copy `.agents/skills/` to `~/.agents/skills/`; only the repository name changes in either | user | `tests/test-install-sh.sh`, `tests/test-codex-install.sh` |
| Every canonical skill loads on Claude Code | `claude plugin details jplugin@jplugin-agentic-development` lists exactly the set `basename(.agents/skills/*/)` | user | live proof in `tasks/e2e-log.md` (slice 1); static half in `tests/test-plugin-manifest.sh` |
| Bare `/name` prose routes to the namespaced skill | triggerability eval PASS for `/quality-gate`, `/verify`, `/task-registry` with **no** un-namespaced copy present | user | `/eval` transcript in `tasks/e2e-log.md`; slice 6 is gated on it |
| A fresh clone of a downstream project has skills on Claude Code | `.claude/settings.json` declares the marketplace and enables `jplugin@jplugin-agentic-development`; Claude Code offers the install on first open | user | live proof on a scratch clone (slice 1); `tests/test-plugin-manifest.sh` pins the settings keys |
| Claude Code stays project-pinned | the `extraKnownMarketplaces` source carries the template `ref` `/sync` checked out; scripts and prose come from the same ref | user | `tests/test-sync-retirement.sh` fixture asserts `/sync` writes the same ref to settings and to the checkout |
| Skill names stay harness-neutral | zero occurrences of the literal `jplugin:` under `.agents/skills/**`, `.claude/agents/**`, `AGENTS.md`, `PI_SETUP.md`; `CLAUDE.md` carries the mapping sentence exactly once | inferred | `tests/test-plugin-manifest.sh` |
| The old repository name is gone | zero occurrences of `coding-agent-workflow` or `Coding Agent Workflow` in tracked files outside `tasks/`, `specs/` and `.git/`; hook identifiers (`coding-agent-workflow-session-start` and siblings) are renamed with their consumers | user | `tests/test-repo-identity.sh` |
| `install.sh` never deletes an entry the template never carried | prune candidates are current template names ∪ names retired in template history (`git log --diff-filter=D` over both trees); anything else in `~/.claude/skills/` is untouched (lesson #52) | user | `tests/test-install-sh.sh` |
| Legacy copies are removed by default, with one confirmation | `install.sh` lists the candidates and asks `y/N` once; `N` or EOF deletes nothing; the `--prune-skills` flag no longer exists | user | `tests/test-install-sh.sh` |
| `/sync` never strands a Claude Code project | `sync-retire.py` retires a path under the retired root `.claude/skills/` only when the **project's** `.claude/settings.json` enables `jplugin@jplugin-agentic-development`; the check is a committed project fact, never a machine inference | inferred | `tests/test-sync-retirement.sh` |
| Project-local skills survive | a file under `.claude/skills/` that template history never carried is never a retirement candidate | user | `tests/test-sync-retirement.sh` (existing allowlist/history logic, now exercised on the retired root) |
| No retired skill is named as live | the seven history-retired names appear in no banner, table, delegation, hook or install list; `/tidy` `retired` check is green | user | `/tidy --report`; `tests/test-doc-conventions.sh` |
| Suite green after every slice | `bash tests/run.sh` exits 0 at the end of each slice | user | `bash tests/run.sh` |
| Minimum Claude Code version | 2.1.227 (the version the manifest is proven on); the skills path is written `./.agents/skills`, never `.`, which needed 2.1.221 | inferred | README prerequisite line; live proof |
| Rollback | template: `git revert`; machine: `claude plugin uninstall jplugin@jplugin-agentic-development` and `claude plugin marketplace remove jplugin-agentic-development`, then the previous `install.sh`; downstream: `/sync` against the previous template ref checks `.claude/skills/` back out and restores the previous `settings.json` | inferred | README § Keeping It Up to Date runbook step |

Consistency is per project, not per machine: within one project every clone
reads the same ref because `settings.json` is committed. Two projects may run
different refs, as they do today.

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `.agents/skills/` | every skill body, for every harness | — |
| `.claude-plugin/plugin.json` NEW | plugin identity (`name`, `version`) and the skills path | — |
| `.claude-plugin/marketplace.json` NEW | marketplace name and the one plugin entry (`source: "./"`) | plugin name |
| `.claude/settings.json` (template and every downstream) | which marketplace ref and which plugin a **project** uses | — |
| `install.sh` | template-developer registration: directory marketplace added, plugin installed at user scope, legacy `~/.claude/skills/` copies removed after one confirmation | `.agents/skills/` names, template history, `~/.claude/plugins/*.json` |
| `.agents/skills/sync/SKILL.md` § Syncable Paths | the list of roots `/sync` manages, including which one is retired | — |
| `sync-retire.py` | which downstream files are retired | Syncable Paths block, template history, the project's `.claude/settings.json` |
| `.github/workflows/sync-template.yml` | the CI mirror list | — |
| `.claude/hooks/session-start.sh` | the banner and the drift notice | Syncable Paths list (hand-pinned copy), the project's `.claude/settings.json` |
| `README.md` | the repository's name and install path as users see them | — |
| `tests/` | the pins above | all of the above |
| Claude Code (`~/.claude/plugins/`) | `known_marketplaces.json`, `installed_plugins.json`, `cache/` | manifest, marketplace, project settings |
| Pi, Codex | — | `~/.agents/skills/` (unchanged) |

### Interaction

```text
 developer            install.sh              claude CLI                 ~/.claude/plugins            Claude Code session
    │ (1) bash ───────►  │                        │                              │                            │
    │                    │ (2) marketplace add ──► │ ── known_marketplaces ─────► │  NEW (directory source)    │
    │                    │ (3) plugin install ───► │ ── installed_plugins ──────► │  NEW (installPath = checkout)
    │                    │ (4) list legacy ~/.claude/skills copies, ask y/N once, delete on y  │  NEW          │
    │                    │                        │                              │ ◄── (5) load manifest ──── │
    │                    │                        │                              │     scan ./.agents/skills   │  NEW
 teammate (fresh clone) Claude Code session       ~/.claude/plugins
    │ (6) open project ► │ reads .claude/settings.json: extraKnownMarketplaces + enabledPlugins    NEW
    │                    │ (7) offers marketplace install; on yes: github source @ ref ─► cache/  NEW
 downstream project     /sync                    sync-retire.py                 template ref
    │ (8) /sync ───────►  │ (9) checkout .agents/skills, settings.json (ref R) ◄─────────────────── │
    │                    │ (10) roots ◄─────────── │ ◄── Syncable Paths block ─── │
    │                    │                        │ (11) guard: project settings enable jplugin@?   NEW
    │                    │                        │ (12) retire .claude/skills/** under the RETIRED root (history match) ─► fs  NEW
 CI (sync-template.yml)  mirror list drops .claude/skills; PR body names the retirement               NEW
```

| Arrow | Mode | On timeout / failure | On duplicate |
|-------|------|----------------------|--------------|
| (2) | sync, local CLI | `claude` not on PATH → step prints NOTE and skips (same shape as the Pi step at `install.sh:186`) | marketplace name already known → `ok "already"`, no second add |
| (3) | sync, local CLI | CLI exit ≠ 0 → step fails loudly with the CLI's stderr, exit non-zero | plugin id already installed → `ok "already"` |
| (4) | sync, filesystem, one prompt | `N`, EOF or a non-interactive run → nothing deleted, list printed with the manual command | idempotent: a pruned entry is simply absent next run |
| (5) | at session start | manifest invalid → Claude Code skips the plugin; `tests/test-plugin-manifest.sh` is the pre-commit guard | one marketplace name → one plugin id |
| (6)–(7) | at session start | user declines → project has no `jplugin:` skills until they accept; `session-start.sh` prints one line naming the enabled-but-uninstalled plugin | already installed → nothing |
| (9) | sync, git | existing `/sync` failure handling | idempotent |
| (10) | sync, git | template unreadable → existing `RetireError` at `sync-retire.py:536-546` | n/a |
| (11) | sync, filesystem | settings unreadable JSON → refuse, naming the file; key absent → refuse, naming the `/sync` step that writes it | n/a |
| (12) | sync, filesystem | existing `PruneError` (`sync-retire.py:54`) | already deleted → filtered by `isfile` (`sync-retire.py:454`) |

Arrows (2) and (3) are two writes to `~/.claude/plugins/`; a crash between them
is recovered by idempotency on the next run, so no transaction is needed.

**Marketplace-name collision (spike question S3) — answered 2026-09-17.** A
developer machine holds the directory-source marketplace from `install.sh`; a
downstream project's `settings.json` declares a github-source marketplace under
the same name `jplugin-agentic-development`. The second registration **replaces**
the first, silently and at exit 0 (`tasks/e2e-log.md` § Spike S3). The planned
fallback — a second marketplace name for the directory source — is not
expressible: a plugin entry's relative source must lie under the marketplace
root and a directory marketplace's name is the manifest's name, so one
repository publishes exactly one marketplace name (S3 follow-up). Decision:
`install.sh` registers the checkout under the manifest's name and prints that
opening a project which declares the github source replaces that registration;
the installed record keeps its `installPath`, so skills keep loading from the
checkout until `claude plugin update`. In-place development uses
`claude --plugin-dir <checkout>`.

### Failure unit

- A broken manifest stops every `jplugin:` skill for Claude Code users, and nothing else; Pi and Codex do not read it.
- A refused retirement guard stops `/sync` Step 6 for that project, and nothing else; the checkout step has already landed and the project still has both `/name` and `/jplugin:name`.
- A failed `install.sh` step 3 leaves the machine on its previous state, because step 4 never runs after a failed or skipped install.
- A declined marketplace prompt on a fresh clone leaves that clone without `jplugin:` skills; the retired `.claude/skills/` is already gone from the repo, so the banner line in (6)–(7) is the only signal — it is loud on purpose.
- Removing the legacy migrations from `/sync` (Steps 2.5 and 2.6) stops nothing: a project that still carries `.claude/commands/` or a `## Deployment Targets` section in `CLAUDE.md` keeps them, and the tooling simply no longer looks there — `session-start.sh` reads `.claude/project.md` only.

## Component contracts

### `.claude-plugin/plugin.json` (Claude Code reads)

```json
{
  "name": "jplugin",
  "version": "1.0.0",
  "description": "Spec → plan → TDD build → review → wrap-up workflow skills for coding agents.",
  "author": { "name": "jplugin-agentic-development maintainers" },
  "repository": "https://github.com/Joaovsales/jplugin-agentic-development",
  "license": "MIT",
  "skills": "./.agents/skills"
}
```

| Aspect | Contract |
|--------|----------|
| Inputs | `skills` is a `./`-relative path to a directory of `<name>/SKILL.md`; `name` is the invocation namespace |
| Outcomes | Claude Code registers every `SKILL.md` under the path as `jplugin:<name>`; typed as `/jplugin:<name>` |
| Invariants | no `commands`, `agents` or `hooks` key (those stay project-level, see *Decisions*); `name` equals `plugins[0].name` in `marketplace.json`; `version` is semver |
| Idempotency | n/a — declarative |
| Versioning | `version` bumps on every skill release; a github-sourced install at a pinned `ref` ignores it, a directory-sourced marketplace loads in place |

### `.claude-plugin/marketplace.json` (Claude Code reads)

```json
{
  "name": "jplugin-agentic-development",
  "owner": { "name": "jplugin-agentic-development maintainers" },
  "plugins": [
    { "name": "jplugin", "source": "./", "description": "…" }
  ]
}
```

| Aspect | Contract |
|--------|----------|
| Inputs | `source: "./"` — the plugin is the marketplace root |
| Outcomes | added from a local directory: loads in place from that directory; added from GitHub at a `ref`: copied to `~/.claude/plugins/cache/` |
| Invariants | exactly one plugin entry; its `name` equals `plugin.json` `name` |
| Versioning | marketplace `name` is the install-id suffix (`jplugin@jplugin-agentic-development`) and never changes |

### `.claude/settings.json` — plugin declaration (synced to every project)

```json
{
  "extraKnownMarketplaces": {
    "jplugin-agentic-development": {
      "source": { "source": "github", "repo": "Joaovsales/jplugin-agentic-development", "ref": "<sha /sync checked out>" }
    }
  },
  "enabledPlugins": { "jplugin@jplugin-agentic-development": true }
}
```

| Aspect | Contract |
|--------|----------|
| Inputs | `ref` is the template commit `/sync` Step 5 checked out; in the template repo itself it is omitted (floating `HEAD`) |
| Outcomes | Claude Code offers the marketplace on first open of a clone and enables the plugin; `sync-retire.py` reads `enabledPlugins` as the guard |
| Invariants | the `hooks` and `env` blocks already in the file are untouched; `/sync` merges these two keys rather than overwriting the file (existing merge rule at `sync/SKILL.md:601`) |
| Idempotency | `/sync` rewrites `ref` to the checked-out sha on every run |
| Versioning | whether `ref` is honoured for github marketplace sources is spike question S4; fallback is no `ref` (floating), which weakens the project-pinning constraint to "pinned at install time" and is recorded in *Decisions* if it lands |

### `install.sh` — `install_claude_plugin`

```bash
install_claude_plugin REPO_DIR   # -> Installed | Already | Skipped(no claude CLI)
```

| Aspect | Contract |
|--------|----------|
| Inputs | the checkout directory (already `REPO_DIR`) |
| Outcomes | `Installed` (both CLI calls succeeded) · `Already` (marketplace known and plugin present) · `Skipped` (no `claude` on PATH, NOTE printed) |
| Raises | a CLI exit code other than 0 on `marketplace add` or `plugin install` aborts the step non-zero with the CLI output; never silently continues |
| Idempotency | re-run detects the marketplace by name in `claude plugin marketplace list` and the plugin by id in `installed_plugins.json` |
| Versioning | replaces step 2 (`install.sh:98-118`); steps 3–9 unchanged apart from the repository name |

### `install.sh` — `remove_legacy_skill_copies`

```bash
remove_legacy_skill_copies REPO_DIR CLAUDE_HOME   # -> Clean | Kept(n) | Removed(n)
```

| Aspect | Contract |
|--------|----------|
| Inputs | candidate = entry under `~/.claude/skills/` whose basename is a current template skill (`.agents/skills/<name>/`) **or** a name the template once shipped and deleted (`git log --diff-filter=D --name-only -- '.agents/skills/*/SKILL.md' '.claude/skills/*/SKILL.md'`, the computation `/tidy` already uses) |
| Outcomes | `Clean` (no candidates) · `Kept(n)` (list printed, prompt answered `N` or EOF, plus the one-line manual command) · `Removed(n)` (prompt answered `y`) |
| Raises | never deletes a non-candidate; never runs when `install_claude_plugin` returned `Skipped` or failed |
| Idempotency | yes |
| Versioning | replaces `extra_global_skills` / `prune_extra_skills` and the `--prune-skills` flag (`install.sh:17-92`); the old predicate ("not in the template") becomes the protected set; an unknown flag is still a usage error |

### `sync-retire.py` — retired roots and the project guard

```python
# Syncable Paths row:   .claude/skills/       → RETIRED — <reason>
def parse_syncable_roots(text, origin) -> Tuple[List[str], List[str]]:   # (live_roots, retired_roots)
def retired_root_candidates(repo, retired_roots, history) -> List[str]:
    """Tracked, on-disk project files under a retired root whose bytes match
    a path template history once carried. Files history never carried are
    project-local and are never returned."""
def missing_plugin_declaration(retire, repo) -> str:
    """The reason the retired-root copies stay — the project's .claude/settings.json
    does not enable 'jplugin@jplugin-agentic-development' — or "" when it does.
    Carried in the plan, never raised: Step 3 previews before Step 5 writes it."""
```

| Aspect | Contract |
|--------|----------|
| Inputs | the doc block (right-hand column beginning `RETIRED` marks a retired root); template history over the retired root; the project's `.claude/settings.json` |
| Outcomes | retired-root candidates join `retire` when the project enables the plugin · otherwise they stay out of the plan and the report carries one line naming `.claude/settings.json` and the `/sync` step that writes it, at exit 0 so the Step 3 preview survives (decided 2026-09-17, see *Decisions*) |
| Raises | `RetireError` when `.claude/settings.json` exists but is unreadable JSON |
| Idempotency | pure |
| Versioning | a retired root is **not** counted by `usable_roots` (`sync-retire.py:533`), so the one-empty-root budget is untouched; `SYNCABLE_ROOT_PATTERN` (`:50`) still validates the path shape |

### Syncable Paths block (`.agents/skills/sync/SKILL.md:99-108`)

| Aspect | Contract |
|--------|----------|
| Change | `.claude/skills/` row stays with the right-hand column `RETIRED — the jplugin plugin reads .agents/skills/; kept so /sync retires downstream copies`; `.claude/settings.json` row gains `+ plugin declaration` |
| Invariant | a `RETIRED` root is scanned for retirement only, never checked out; the two-column shape and trailing slash are unchanged so both existing parsers keep working |
| Copies | the six remaining hand copies (`SKILL.md` block, two `git diff` commands, `session-start.sh:356`, `CLAUDE.md` Key Directories, `README.md`) are re-pinned by `tests/test-syncable-paths.sh` with `SYNC_COPY` removed |

### `/sync` — Steps 2.5 and 2.6 removed

| Aspect | Contract |
|--------|----------|
| Change | `sync/SKILL.md:195-262` (the `.claude/commands/` migration and the `CLAUDE.md` Deployment Targets migration) are deleted; Step 2 flows into Step 3 |
| Consumers | `session-start.sh:275-285` drops the `CLAUDE.md` fallback and reads `.claude/project.md` only; `.claude/deployments/README.md:151` drops the legacy sentence; `verify/SKILL.md:65` drops "primary" |
| Invariant | no test or skill names `.claude/commands/` or `commands.legacy` afterwards |

### `.github/workflows/sync-template.yml`

| Aspect | Contract |
|--------|----------|
| Change | `mirror ".claude/skills"` (line 56) removed; header comment (lines 7–8) and PR body (line 81) name `.claude/skills/` as retired and point at `/sync` for the deletion, since the workflow never deletes by design; every `coding-agent-workflow` literal becomes `jplugin-agentic-development` |
| Invariant | `.claude/settings.json` stays in the mirror list, so CI-synced downstreams receive the plugin declaration |

### Repository identity (`README.md`, `install.sh`, hooks, tests)

| Aspect | Contract |
|--------|----------|
| Change | every `coding-agent-workflow` / `Coding Agent Workflow` literal in tracked files outside `tasks/` and `specs/` becomes `jplugin-agentic-development` / `jplugin for agentic development`; the install path becomes `~/jplugin-agentic-development`; hook ids `coding-agent-workflow-session-start`, `-session-end`, `-pre-compact` (`scripts/install-codex.sh`, `scripts/render-codex.py`, `codex/hooks/session_start.py`, `tests/test-codex-install.sh`) are renamed together with `install-codex.sh`'s idempotency check, so a re-run replaces the old entries rather than adding duplicates |
| Invariant | the git remote name `workflow` and the `WORKFLOW_BRANCH` variable are internal identifiers and stay; README gains the one-line `git remote set-url origin https://github.com/Joaovsales/jplugin-agentic-development.git` step for existing clones |
| Detected by | `tests/test-repo-identity.sh`: zero matches; `tests/test-codex-install.sh`: a second `install-codex.sh` run against a `hooks.json` holding the old ids leaves exactly one set of hooks |

### Deprecated hook and placeholder removed

| Aspect | Contract |
|--------|----------|
| Change | `.claude/hooks/auto-test-runner.sh` and `.ps1` (header: `DEPRECATED — no longer registered in settings.json`) are deleted with `README.md:345,369`; `tests.md` (root placeholder referenced only by `README.md:376`) is deleted with that line |
| Invariant | `install.sh` and `install-codex.sh` never copied either, so no machine step follows |

### `CLAUDE.md` — namespace sentence (shared by both harnesses)

One sentence under `## Skills — .agents/skills/`: *On Claude Code the skills are installed as the `jplugin` plugin, so a `/name` in this file is typed `/jplugin:name` and appears to the Skill tool as `jplugin:name`; Pi and Codex invoke `/name` directly.* Every other reference in the repository stays `/name`.

### Project-local skills (`create-verification-skill`, `maintain-verification-skill`, `verify`)

Unchanged in behaviour: a project's own Claude Code skill still lives in the
project's `.claude/skills/<name>/` (mirrored from `.agents/skills/<name>/` for
Pi), because Claude Code scans no other project directory. Their prose stops
calling `.claude/skills/` "the compatibility copy of the template" and calls it
"the project's Claude Code skill directory". `tests/test-skill-references.sh:15-19`
keeps forbidding executed `.claude/skills/` paths inside template skills, with
its premise reworded: the template ships nothing there. `.agents/agents/README.md:11`
stops calling `.claude/agents/` a "backwards-compat copy": it is the Claude Code
copy that carries model pins, and it stays.

## Data models

### Entity — project plugin declaration (`.claude/settings.json`)

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `extraKnownMarketplaces["jplugin-agentic-development"].source.ref` | git sha or absent | equals the template ref `/sync` checked out in the same run; absent only in the template repo | `tests/test-sync-retirement.sh` fixture; `tests/test-plugin-manifest.sh` (template has no `ref`) |
| `enabledPlugins["jplugin@jplugin-agentic-development"]` | `true` or absent | present in every synced project and in the template | `tests/test-plugin-manifest.sh` |

### Entity — Claude Code machine state (`install.sh` moves it)

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `skills_source` | enum `legacy-copy` · `both` · `plugin` | `plugin` iff `jplugin@jplugin-agentic-development` in `installed_plugins.json` and no template-named or template-retired entry in `~/.claude/skills/` | `install.sh` step 4 prints the derived state |
| `marketplace_source` | enum `directory` · `github` | `directory` after `install.sh`; `github` after accepting a project's declaration | `known_marketplaces.json`, read by `tests/test-install-sh.sh` fixture |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| retirement of `.claude/skills/**` committed in a project whose `settings.json` does not enable the plugin | `missing_plugin_declaration` keeps every retired-root path out of the plan; the report names the file and Step 5 |
| a retired-root file deleted that template history never carried (a project-local skill) | `retired_root_candidates` intersects with history by construction |
| `plugin` state with `install.sh` still copying to `~/.claude/skills/` | step 2 is deleted, not conditional |
| a never-carried `~/.claude/skills/` entry deleted by `install.sh` | the candidate predicate is current ∪ retired template names; the old "not in the template" set is exactly what is protected |
| a skill body valid only under one namespace | `tests/test-plugin-manifest.sh` fails on any `jplugin:` literal outside `CLAUDE.md` |
| the old repository name reappearing in a tracked file | `tests/test-repo-identity.sh` |
| two marketplaces named `jplugin-agentic-development` with different sources on one machine | the CLI keeps one per name and replaces silently (S3); `install.sh` says so in its output, and the installed record's `installPath` survives the replacement |

### Transitions — `skills_source`

| From | To | Trigger |
|------|----|---------|
| `legacy-copy` | `plugin` | `install.sh`, prompt answered `y` |
| `legacy-copy` | `both` | `install.sh`, prompt answered `N` or run non-interactively — list and manual command printed |
| `both` | `plugin` | a later `install.sh` answered `y`, or manual deletion |
| `legacy-copy` | `legacy-copy` | `install.sh` on a machine without `claude` on PATH (`Skipped`) — reported, nothing removed |
| `plugin` | `both` | never — no step writes `~/.claude/skills/` any more |

### Transitions — downstream `compat_copy` (`.claude/skills/` template files in a synced project)

| From | To | Trigger |
|------|----|---------|
| `present` | `absent` | `/sync` Step 6: settings.json enables the plugin **and** the file matches template history |
| `present` | `present` | guard refused — `/sync` prints the settings path and stops Step 6 |
| `present` | `present` | CI `sync-template.yml` run — it never deletes; its PR body says so |
| `absent` | `present` | never from the template; a project's own skill there is project-local and outside this table |

Units, zones and tenant scoping are n/a — no amounts, no timestamps, every entity is per-project or per-machine by construction.

### Migration and compatibility

Forward: slice 1 proves routing with the fallback removed before anything is
deleted; slice 2 renames the repository identity so every later slice pins the
new name; slice 5 lands the settings declaration and the retired-root logic
while the template still ships `.claude/skills/`, so a project that syncs
between slices 5 and 6 gains the declaration and retires nothing; slice 6
deletes the copy, and the next `/sync` retires the downstream files under the
guard; slice 7 removes the legacy shims, which no live path depends on. A
machine re-running `install.sh` from any commit in between is in `both` at
worst, never skill-less. Reverse: `git revert` restores `.claude/skills/`, the
old `settings.json` and the old name; `claude plugin uninstall` plus
`marketplace remove` clear the machine; a downstream `/sync` against the
previous ref checks `.claude/skills/` back out. Until a project's next `/sync`,
both `/plan` and `/jplugin:plan` resolve there — noisy, not broken.

## Build order

| # | Slice | Delivers | Depends on | Contract exposed | Size |
|---|-------|----------|------------|------------------|------|
| 1 | Spike: manifest, routing, declaration | `.claude-plugin/plugin.json`, `marketplace.json`, `tests/test-plugin-manifest.sh`; four live answers in `tasks/e2e-log.md`: **S1** all 33 skills load as `jplugin:<name>` in place via `claude --plugin-dir .`; **S2** `/eval` triggerability PASS for `/quality-gate`, `/verify`, `/task-registry` with `~/.claude/skills/` template copies removed and the project `.claude/skills/` temporarily moved aside; **S3** a directory-source and a github-source marketplace under one name: refused, replaced, or coexisting; **S4** a scratch clone whose `.claude/settings.json` declares the marketplace at a `ref` is offered the install and loads that ref | — | plugin + marketplace manifests | M |
| 2 | Repository identity | every old-name literal replaced; hook ids renamed with `install-codex.sh` idempotency; README remote step; `tests/test-repo-identity.sh` | 1 | identity contract | M |
| 3 | Canonical extras | `setup-deployment` and `verify-deployment` move to `.agents/skills/` with `harness: claude`; parity allowlist shrinks to `README.md`; `writing-skills` no longer instructs the copy | 1 | — | S |
| 4 | Installer | `install_claude_plugin`, `remove_legacy_skill_copies` (current ∪ retired names, one `y/N`); step 2 and `--prune-skills` removed; `/tidy` `installed` check reads `installed_plugins.json` and the legacy list | 2 | the two `install.sh` functions | M |
| 5 | Sync contract | `.claude/settings.json` plugin declaration in the template; Syncable Paths `RETIRED` row; `sync-retire.py` retired roots + project guard; `/sync` Step 5 writes `ref`; `sync-template.yml` mirror list and PR body; `session-start.sh` drift list and enabled-but-uninstalled line; `test-syncable-paths.sh` to six copies | 2 | `require_project_plugin`, settings declaration | L |
| 6 | Remove the copy | delete `.claude/skills/`, `tests/test-skill-parity.sh`; rewrite the 25 two-tree tests to loop over `.agents/skills/` only; `CLAUDE.md` Key Directories + namespace sentence; `README.md`, `.agents/agents/README.md`, `tasks/concepts.md`, `/tidy` inventory; `task-registry` `SKILL_ROOTS` comment and `templates/task-tracking.md:119`; project-local-skill prose in `create-verification-skill`, `maintain-verification-skill`, `verify`; `test-skill-references.sh` premise | 3, 4, 5; **S2 PASS** | — | L |
| 7 | Retire legacy shims | `/sync` Steps 2.5 and 2.6 deleted; `session-start.sh` `CLAUDE.md` fallback and deprecation hint deleted; `.claude/deployments/README.md:151` sentence; `verify/SKILL.md:65`; `auto-test-runner.sh`/`.ps1` and `tests.md` deleted with their README rows; `/tidy --report` shows the seven retired names nowhere as live | 6 | — | M |

### Slice criteria

- Slice 1: both manifests parse as JSON; `plugin.json.skills == "./.agents/skills"` and the directory exists; `plugin.json.name == marketplace.plugins[0].name == "jplugin"`; no `commands`/`agents`/`hooks` key; `tasks/e2e-log.md` has one entry each for S1–S4 with the command run, the transcript or output path, and PASS/FAIL; an S2 FAIL or an S4 FAIL stops the plan here and reopens *Decisions*.
- Slice 2: `grep -rIl 'coding-agent-workflow\|Coding Agent Workflow'` over tracked files outside `tasks/` and `specs/` is empty; `tests/test-codex-install.sh` fixture with a `hooks.json` carrying the three old hook ids ends with exactly three hooks, all new ids, after `install-codex.sh`; `README.md` contains the `git remote set-url` line; `bash tests/run.sh` green.
- Slice 3: `.agents/skills/setup-deployment/SKILL.md` and `.agents/skills/verify-deployment/SKILL.md` exist with `harness: claude`; `tests/test-skill-parity.sh` `ALLOWLIST` is `README.md`; `bash tests/run.sh` green.
- Slice 4: fixture run of `install.sh` with a stub `claude` on PATH records one `marketplace add <REPO_DIR>` and one `plugin install jplugin@jplugin-agentic-development --scope user`; a second run records neither and prints `already`; without `claude` on PATH prints the NOTE and touches nothing; `~/.claude/skills/aws-saml2aws-auth` survives a `y`; `~/.claude/skills/plan` (current) and `~/.claude/skills/tdd` (retired) are listed and deleted on `y`, kept on `N` and on EOF with the manual command printed; `install.sh --prune-skills` exits 1 with the usage text.
- Slice 5: `parse_syncable_roots` returns `.claude/skills/` in `retired_roots` and not in `live_roots`; a fixture whose `settings.json` lacks `enabledPlugins["jplugin@jplugin-agentic-development"]` and holds a history-known `.claude/skills/plan/SKILL.md` lists nothing under `.claude/skills/` and reports why, naming `.claude/settings.json` and `/sync` Step 5, at exit 0; with the key present the path is listed under `retire`; a project-local `.claude/skills/verify-myapp/SKILL.md` is listed under neither; the template's own `settings.json` has `enabledPlugins` and no `ref`; `sync-template.yml` contains no `mirror ".claude/skills"`; `test-syncable-paths.sh` passes with six copies and the `RETIRED` row present.
- Slice 6: `.claude/skills/` absent from the template tree; `grep -rl 'jplugin:' .agents/skills .claude/agents AGENTS.md PI_SETUP.md` is empty; `CLAUDE.md` contains the namespace sentence once; `git grep -l 'test-skill-parity'` is empty; `bash tests/run.sh` green.
- Slice 7: `git grep -l 'commands.legacy\|Step 2.5\|Step 2.6\|auto-test-runner'` is empty; `tests.md` absent; `session-start.sh` contains no `TARGETS_IN_CLAUDE`; `bash .agents/skills/tidy/...` — `/tidy --report` `retired` check lists zero live references for `auto-improve route tdd deslop simplify verify-e2e aposd-guardrail`; `bash tests/run.sh` green.

## Decisions

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| Plugin name (the typed prefix) — **closed by approval of this document** | `jplugin` / `jp` | `jplugin` — it is the repository's own name, so `/jplugin:plan` reads as "the jplugin plan skill"; the install id, the guard, the tests and every criterion hardcode it, so it cannot change after slice 4 | four extra characters per invocation outweigh the clarity; say `jp` in the review and the id is renamed before slice 1 |
| Marketplace name | `jplugin-agentic-development` / `jplugin` | `jplugin-agentic-development` — the GitHub slug, so `gh repo view`, the marketplace and the docs agree | the repo is renamed again |
| Pinning model for Claude Code — **OPEN, reopened 2026-09-17 by Spike S4 (FAIL)** | A) `ref` = a template **branch** (`master`) — floating; the install record pins `gitCommitSha` at install time and `/plugin update` moves it · B) `ref` = a template **tag** written by `/sync` Step 5 — requires the template to tag every release `/sync` may check out · C) no `ref` — same as A on the default branch · D) keep the sha — **not viable**: Claude Code clones with `git clone --branch <ref>`, so a sha is "Remote branch … not found" and the marketplace never registers | undecided — the marketplace is registered automatically from `settings.json` (headless too), the plugin install is **not** automatic and shows no prompt in 2.1.274 (one `claude plugin install <id> --scope project` per machine, surfaced by `/plugin` as `enabled in project settings but isn't installed`), and the install record carries `gitCommitSha` of the branch tip, never the `ref`; `/sync` Step 5 and `tests/test-sync-retirement.sh` currently write and assert the sha and must change with this row | the decision is A or C and a downstream project wants a reproducible skill set — then B is the only shape that pins prose and scripts to one template commit through the plugin |
| Home of the Claude-only extras | move to `.agents/skills/` with `harness: claude` / keep a two-skill `.claude/skills/` | move — one tree, one namespace; `harness:` has no consumer yet, so Pi and Codex installers copy them too (documented `TODO(shortcut)`: filter on `harness: claude` when a Pi user reports noise) | a Codex or Pi user invokes one and it fails on `.claude/project.md` — then the installer filter is due |
| Skill references in shared prose | keep `/name` + one mapping sentence in `CLAUDE.md` / rewrite to `/jplugin:name` | keep `/name` — Pi and Codex read the same files and have no namespace; S2 falsifies this before anything is deleted | S2 FAILs — then the alternatives are harness-specific wrapper commands (Addy Osmani's `.claude/commands/` pattern) or the rewrite, and this spec reopens |
| Agents and hooks | stay project-level (`.claude/agents/`, `settings.json`) / move into the plugin | stay — plugin agents are namespaced too and project agents override them, so every `subagent_type:` in every skill would have to change | all agent dispatches are rewritten to namespaced names in a later change |
| Legacy `~/.claude/skills/` copies | remove by default after one `y/N` / report only, prune behind a flag | remove by default — the reviewer asked for the old copies to go; the candidate predicate (current ∪ retired template names) is what keeps #52's lesson, not the flag | a machine's `~/.claude/skills/` holds a *renamed* fork of a template skill under a template name — it is a candidate, and `N` is the only protection |
| Retirement of downstream copies | explicit `RETIRED` root scanned against history / ship a sentinel file to keep the root non-empty / never retire | `RETIRED` root — the skipped-root behaviour at `sync-retire.py:615,624` makes an empty live root inert, and a sentinel contradicts "no longer exists" | a project needs `.claude/skills/` retired without adopting the plugin — that project edits its allowlist by hand |
| Missing plugin declaration at retirement | `RetireError` at exit 1 / plan state reported at exit 0 | plan state — decided 2026-09-17 at `/quality-gate`: `/sync` Step 3 previews retirement before Step 5 writes the declaration, so a refusal exited 1 on every downstream project's first sync and dropped the live-root list from the summary the user approves; the retired-root copies stay out of the plan either way, so nothing is deletable without the declaration |
| **OPEN — reopened 2026-09-17 by Spike S2 (FAIL)** — `/verify` after the copy is deleted | A) rename the skill (the bundled Claude Code skill `verify` wins a bare `/verify` once no un-namespaced copy exists; `bundled-skills/2.1.227` ships exactly that one name) · B) keep a project-level `.claude/skills/verify/` shim that forwards to `jplugin:verify` · C) accept the bundled `/verify` and reference `jplugin:verify` explicitly in every skill body | undecided — slice 6 stays gated; organic triggerability of verify is also weak with the copy present (control 1/2), so A or C should pair with a description rewrite measured by `/eval` |
| Legacy `/sync` migrations (Steps 2.5, 2.6) and the `CLAUDE.md` fallback | delete / keep | delete — they serve projects synced before two earlier renames; the reviewer owns every downstream project and asked for compatibility no longer needed to go | a downstream project still has `## Deployment Targets` in `CLAUDE.md`: its verification silently stops until the section is moved by hand — `/tidy` in that project reports it |
| Scope of the identity rename | prose and user-facing paths only / also internal identifiers (`workflow` remote, `WORKFLOW_BRANCH`) | prose, paths and hook ids; the remote name and variables stay — they name a role, not the repository | the remote name is ever shown to users as the repository's name |
| Lifetime of the `RETIRED` row — **open** | drop after one release / keep indefinitely | drop once every known downstream project has synced past slice 6; it costs nothing meanwhile because a retired root is outside the empty-root budget | never — a stale row is documentation of a deletion nobody can see |

## Acceptance Criteria

- Claude Code loads every skill under `.agents/skills/` as `jplugin:<name>` from the plugin manifest; the template's `.claude/skills/` no longer exists.
- Bare `/name` references in prose route to `jplugin:<name>` on Claude Code, proven by a triggerability eval with no un-namespaced copy present, before the copy is deleted.
- Every synced project's `.claude/settings.json` declares the marketplace at the template ref `/sync` checked out and enables `jplugin@jplugin-agentic-development`, so a fresh clone is offered the plugin on first open. *(S4, 2.1.274: the marketplace is registered on first open, the plugin install is one explicit `claude plugin install … --scope project`, and the `ref` must be a branch or tag — see § Decisions, pinning model.)*
- The old repository name appears in no tracked file outside `tasks/` and `specs/`; hook ids carry the new name and `install-codex.sh` replaces the old ids on re-run.
- `install.sh` registers the checkout as a directory marketplace and installs the plugin at user scope; it no longer copies skills to `~/.claude/skills/`; it lists current-or-retired template names there and deletes them after one `y`; it never deletes a name the template never carried; `--prune-skills` is gone.
- `install.sh` step 3 and `scripts/install-codex.sh` still deliver `~/.agents/skills/` unchanged, so Pi and Codex behave as before.
- `/sync` retires template files under the retired root `.claude/skills/` only when the project's own `settings.json` enables the plugin and the file matches template history; project-local skills there are never touched; the CI mirror stops mirroring the root and says so.
- `/sync` Steps 2.5 and 2.6, the `CLAUDE.md` Deployment Targets fallback, the deprecated `auto-test-runner` hook and the `tests.md` placeholder are deleted with every reference to them.
- No skill body or harness-neutral document hardcodes the `jplugin:` namespace; `CLAUDE.md` states the mapping once.
- `tests/test-plugin-manifest.sh` and `tests/test-repo-identity.sh` pin the new invariants; `tests/test-skill-parity.sh` is retired; `bash tests/run.sh` is green after every slice.
- `tasks/e2e-log.md` records the four spike answers S1–S4.

## Implementation Paths

- `.claude-plugin/**` — plugin and marketplace manifests
- `.claude/settings.json` — marketplace and plugin declaration (template copy, no `ref`)
- `.claude/hooks/auto-test-runner.sh`, `.claude/hooks/auto-test-runner.ps1`, `tests.md` — deleted
- `.claude/hooks/session-start.sh` — drift list, enabled-but-uninstalled line, `CLAUDE.md` fallback removed, banner name
- `.claude/deployments/README.md` — legacy location sentence removed
- `.agents/skills/setup-deployment/**`, `.agents/skills/verify-deployment/**` — Claude-only skills moved into the canonical tree
- `.agents/skills/sync/SKILL.md`, `.agents/skills/sync/scripts/sync-retire.py` — `RETIRED` row, retired-root candidates, project guard, `ref` write in Step 5, Steps 2.5 and 2.6 removed, repository name
- `.agents/skills/tidy/SKILL.md`, `.agents/skills/writing-skills/SKILL.md` — inventory, installed check and authoring instructions for the one-tree layout; `--prune-skills` references removed
- `.agents/skills/create-verification-skill/SKILL.md`, `.agents/skills/maintain-verification-skill/SKILL.md`, `.agents/skills/verify/SKILL.md` — project-local skill wording; "primary" removed
- `.agents/skills/task-registry/scripts/registry/config.py`, `.agents/skills/task-registry/scripts/task-registry.py`, `.agents/skills/task-registry/templates/task-tracking.md` — `SKILL_ROOTS` comment and prose that cite the parity test
- `.agents/agents/README.md` — "backwards-compat copy" wording
- `.agents/git-hooks/pre-push`, `scripts/scaffold-project.sh`, `scripts/install-codex.sh`, `scripts/render-codex.py`, `codex/hooks/session_start.py`, `PI_SETUP.md` — repository name and hook ids
- `.github/workflows/sync-template.yml` — mirror list, PR body, repository name
- `install.sh` — plugin registration, legacy-copy removal, `--prune-skills` removed, repository name
- `CLAUDE.md`, `README.md` — Key Directories, namespace sentence, install instructions, remote step, rollback runbook, hooks table, directory tree
- `tests/test-plugin-manifest.sh` — manifest and settings invariants, the no-`jplugin:` guard
- `tests/test-repo-identity.sh` — zero old-name literals
- `tests/test-install-sh.sh`, `tests/test-codex-install.sh`, `tests/test-sync-retirement.sh`, `tests/test-syncable-paths.sh`, `tests/test-skill-references.sh` — the changed contracts
