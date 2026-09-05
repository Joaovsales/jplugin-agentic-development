---
name: sync
description: Pull latest skills, hooks, agents, and config from the coding-agent-workflow template repo.
harness: universal
---

# /sync — Sync Workflow Updates from Template Repo

Pull the latest skills, hooks, agents, and config from the `coding-agent-workflow` template repo into the current project.

## Layered Configuration Model

Config is split across layers so `/sync` can overwrite template-managed files safely without touching project-specific content.

### Shared layer (both Claude Code and Pi read this natively)

| Path | Scope | Committed? | Touched by /sync? |
|---|---|---|---|
| `CLAUDE.md` | All shared rules inline: workflow, principles, skills index | Yes | **Yes — overwritten wholesale** |
| `.agents/skills/` | Canonical skills — readable by any harness | Yes | **Yes** |
| `.agents/agents/` | Canonical sub-agent personas (model-agnostic) | Yes | **Yes** |

Both Claude Code and Pi read `CLAUDE.md` natively at session start. All shared workflow rules and coding principles live there inline — no `@` import required for shared content.

### Claude Code additional layer

| File | Scope | Committed? | Touched by /sync? |
|---|---|---|---|
| `.claude/project.md` | Team-shared, project-specific rules + Deployment Targets | Yes | **Never** |
| `CLAUDE.local.md` | Personal per-project overrides | No (gitignored) | **Never** |
| `~/.claude/CLAUDE.md` | Cross-project personal | N/A (global) | **Never** |

`CLAUDE.md` uses Claude Code's native `@` import syntax to pull in `.claude/project.md` and `CLAUDE.local.md`. This layering exists so `/sync` can overwrite `CLAUDE.md` without touching project-specific content.

### Pi additional layer

| File | Scope | Committed? | Touched by /sync? |
|---|---|---|---|
| `AGENTS.md` | Team-shared, project-specific rules for Pi | Yes | **Never** |
| `~/.pi/agent/AGENTS.md` | Cross-project personal | N/A (global) | **Never** |

Pi reads `CLAUDE.md` (shared rules) + `AGENTS.md` (project-specific additions). `AGENTS.md` is Pi's equivalent of `.claude/project.md`.

## Source Repo

- **GitHub**: `Joaovsales/coding-agent-workflow`
- **Remote name convention**: `workflow`

## Automatic Drift Notification

The `session-start.sh` hook checks the `workflow` remote once per 24h and prints a
one-line `🔄 TEMPLATE DRIFT` notice at session start when syncable paths differ
from `workflow/<default-branch>`. It does **not** modify files — it only nudges
you to run `/sync`.

**Where the hook is registered:** `install.sh` registers `SessionStart` at the **user**
level only (`~/.claude/hooks/session-start.sh` + `~/.claude/settings.json`) — once per
machine, covering every project. It is deliberately **not** registered in the
project-level `.claude/settings.json` that `/sync` copies. Registering it in both places
makes the hook fire twice per session and print the banner twice. Do not "helpfully" add
a `SessionStart` entry to `.claude/settings.json` — syncing that file does not, and must
not, install this hook.

**Enable on a fresh project:**

```bash
git remote add workflow https://github.com/Joaovsales/coding-agent-workflow.git
```

Once the remote exists, the hook takes over automatically. Fetch is capped at a
5-second timeout (offline sessions stay silent). Cache lives at
`.claude/.sync-check-cache` (gitignored).

**Silence the notification:**

```bash
touch .claude/sync-check-dismissed
```

**Force a re-check now** (bypass the 24h cache):

```bash
rm .claude/.sync-check-cache
```

## Syncable Paths

These are the files/directories managed by the workflow template.

> **This block is machine-parsed** — by `scripts/sync-retire.py`, which reads it
> for the roots it scans, and by `tests/test-syncable-paths.sh`, which pins the
> other six copies of this list against it. Both parsers split each line on the
> arrow glyph, so keep the two-column shape, and keep the trailing slash on
> every directory: an entry without one is read as a file and excluded from
> retirement. Do not use that glyph in prose anywhere between this heading and
> the next one — the parsers are fence-unaware and would read the line as a root.

```
CLAUDE.md             → Shared rules: workflow, principles, skills index (both harnesses)
.agents/skills/       → Canonical skills (harness-neutral)
.agents/agents/       → Canonical sub-agent personas (harness-neutral, discovered by pi-subagents)
.claude/skills/       → Claude Code backwards-compat copy of .agents/skills/
.claude/agents/       → Subagent definitions (Claude Code only)
.claude/hooks/        → Lifecycle hooks (Claude Code only)
.claude/browsers/     → Browser adapter runbooks read by /verify --scope e2e
.claude/settings.json → Hook configuration + env (Claude Code only — no SessionStart, see above)
.agents/git-hooks/    → Git hooks (harness-agnostic; installed separately, see below)
```

**`.agents/git-hooks/pre-push` needs an install step, not just a sync.** Syncing
updates the file in the tree; git runs the copy under `--git-common-dir/hooks/`.
`install.sh` writes the git *template* dir, which applies only to repositories
created afterwards — so an already-cloned project keeps running whatever hook it
had, or none. Refresh it explicitly after every sync:

```bash
cp .agents/git-hooks/pre-push "$(git rev-parse --git-common-dir)/hooks/pre-push"
chmod +x "$(git rev-parse --git-common-dir)/hooks/pre-push"
```

Idempotent, and one copy covers every worktree since they share the common dir.
Skipping it is how a gate ends up present in the tree and wired nowhere.

**Never sync** (project-specific state):
- `AGENTS.md` — Pi project-specific rules (Pi's equivalent of .claude/project.md)
- `.claude/project.md` — Claude Code project-specific rules, Deployment Targets, team conventions
- `tasks/solutions/` and `tasks/history.md` — project-specific learnings and session log
- `CLAUDE.local.md` — personal per-project overrides (gitignored)
- `tasks/` — project-specific task state
- `specs/` — project-specific feature specs
- `.claude/sync-keep` — the project's retirement allowlist (see Step 6.4). It
  needs no exclusion mechanism, and the reason is structural rather than a list
  to keep in step: every syncable root under `.claude/` is a *subdirectory*,
  while `sync-keep` is a file directly under `.claude/`, so it lies outside all
  of them by shape. Listed here anyway, because this is where people look.

## Procedure

### Step 1 — Detect Connection Method

Check if the `workflow` remote already exists:

```bash
git remote get-url workflow 2>/dev/null
```

- **If remote exists**: proceed to Step 2.
- **If no remote**: ask the user which connection method to use:

| Option | Action |
|--------|--------|
| **Add git remote** | `git remote add workflow https://github.com/Joaovsales/coding-agent-workflow.git` |
| **Manual diff** | Skip git, do a file-by-file comparison using a local clone in `/tmp` |

If user chooses manual diff, clone to a **fresh private directory** and remember it:

```bash
WORKFLOW_CLONE="$(mktemp -d)"
git clone --filter=blob:none https://github.com/Joaovsales/coding-agent-workflow.git "$WORKFLOW_CLONE"
```

`--filter=blob:none`, not `--depth 1`: Step 6.4 asks the template what it *used
to* carry, and a shallow clone's history is just its current state — under which
every retired skill looks project-specific and is kept forever. The filter keeps
the clone cheap (commits and trees only; file contents are fetched on demand)
while leaving that question answerable.

Do not reuse a fixed path such as `/tmp/coding-agent-workflow`, and do not trust
one that already exists. Step 6.4 points a **file-deleting** tool at this
directory and reads the syncable-root list out of it, so anything that can
pre-create that path chooses what gets deleted.

### Step 2 — Detect Remote Default Branch & Fetch Latest

First, detect the remote's default branch (handles repos using `master` or `main`):

```bash
# Detect the remote HEAD branch
WORKFLOW_BRANCH=$(git ls-remote --symref workflow HEAD 2>/dev/null \
  | grep '^ref:' \
  | sed 's|^ref: refs/heads/||' \
  | awk '{print $1}')

# Fall back to 'main' if detection fails
WORKFLOW_BRANCH=${WORKFLOW_BRANCH:-main}

echo "Remote default branch: $WORKFLOW_BRANCH"
git fetch workflow "$WORKFLOW_BRANCH"
```

Store the detected branch name — use `workflow/$WORKFLOW_BRANCH` in all subsequent steps (Steps 3, 4, 5) instead of the hardcoded `workflow/main`.

If using manual diff mode, use the `"$WORKFLOW_CLONE"` checkout from Step 1 as the source.

### Step 2.5 — Legacy Directory Migration

Older versions of this workflow shipped slash commands under `.claude/commands/`. The current layout uses `.claude/skills/`. Projects synced before the rename retain a stale `.claude/commands/` directory whose entries can shadow or contradict the canonical skills.

Detect and resolve before showing diffs:

1. Check whether `.claude/commands/` exists in the target project (`ls .claude/commands/ 2>/dev/null`)
2. **If absent:** silent no-op — do not log anything, proceed to Step 3.
3. **If present:** list its entries, then check for **overlapping basenames** with `.claude/skills/`:
   - Build the set `commands_basenames = basename(file) without extension for file in .claude/commands/`
   - Build the set `skills_basenames = basename(dir) for dir in .claude/skills/`
   - Compute the intersection
4. **If overlapping basenames exist:** surface the conflict list and refuse to auto-resolve:
   ```
   ⛔ Conflict: the following entries exist in BOTH .claude/commands/ and .claude/skills/:
     - <basename1>
     - <basename2>
   These would shadow each other at runtime. Resolve manually before re-running /sync:
     - Decide which version is authoritative (usually the skills/ version)
     - Delete the obsolete copy
     - Re-run /sync
   ```
   Do NOT prompt for archive/delete in this case — the user must intervene.
5. **If no overlapping basenames:** prompt the user with three options:
   ```
   Legacy directory .claude/commands/ found with N entries.
   The current workflow uses .claude/skills/ exclusively.
   How should we handle the legacy directory?
     [archive]  Rename to .claude/commands.legacy/ (preserves contents)
     [delete]   Remove .claude/commands/ entirely
     [skip]     Leave it in place for now (re-prompted next /sync)
   Choose: archive / delete / skip
   ```
6. Apply the user's choice:
   - `archive`: `mv .claude/commands .claude/commands.legacy`
   - `delete`: `rm -rf .claude/commands` (confirm once more before running)
   - `skip`: log "Legacy migration skipped — will re-prompt next /sync" and proceed

### Step 2.6 — Legacy CLAUDE.md Migration

Earlier versions of this workflow wrote the `## Deployment Targets` routing table directly into `CLAUDE.md`. The current layout keeps project-specific content in `.claude/project.md` so `/sync` can overwrite `CLAUDE.md` safely.

Before showing the diff, detect and offer to auto-migrate:

1. **Detect** with the exact-match regex:
   ```bash
   grep -qE '^## Deployment Targets[[:space:]]*$' CLAUDE.md 2>/dev/null
   ```
2. **If absent**: silent no-op — do not log anything, proceed to Step 3.
3. **If present in `CLAUDE.md` AND also present in `.claude/project.md`**: ambiguous state. Refuse to auto-migrate:
   ```
   ⛔ Conflict: ## Deployment Targets exists in BOTH CLAUDE.md AND .claude/project.md.
   Manually consolidate before re-running /sync:
     - Decide which section is authoritative
     - Delete the other
     - Re-run /sync
   ```
   Do NOT prompt — user must intervene.
4. **If present only in `CLAUDE.md`**: prompt with default-no:
   ```
   Legacy Deployment Targets section found in CLAUDE.md.
   The current layout keeps this section in .claude/project.md so /sync can
   overwrite CLAUDE.md safely without wiping your deployment config.

   Migrate now? [y/N]:
   ```
5. **On `y`** — apply the migration:
   a. Extract the block from the `^## Deployment Targets[[:space:]]*$` heading through the end of the `**Config:**` bullet list (or end-of-file / next `^## ` heading, whichever comes first)
   b. If `.claude/project.md` does not exist, create it from this stub:
      ```markdown
      # Project-Specific Configuration

      > Imported by CLAUDE.md. Safe to edit — /sync never touches this file.
      ```
   c. Append the extracted block to `.claude/project.md` (separated by a blank line from any existing content)
   d. Remove the same block from `CLAUDE.md`
   e. Ensure `.gitignore` contains `CLAUDE.local.md`; add it if missing with a comment header
   f. Stage all three files (`CLAUDE.md`, `.claude/project.md`, `.gitignore`) for the user to review
   g. Log: `✓ Migrated Deployment Targets from CLAUDE.md → .claude/project.md`
6. **On `n` (or default)** — **abort the entire sync**:
   ```
   Sync aborted — CLAUDE.md cannot be safely overwritten while Deployment Targets
   still lives in it. Re-run /sync and choose 'y' to migrate, or manually move the
   section to .claude/project.md.
   ```
   Do NOT partially apply. The whole sync stops here.

**Idempotency**: running `/sync` a second time after a successful migration finds no matching section in `CLAUDE.md`, takes the silent no-op path in step 2, and proceeds normally. Re-runs are safe.

### Step 3 — Show What Changed

Compare the syncable paths between the current project and the template source.

**If git remote mode:**
```bash
# Show changed files in syncable paths only
# Note: use two-dot diff (not three-dot) — template and project have unrelated histories,
# so HEAD...workflow/$WORKFLOW_BRANCH fails with "no merge base"
git diff workflow/$WORKFLOW_BRANCH --stat -- .agents/skills/ .agents/agents/ .agents/git-hooks/ .claude/skills/ .claude/agents/ .claude/hooks/ .claude/browsers/ .claude/settings.json CLAUDE.md
```

Then show the full diff:
```bash
git diff workflow/$WORKFLOW_BRANCH -- .agents/skills/ .agents/agents/ .agents/git-hooks/ .claude/skills/ .claude/agents/ .claude/hooks/ .claude/browsers/ .claude/settings.json CLAUDE.md
```

**If manual diff mode:**
For each syncable path, compare using `diff -rq` between the project and `"$WORKFLOW_CLONE"`.

**Retirement preview (both modes):** the diff above covers additions and
modifications. Deletions come from the retirement pass, which is a dry run here
so its output is part of the summary the user approves — nothing is written
until Step 6.4:

```bash
set -o pipefail
git show "workflow/$WORKFLOW_BRANCH:.agents/skills/sync/scripts/sync-retire.py" \
  | python3 - --from-ref "workflow/$WORKFLOW_BRANCH"
```

In manual-diff mode run
`python3 "$WORKFLOW_CLONE/.agents/skills/sync/scripts/sync-retire.py"` with
`--from-dir "$WORKFLOW_CLONE"` instead. Show every line it prints; the retire
list is never abbreviated.

**Set the variables in the same command that uses them.** `$WORKFLOW_BRANCH` and
`$WORKFLOW_CLONE` are assigned in Step 1, and shell state does not survive
between separate tool calls — so re-derive or re-state them here rather than
assuming they are still set. `set -o pipefail` is not decoration either: without
it a failed `git show` feeds `python3 -` an empty program, which exits **0**
having printed nothing, and the retirement gate silently does not run. The
script rejects an empty `--from-dir` with exit 2 for the same reason.

**Both forms run the template's copy of the script, never the project's.** The
project may not have one: Step 5 is what checks `.agents/skills/` out, so on the
sync that first delivers this script the project's path does not exist yet —
which is every downstream project's first sync. Reading it from the template
also settles the version question Step 6.4 raises, since the preview and the
deletion then come from the same revision.

### Step 4 — Present Changes to User

Summarize the changes in a clear table:

```
| File                          | Status   | Summary                    |
|-------------------------------|----------|----------------------------|
| .claude/skills/sync/SKILL.md  | NEW      | New sync skill              |
| .claude/agents/planner.md     | MODIFIED | Updated planning prompts    |
| CLAUDE.md                     | MODIFIED | Added new workflow section  |
```

Then ask the user:

> **What would you like to sync?**
> 1. **All changes** — apply everything
> 2. **Pick files** — choose specific files to sync
> 3. **Preview only** — just show the diffs, don't apply anything
> 4. **Abort** — cancel sync

Retirement is **not** part of this menu. It applies in full for both *all
changes* and *pick files*, and not at all for *preview only* or *abort*. The
retirement set is defined by `.claude/sync-keep`, not by picking — a user who
wants to keep a path adds it to `sync-keep`, which is the entire point of the
mechanism.

### Step 5 — Apply Changes

**If git remote mode (recommended for "all changes"):**
```bash
git checkout workflow/$WORKFLOW_BRANCH -- <selected-files>
```

**If manual diff mode or selective sync:**
Copy files from the source to the project, overwriting existing files.

For each applied file, briefly note what changed.

### Step 6 — Post-Sync

1. Run `git diff --stat` to confirm what was updated
2. Ask the user if they want to commit the sync:
   - Suggested message: `chore: sync workflow updates from coding-agent-workflow`
3. Remind the user to review `CLAUDE.md` if it was updated — they may need to merge project-specific customizations back in

### Step 6.4 — Retired Path Removal

A sync copies files in; it never deletes. A project that installed a skill the
template has since retired keeps running the stale copy indefinitely, and the
retired copy still carries whatever rule got it retired. `tdd` is the live
example: it offered committing with a `/learn` run as a sanctioned substitute
for `/wrap-up-session` — the only written authorization in the workflow to commit
code without wrapping up,
which is exactly what the pre-push wrap-up gate exists to catch.

Which paths are retired is **recorded, not judged**. A path that exists in the
project but not in the template is either retired upstream or project-specific;
nothing in either repository used to answer which, so the answer was re-derived
on every run and two syncs from one template commit could produce different
trees. The project now owns `.claude/sync-keep` — newline-delimited glob
patterns naming the paths under syncable roots that belong to it — and the
retirement set is set arithmetic over that file:

    retire = project paths under syncable roots
           - template paths under the same roots
           - paths matching a sync-keep pattern

Apply it. This is the same command Step 3 already ran as a dry run, plus
`--apply`:

```bash
set -o pipefail
git show "workflow/$WORKFLOW_BRANCH:.agents/skills/sync/scripts/sync-retire.py" \
  | python3 - --from-ref "workflow/$WORKFLOW_BRANCH" --apply
```

In manual-diff mode run
`python3 "$WORKFLOW_CLONE/.agents/skills/sync/scripts/sync-retire.py"` with
`--from-dir "$WORKFLOW_CLONE"`; the two modes produce the same retirement set
for the same template content. The `set -o pipefail` and same-command variable
rules from Step 3 apply here unchanged — more so, because this run deletes. Report every line the script prints — the retire list is the
record of what was destroyed, so it is never abbreviated.

**Re-read the list here, do not rely on the Step 3 preview.** The tree changed
underneath it: Step 5 checked out `.agents/skills/`, so paths that were retire
candidates at Step 3 may no longer be. The list printed here is the
authoritative one, and it is printed before anything is deleted. Running the
template's copy in both steps — rather than the project's, which Step 5
overwrites midway — is what keeps the two runs the same version of the script.

**Pattern syntax.** Each non-blank, non-`#` line in `.claude/sync-keep` is one
glob, matched against the whole path, case-sensitively:

```
*   any run of characters except /       .claude/hooks/*.sh
?   exactly one character except /       .claude/hooks/ru?.sh
**  any run of characters including /    .agents/skills/sync/**
```

Those three tokens are the whole language. Character classes, brace expansion
and negation are rejected, as are absolute paths, `..`, and backslashes. A
pattern must name a path under a syncable root.

A trailing `/` is refused: a directory name matches no file and would protect
nothing, so write the `**` form above rather than `.agents/skills/sync/`. A
pattern that matches nothing in a given run is reported as `unmatched:` — not an
error, but usually a stale entry that has stopped protecting what it names.

**Project-local content under a syncable root belongs in `sync-keep`.** Other
skills write there — `/create-verification-skill` generates a `verify-<app>`
skill into `.agents/skills/` and mirrors it into `.claude/skills/` — and nothing
registers those paths automatically. Once a project has promoted its candidate,
anything generated afterwards is a retire candidate on the next sync. It is
always reported before deletion, so nothing is lost silently, but the operator
is the only thing standing between a generated skill and removal. When this run
reports a retire path the project deliberately created, add it to
`.claude/sync-keep` rather than re-creating it after every sync.

**A non-zero exit means one of three different things.** They need different
responses, so read the message rather than the code:

| Exit | Meaning | Response |
|------|---------|----------|
| `2` | usage — no source, both sources, or an empty one | fix the invocation; nothing was read |
| `1` + `sync-keep line N:` | the allowlist has an unusable pattern | fix that line; nothing was deleted |
| `1` + `candidate already exists` | a previous bootstrap run left `.claude/sync-keep.candidate` | review and promote it, or delete it; nothing was deleted |
| `1` + `refusing to retire a root` | the template source is wrong, or a declared root is genuinely empty upstream | check the ref before anything else |
| `1` + `FAILED:`/`UNPRUNED:` | deletion ran and part of it did not land | the `deleted:` lines are the record; re-run after fixing permissions |

Only the last one has deleted anything. **Do not treat a non-zero exit as
permission to skip the step** — retirement not running is the state this feature
exists to end.

**A project with no `.claude/sync-keep` is in bootstrap.** It still loses what
the template retired: a file byte-identical to something the template once
shipped at that path was template content, not this project's, and the
template's git history is the record that says so — no hand-maintained list of
retired names, and no model asked to classify. Those are reported as
`retire: <path> (was template content, retired upstream)` and deleted under
`--apply`.

Provenance is per **content**, not per path and not per skill name. Three cases
that look retirable and are not:

- a synced file this project **edited** afterwards — the edit makes it the
  project's, and the edit may not even be committed yet
- a file this project **wrote itself** at a path the template happens to have
  used once (`.claude/hooks/pre-commit.sh` is a name both reach for)
- a retired skill sitting at a path the template never used — an older sync that
  wrote it elsewhere, or a hand copy

All three stay candidates. The script deletes a file only when its bytes match
something the template actually shipped there, so nothing is removed that
`git checkout` could not have restored anyway.

Only paths the template **never** carried are held back for a human. For those
the script retires nothing, reports `bootstrap: required`, and under `--apply` writes
`.claude/sync-keep.candidate` — never `.claude/sync-keep` itself. Promoting the
candidate is the human's confirming act; until that file exists, this step
deletes nothing *of unknown origin*, and additions and modifications still sync
normally.

If the template's history cannot be read, the script says
`provenance: unavailable (<reason>)` and retires nothing at all, rather than
treating "I cannot tell" as "project-specific". **Read the reason**: a truncated
clone, a ref that does not resolve, and an unreadable object are different
problems, and only the first is fixed by deepening the clone — the advice is
attached to the reason that warrants it, not to all of them. Step 1's
`--filter=blob:none` is what keeps that from being the normal case.

Truncation is detected at **any** depth, by whether the revision's root commit
records a parent git does not have. A `--depth 5` clone is as unreadable as a
`--depth 1` one for this purpose, and reporting only the latter meant the same
template commit could yield two different retirement sets.

The depth that matters is the **template revision's**, not the project's. A
project that is itself a `--depth 1` checkout — what CI does by default — still
gets full provenance, as long as the ref it syncs from carries its history. A
second
`--apply` while the candidate is still sitting there exits 1 rather than
overwriting it, so the routine "I have not promoted it yet" case is an error by
design — promote the file or delete it.

**A declared root the template has no files under is skipped, not fatal.** It is
reported as `skipped: <root>` and nothing under it is retired — upstream may have
emptied it legitimately, and two roots here hold a single file each, so one
commit removing that file must not disable retirement everywhere. More than one
empty root is refused outright: upstream retires roots one release at a time,
while a truncated checkout empties several at once, and retiring against that
would delete the project's copy of each.

The script scans only what the § Syncable Paths block above declares, reading it
from the template rather than the project so a stale branch cannot narrow the
scan. It never deletes an untracked file, and it fails loudly — deleting
nothing — on an invalid `sync-keep` pattern or a syncable root the template
cannot vouch for.

Retired content was folded into surviving skills, not dropped: `tdd` → `/build`
Phase 1 § *TDD Discipline*; `simplify` and `deslop` → `/quality-gate` Phase 1
and Phase 2; `verify-e2e` → `/verify --scope e2e`.

### Step 6.5 — Unmigrated Learning Store Check

/sync overwrites `CLAUDE.md` and the skills, so a project can end up with new
skills pointing at `tasks/solutions/` while its learnings still sit in the old
monolithic store. Detect and tell the user — never migrate for them:

```bash
for f in memory lessons bugs; do [ -f "tasks/$f.md" ] && echo "unmigrated: tasks/$f.md"; done
```

(The paths are constructed, not written literally, so the template repo's
retired-reference sweep stays strict.)

If any hit **and** `tasks/solutions/` does not exist:

> ⚠ This project still uses the retired monolithic learning store. The synced
> skills read `tasks/solutions/` instead. Run the converter from your
> coding-agent-workflow clone —
> `python3 <template-clone>/scripts/migrate-learning-store.py --repo .`
> (dry-run by default; `--apply` to convert; originals are archived, never
> deleted). Where `python3` is not on PATH (Windows, notably), substitute
> `python` or `py` — the script is plain stdlib and runs on any of the three.

If `tasks/solutions/` exists alongside old files, name the leftover files and
suggest re-running the migration or archiving them manually. Silent when there
is nothing to flag.

### Step 7 — Optional: Re-wire graphify

`graphify` is a per-machine CLI (`~/.local/bin/graphify`) that most projects do not use.
This step is **optional and non-blocking** — never abort, fail, or roll back a sync
because of it. Skip silently when the binary is absent:

```bash
command -v graphify >/dev/null 2>&1 || echo "graphify not installed — skipping"
```

If it *is* available, note that `/sync` may have just overwritten `CLAUDE.md`, which
wipes the graphify section written by `graphify claude install`. Re-run the per-project
wiring to restore it:

```bash
graphify claude install || true   # CLAUDE.md section + PreToolUse hook
graphify hook install  || true    # post-commit / post-checkout re-index git hooks
```

Both are idempotent, so re-running after every sync is expected and harmless.
`graphify hook status` reports whether the git hooks are already in place if you'd
rather check before writing.

Then confirm the graph itself isn't stale. Per-project state lives in
`graphify-out/graph.json`; if it is missing or older than recent commits, refresh it:

```bash
graphify update . || true
```

Report the outcome as a single line and move on. Because this runs after the sync is
already applied, a graphify failure leaves the sync itself fully intact.

## Edge Cases

- **CLAUDE.md is safe to overwrite**: `CLAUDE.md` contains only shared template rules (workflow, principles, skills index). Project-specific content lives in `.claude/project.md` (Claude Code) or `AGENTS.md` (Pi), which `/sync` never touches. The `@.claude/project.md` and `@CLAUDE.local.md` imports at the top of `CLAUDE.md` are Claude Code layering — they survive the overwrite unchanged since `/sync` replaces the whole file with the same imports.
- **settings.json merge**: If the project has custom hooks in `.claude/settings.json`, show both versions and help the user merge rather than overwrite. Syncing this file never installs the `SessionStart` drift hook — that is registered once at user level by `install.sh` (see Automatic Drift Notification). If a project's `.claude/settings.json` contains a `SessionStart` entry pointing at `session-start.sh`, it duplicates the user-level registration and makes the banner print twice — flag it for removal.
- **New files**: Files that exist in the template but not the project are shown as NEW and can be added.
- **Deleted files**: Files that exist in the project's `.claude/` but NOT in the template are flagged — they may be project-specific additions (don't remove them).
- **`.claude/project.md` missing in the target project**: expected for fresh projects that haven't run `/setup-deployment` yet. `/sync` does not create it — that happens lazily on first write by `/setup-deployment` or the migration step above.
