---
name: sync
description: Pull latest skills, hooks, agents, and config from the jplugin-agentic-development template repo.
harness: universal
---

# /sync — Sync Workflow Updates from Template Repo

Pull the latest skills, hooks, agents, and config from the `jplugin-agentic-development` template repo into the current project.

## Layered Configuration Model

One instruction file per project, `AGENTS.md`, read by every harness. `/sync` rewrites only the text between its two markers, so the template's rules and the team's rules share a file without sharing an edit.

| Path | Scope | Committed? | Touched by /sync? |
|---|---|---|---|
| `AGENTS.md` — the managed block, `<!-- jplugin-agentic-development:begin -->` to `<!-- jplugin-agentic-development:end -->` | Shared rules: workflow, principles, review taxonomy, task tracking, code economy | Yes | **Yes — replaced wholesale by `scripts/sync-managed-block.py`** |
| `AGENTS.md` — below the end marker | Team-shared project rules, the `Task tracking instructions:` pointer, `## Deployment Targets` | Yes | **Never** |
| `CLAUDE.md` | The single line `@AGENTS.md` — Claude Code's import of the same file | Yes | **Rewritten whenever it differs** |
| `.agents/skills/`, `.agents/agents/`, `.agents/references/` | Canonical skills, personas and protocol references — readable by any harness | Yes | **Yes** |
| `CLAUDE.local.md` | Personal per-project overrides (Claude Code, loaded natively) | No (gitignored) | **Never** |
| `~/.pi/agent/AGENTS.md` | Cross-project personal (Pi) | N/A (global) | **Never** |

Claude Code follows the `@AGENTS.md` import; Pi and Codex read `AGENTS.md` natively. There is no `.claude/project.md` any more. A project still carrying one keeps working — its pointer and its Deployment Targets are read after `AGENTS.md`, with a one-line notice — until a later `/sync` step moves that content below the end marker and deletes the file (`specs/single-instruction-file.md`).

## Source Repo

- **GitHub**: `Joaovsales/jplugin-agentic-development`
- **Remote name convention**: `workflow`

## Automatic Drift Notification

The `session-start.sh` hook checks the `workflow` remote once per 24h and prints a
one-line `🔄 TEMPLATE DRIFT` notice at session start when syncable paths differ
from `workflow/<default-branch>`. It does **not** modify files — it only nudges
you to run `/sync`.

**Where the hook is registered:** in the plugin's `hooks/hooks.json`, against
`.agents/hooks/session-start.sh` — once, for every project the plugin is enabled in,
together with `PreCompact` and `Stop`. Neither `.claude/settings.json` nor `install.sh`
registers any of the three. Hooks from every source merge and all run, so a project
file that still carries an entry pointing at `.claude/hooks/<name>.sh` would fire the
same event twice; the Step 5 settings merge removes such entries (D16). Do not
"helpfully" add one back.

**Enable on a fresh project:**

```bash
git remote add workflow https://github.com/Joaovsales/jplugin-agentic-development.git
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
> other hand copies of this list against it. Both parsers split each line on the
> arrow glyph, so keep the two-column shape, and keep the trailing slash on
> every directory: an entry without one is read as a file and excluded from
> retirement. Do not use that glyph in prose anywhere between this heading and
> the next one — the parsers are fence-unaware and would read the line as a root.
> A right-hand column that begins `RETIRED` marks a root the script scans for
> retirement but `/sync` never checks out; keep the marker first on that line.
> One that begins `MANAGED` marks a file `/sync` writes through
> `scripts/sync-managed-block.py` instead of checking out: it is in no diff
> list, because the project's own text below the end marker differs by design.

```
AGENTS.md             → MANAGED — the block between the markers is replaced by scripts/sync-managed-block.py (Step 5); the project's text below the end marker is never touched
CLAUDE.md             → Pointer: the single line @AGENTS.md, written by the same script (Step 5), never checked out
.agents/skills/       → Canonical skills (harness-neutral)
.agents/agents/       → Canonical sub-agent personas (harness-neutral, discovered by pi-subagents)
.agents/references/   → Protocol references read at dispatch time: finding model, review dispatch contract, model routing
.agents/hooks/        → Lifecycle hook scripts (session-start, pre-compact, session-stop), run by the plugin's hooks/hooks.json
.claude/skills/       → RETIRED — the jplugin plugin reads .agents/skills/; kept so /sync retires downstream copies
.claude/hooks/        → RETIRED — the scripts moved to .agents/hooks/ and run from the plugin; kept so /sync retires downstream copies
.claude/agents/       → Subagent definitions (Claude Code only)
.claude/browsers/     → Browser adapter runbooks read by /verify-evidence --scope e2e
.claude/settings.json → env + plugin declaration (Claude Code only — registers no hook, see above)
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
- `AGENTS.md` below the end marker — project rules, the task-tracking pointer, Deployment Targets (only the block above it is written)
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
| **Add git remote** | `git remote add workflow https://github.com/Joaovsales/jplugin-agentic-development.git` |
| **Manual diff** | Skip git, do a file-by-file comparison using a local clone in `/tmp` |

If user chooses manual diff, clone to a **fresh private directory** and remember it:

```bash
WORKFLOW_CLONE="$(mktemp -d)"
git clone --filter=blob:none https://github.com/Joaovsales/jplugin-agentic-development.git "$WORKFLOW_CLONE"
```

`--filter=blob:none`, not `--depth 1`: Step 6.4 asks the template what it *used
to* carry, and a shallow clone's history is just its current state — under which
every retired skill looks project-specific and is kept forever. The filter keeps
the clone cheap (commits and trees only; file contents are fetched on demand)
while leaving that question answerable.

Do not reuse a fixed path such as `/tmp/jplugin-agentic-development`, and do not trust
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

### Step 3 — Show What Changed

Compare the syncable paths between the current project and the template source.

**If git remote mode:**
```bash
# Show changed files in syncable paths only
# Note: use two-dot diff (not three-dot) — template and project have unrelated histories,
# so HEAD...workflow/$WORKFLOW_BRANCH fails with "no merge base"
git diff workflow/$WORKFLOW_BRANCH --stat -- .agents/skills/ .agents/agents/ .agents/references/ .agents/hooks/ .agents/git-hooks/ .claude/agents/ .claude/browsers/ .claude/settings.json CLAUDE.md
```

Then show the full diff:
```bash
git diff workflow/$WORKFLOW_BRANCH -- .agents/skills/ .agents/agents/ .agents/references/ .agents/hooks/ .agents/git-hooks/ .claude/agents/ .claude/browsers/ .claude/settings.json CLAUDE.md
```

**If manual diff mode:**
For each syncable path, compare using `diff -rq` between the project and `"$WORKFLOW_CLONE"`.

**Managed block preview (both modes):** `AGENTS.md` is in neither list above —
the project's own text below its end marker differs from the template's by
design, so a whole-file diff is noise. Preview what Step 5 will write with the
script's `--dry-run`, run from the template's copy for the same reason the
retirement preview below is:

```bash
SYNC_TMP="$(mktemp -d)"
git show "workflow/$WORKFLOW_BRANCH:.agents/skills/sync/scripts/sync-managed-block.py" > "$SYNC_TMP/sync-managed-block.py"
git show "workflow/$WORKFLOW_BRANCH:AGENTS.md" > "$SYNC_TMP/AGENTS.md"
python3 "$SYNC_TMP/sync-managed-block.py" --source "$SYNC_TMP/AGENTS.md" \
  --target AGENTS.md --claude-md CLAUDE.md --migrate .claude/project.md --dry-run
```

In manual-diff mode run
`python3 "$WORKFLOW_CLONE/.agents/skills/sync/scripts/sync-managed-block.py"`
with `--source "$WORKFLOW_CLONE/AGENTS.md"` instead. It prints `would AGENTS.md:
replaced|appended|unchanged`, `would CLAUDE.md: written|unchanged` and `would
migration: moved <n> section(s), .claude/project.md deleted` or `would migration:
nothing to move`; show all three lines in the summary — the migration line is
how the user approves the deletion Step 6.6 performs.

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
| .agents/skills/sync/SKILL.md  | NEW      | New sync skill              |
| .claude/agents/planner.md     | MODIFIED | Updated planning prompts    |
| AGENTS.md (managed block)     | MODIFIED | Block replaced by the script |
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

**Write the managed block and the pointer.** `AGENTS.md` and `CLAUDE.md` are
never in `<selected-files>`: checking either out would replace the project's
own rules with the template's. The script is their only write path — it
replaces the text between the markers (appending a block when the project has
none, recognising the markers written before the repository was renamed), copies every
byte outside them unchanged, and rewrites `CLAUDE.md` to the single line
`@AGENTS.md` whenever it differs. Both land in the same run, so no downstream
session ever loads the pointer without the block:

```bash
SYNC_TMP="$(mktemp -d)"
git show "workflow/$WORKFLOW_BRANCH:.agents/skills/sync/scripts/sync-managed-block.py" > "$SYNC_TMP/sync-managed-block.py"
git show "workflow/$WORKFLOW_BRANCH:AGENTS.md" > "$SYNC_TMP/AGENTS.md"
python3 "$SYNC_TMP/sync-managed-block.py" --source "$SYNC_TMP/AGENTS.md" \
  --target AGENTS.md --claude-md CLAUDE.md
```

In manual-diff mode point `--source` at `"$WORKFLOW_CLONE/AGENTS.md"` and run
the clone's copy of the script. Report its two outcome lines (`AGENTS.md:
replaced|appended|unchanged`, `CLAUDE.md: written|unchanged`). Exit 2 means a
malformed marker pair in the project's `AGENTS.md` (unmatched or duplicated);
nothing was written — show the message, which names the file and line, and
stop the sync there.

**Merge the plugin declaration.** The template's `.claude/settings.json`
declares the `jplugin-agentic-development` marketplace under
`extraKnownMarketplaces` and enables `jplugin@jplugin-agentic-development` under
`enabledPlugins`. Step 5 merges those two keys into the project's existing
`.claude/settings.json` rather than overwriting it — the `env` block and any
project-specific keys stay as they are. The one thing it removes is a
`SessionStart`, `PreCompact` or `Stop` entry whose command names
`.claude/hooks/<name>.sh`: those scripts now run from the plugin's
`hooks/hooks.json`, and an entry left beside that registration fires the same
event twice — the checkpoint flush has no guard against it (D16). The entry
goes whether or not the script still exists; Step 6.4 retires the script in the
same run. `.claude/settings.json` is never in `<selected-files>`: the merge
below is its only write path, so the checkout above cannot replace the
project's file. It writes no `ref`: a
marketplace `ref` must be a branch or tag (a commit sha does not clone), so the
source floats on the template's default branch and the plugin's `version` in
`.claude-plugin/plugin.json` is the pin — `version` pins what Claude Code caches
for the project, and it refreshes that copy only when the template bumps it.
Skill bodies and the scripts they call can diverge between a `version` bump and
the project's next sync: Claude Code refreshes the cached skills on the project's
next open, while the scripts they invoke by project path stay at the last `/sync`.
Sync promptly after a bump — `/sync` is what closes that window.

The declaration itself is read from the template's copy, never restated here,
so the template's `.claude/settings.json` stays its single source.

```bash
python3 - "$(git show "workflow/$WORKFLOW_BRANCH:.claude/settings.json")" <<'PY'
import json, re, sys
template = json.loads(sys.argv[1])
path = ".claude/settings.json"
settings = json.load(open(path, encoding="utf-8"))
for key in ("extraKnownMarketplaces", "enabledPlugins"):
    settings.setdefault(key, {}).update(template.get(key, {}))
# D16: hooks/hooks.json registers these three; a project entry still pointing at
# a .claude/hooks/ script would fire the same event twice.
retired = re.compile(r"\.claude/hooks/[^/\s\"']+\.sh")
hooks = settings.get("hooks", {})
for event in ("SessionStart", "PreCompact", "Stop"):
    groups = hooks.get(event, [])
    for group in groups:
        group["hooks"] = [h for h in group.get("hooks", []) if not retired.search(h.get("command", ""))]
    hooks[event] = [g for g in groups if g.get("hooks")]
    if not hooks[event]:
        hooks.pop(event)
if "hooks" in settings and not hooks:
    settings.pop("hooks")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
```

In manual-diff mode pass `$(cat "$WORKFLOW_CLONE/.claude/settings.json")` instead.
Run it on every sync so a renamed marketplace or plugin id lands in the project.
Beyond the retired hook entries the merge deletes nothing: after a rename, remove
the old marketplace and plugin keys by hand, or every synced project keeps
enabling an id that no longer resolves.

### Step 6 — Post-Sync

1. Run `git diff --stat` to confirm what was updated
2. Ask the user if they want to commit the sync:
   - Suggested message: `chore: sync workflow updates from jplugin-agentic-development`
3. If `CLAUDE.md: written` replaced a full rules file with the pointer, say so: Claude Code now reads the block through `AGENTS.md`. A project that still has `.claude/project.md` is no longer importing it — Step 6.6 moves that file's content below the end marker in this same run; until it has run, the pointer and Deployment Targets there are still read (with a notice) and any other team text is loaded by nothing

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

**A `RETIRED` root is scanned, never checked out.** `.claude/skills/` is marked
`RETIRED` in § Syncable Paths: the plugin reads `.agents/skills/` directly, so
Step 5 no longer copies anything there, and the copies earlier syncs left behind
are retired here — but only a file whose bytes match something the template once
shipped at that path. A project-local skill under that root
(a `verify-<app>` skill an earlier `/create-verification-skill` mirrored there) is never a candidate,
with or without a `sync-keep` entry. Nothing under the retired root enters the
plan while the project's `.claude/settings.json` does not enable
`jplugin@jplugin-agentic-development`: until it does, those copies are the only
skills the project has. The report says so in one `retired roots:` line naming
the file and Step 5. In the Step 3 preview that is the expected state — Step 5
has not run yet — and the live-root list is unaffected; here it means the
settings write was skipped, so run it and re-run. A retired root never counts
toward the one-empty-root budget, so the template having nothing under it is
the expected state, not the "incomplete source" refusal. The running session
cached its plugins at startup, so once the copies are gone the skills return on
the next session start, not in this one.

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
skill into `.agents/skills/` — and nothing
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
and Phase 2; `verify-e2e` → `/verify-evidence --scope e2e`; `route` → the routine contract
at `.agents/skills/wrap-up-session/references/routines.md`, plus
`task-registry select`/`claim` and `/wrap-up-session` § *The Pull Request*.

### Step 6.5 — Unmigrated Learning Store Check

/sync replaces the managed block and the skills, so a project can end up with new
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
> jplugin-agentic-development clone —
> `python3 <template-clone>/scripts/migrate-learning-store.py --repo .`
> (dry-run by default; `--apply` to convert; originals are archived, never
> deleted). Where `python3` is not on PATH (Windows, notably), substitute
> `python` or `py` — the script is plain stdlib and runs on any of the three.

If `tasks/solutions/` exists alongside old files, name the leftover files and
suggest re-running the migration or archiving them manually. Silent when there
is nothing to flag.

### Step 6.6 — Project-File Migration

Before the single instruction file, a project's own rules lived in
`.claude/project.md`, imported by the old `CLAUDE.md`. The pointer written in
Step 5 imports nothing but `AGENTS.md`, so whatever is still in that file is
loaded by nothing — except the task-tracking pointer and the Deployment Targets
table, which their readers still find there with a one-line notice. Move it
once, inside the run the user approved in Step 4:

```bash
python3 "$SYNC_TMP/sync-managed-block.py" --source "$SYNC_TMP/AGENTS.md" \
  --target AGENTS.md --migrate .claude/project.md
```

Same script and source as Step 5 (`$SYNC_TMP` from that step; in manual-diff
mode the clone's copy with `--source "$WORKFLOW_CLONE/AGENTS.md"`). The block was
written already, so the first line reads `AGENTS.md: unchanged`; report the
`migration:` line. What moves is **everything** below the file's own header —
its `# ` title, the `> ` blockquote describing the file, and the `---` that
closes them — in its original order with headings unchanged, except the four
generic sections the block owns now (`### Code Economy`, `### Surgical Changes`,
`### Ambiguity Protocol`, `### Large-Artifact Handoff`) and the `### Task
Tracking` prose that explained where the pointer lived. The pointer line itself
moves and is written first, directly below the end marker, so
`/task-registry` finds it in `AGENTS.md`. A `## Project-Specific Rules` heading
already below the end marker is reused rather than duplicated. `AGENTS.md` is
written first and `.claude/project.md` deleted last, so an interrupted run
leaves a redundant copy the next run removes — never a lost section.

| Outcome | Meaning |
|---------|---------|
| `migration: moved <n> section(s), .claude/project.md deleted` | done; `git diff` shows the sections below the end marker |
| `migration: nothing to move` | no `.claude/project.md` — already migrated, or the project never had one |
| exit 2, `'## Deployment Targets' is also below the end marker` | the table exists in both files; nothing was written and `project.md` is intact — merge the two tables by hand, then re-run this step |

The CI mirror (`sync-template.yml`) never runs this step: it adds and
overwrites but never deletes, and the migration ends in a delete. A project
synced only by CI migrates on its first hand-run `/sync`.

### Step 7 — Optional: Re-wire graphify

`graphify` is a per-machine CLI (`~/.local/bin/graphify`) that most projects do not use.
This step is **optional and non-blocking** — never abort, fail, or roll back a sync
because of it. Skip silently when the binary is absent:

```bash
command -v graphify >/dev/null 2>&1 || echo "graphify not installed — skipping"
```

If it *is* available, note that `graphify claude install` appends its `## graphify`
section to `CLAUDE.md`, which is now the single line `@AGENTS.md` — `/sync` rewrites
that file whenever it differs, so the section would vanish on the next sync.
`install.sh` moves it below the end marker of `AGENTS.md`, where it survives; if
the section is missing from `AGENTS.md`, re-run the per-project wiring and move it:

```bash
graphify claude install || true   # writes a CLAUDE.md section — move it into AGENTS.md (see install.sh)
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

- **`CLAUDE.md` is rewritten, never merged**: it holds the single line `@AGENTS.md`. A downstream `CLAUDE.md` that still carries the old inline rules is replaced by the pointer in the same Step 5 run that writes the block, so no session ever loads the pointer alone. `CLAUDE.local.md` is loaded by Claude Code natively and needs no import line.
- **`AGENTS.md` missing in the target project**: the script creates it with the block alone (`AGENTS.md: appended`); project rules go below the end marker afterwards.
- **settings.json merge**: If the project has custom hooks in `.claude/settings.json`, show both versions and help the user merge rather than overwrite. Syncing this file installs no hook — the three lifecycle events come from the plugin's `hooks/hooks.json` (see Automatic Drift Notification). The Step 5 merge removes only an entry whose command names `.claude/hooks/<name>.sh`; a project's own hooks stay.
- **New files**: Files that exist in the template but not the project are shown as NEW and can be added.
- **Deleted files**: Files that exist in the project's `.claude/` but NOT in the template are flagged — they may be project-specific additions (don't remove them).
