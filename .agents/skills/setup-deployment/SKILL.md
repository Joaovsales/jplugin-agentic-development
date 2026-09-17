---
name: setup-deployment
description: One-time interactive bootstrap for deployment verification. Scans the project for deployment signal files, asks the user to confirm detected services and project IDs, and writes the routing table into .claude/project.md.
disable-model-invocation: false
---

# /setup-deployment — Deployment Verification Bootstrap

Configure `/verify-deployment` for this project. Scans the project for deployment signal files, confirms detected services with the user, prompts for the per-service routing details, and writes the `## Deployment Targets` section into `.claude/project.md`. (Legacy location: `CLAUDE.md`. Projects synced before the project-config split keep their existing section there until `/sync` migrates it.)

This skill is idempotent. Re-running it offers to update existing routing rather than duplicating it.

---

## Step 1 — Discover available adapters

Read every runbook in `.claude/deployments/*.md` (excluding `README.md`). For each, parse the YAML frontmatter and extract:

- `name`
- `display_name`
- `detect_files`

Build an in-memory map: `{ name → { display_name, detect_files, runbook_path } }`.

**If `.claude/deployments/` is missing or empty:**

```
No deployment runbooks found in .claude/deployments/.
This template ships with starter runbooks for Railway and Vercel. If you ran
/sync recently, those should be present. Otherwise, see .claude/deployments/README.md
for how to author a new runbook.
```

Exit. Nothing to set up.

---

## Step 2 — Scan the project for deployment signals

For each adapter from Step 1, check whether **any** of its `detect_files` exists at the project root. Any match counts as "service detected".

Build a list of `detected_services` — adapters whose detection succeeded.

**If `detected_services` is empty:**

Ask the user:

```
No deployment signal files detected at the project root.
Available adapters: <comma-separated display_names>

Do you want to manually configure a service anyway? (y/n)
```

- **No** → exit 0 with `No deployment services configured. Run /setup-deployment again after adding a deployment config file (railway.json, vercel.json, etc.) to enable.`
- **Yes** → present the full adapter list and let the user pick which to configure manually. Skip Step 3's auto-detect summary and go straight to Step 4 with the user's manual selection.

**If `detected_services` is non-empty**, present the summary:

```
Detected deployment services:

  ✓ <display_name 1> (matched: <detect_file>)
  ✓ <display_name 2> (matched: <detect_file>)

Configure verification for these services? (y/n/edit)
```

- **y** → proceed to Step 3 with the auto-detected list
- **n** → exit 0 (no changes)
- **edit** → let the user toggle individual services in/out before proceeding

---

## Step 3 — Per-service interview

For each confirmed service, ask:

```
<display_name>:
  Triggers on branch [default: main]:
  Project ID (used for dashboard links):
```

- **Triggers on branch** — the branch name whose pushes should trigger this service's build. Default `main`. Accept globs (e.g. `preview/*`) for projects with preview environments.
- **Project ID** — free-form identifier the runbook will interpolate into its `dashboard_url_template`. Tell the user the format expected by the runbook (read the runbook's "Dashboard URL" body section if present).

Store the responses as `{ service_name → { branch, project_id } }`.

---

## Step 4 — Check existing .claude/project.md state

Read `.claude/project.md`. **If the file does not exist, auto-create it** from the stub below before writing the Deployment Targets table. Do NOT fall back to writing into `CLAUDE.md` — that file is template-managed and overwritten by `/sync`.

**Stub content (create if missing):**

```markdown
# Project-Specific Configuration

> Imported by CLAUDE.md. Safe to edit — /sync never touches this file.

```

If `.claude/project.md` cannot be created or written (permission error, filesystem failure), **abort** with:

```
setup-deployment: could not write .claude/project.md — <specific error>.
This file is required for deployment target configuration. Resolve the filesystem
error and re-run /setup-deployment. Do NOT manually add the Deployment Targets
section to CLAUDE.md — it will be wiped on the next /sync.
```

Once `.claude/project.md` exists, look for an existing `## Deployment Targets` section in it. (Also check `CLAUDE.md` for a legacy section; if one is found there, instruct the user to run `/sync` first, which will auto-migrate the legacy section into `.claude/project.md` before /setup-deployment proceeds.)

| Existing state | Action |
|---|---|
| Section absent in project.md | Append a new section at the end of `.claude/project.md` |
| Section present, no overlapping services | Add the new rows to the existing table; preserve existing rows |
| Section present, same service appears | Ask: `<service> is already configured for branch <X>. Replace with the new branch <Y>? (y/n)` — replace on yes, skip on no |
| Legacy section present in CLAUDE.md | Abort: `Legacy Deployment Targets section found in CLAUDE.md. Run /sync first to migrate it to .claude/project.md, then re-run /setup-deployment.` |

**Format of the inserted section:**

```markdown
## Deployment Targets

> Populated by `/setup-deployment`. Read by `/verify-deployment`.
> Delete this section to disable deployment verification for this project.

| Service       | Runbook                          | Triggers on branch | Project ID    |
|---------------|----------------------------------|--------------------|---------------|
| <display_1>   | .claude/deployments/<name_1>.md  | <branch_1>         | <project_1>   |
| <display_2>   | .claude/deployments/<name_2>.md  | <branch_2>         | <project_2>   |

**Config:**
- Max fix iterations: 3
- Build timeout: 15m
- Preferred status source: github-checks
```

The Config block defaults are inserted as-is on a fresh setup. If the section already had a Config block, preserve the user's existing values rather than overwriting.

---

## Step 5 — Verify runbook files are in place

For each confirmed service, verify `.claude/deployments/<name>.md` exists. It should — we read it in Step 1 — but check anyway in case the directory was modified between steps.

If any runbook is missing, abort with:

```
Runbook missing: .claude/deployments/<name>.md
This shouldn't happen after Step 1 succeeded. Run /sync to re-pull template files.
```

---

## Step 6 — Update `.gitignore`

Read `.gitignore` (create it if missing). Ensure these entries exist:

```
tasks/deploy-state.json
tasks/deploy-logs-*.log
```

Add any missing entries with a comment header:

```
# Deployment verification state — per-session, not committed
tasks/deploy-state.json
tasks/deploy-logs-*.log
```

If both entries are already present (verbatim or via a broader pattern like `tasks/*.json`), make no changes.

---

## Step 7 — Final report

Output:

```
Deployment verification configured.

Targets:
  ✓ <display_1> on branch <branch_1>
  ✓ <display_2> on branch <branch_2>

Next steps:
  1. Verify your auth is set up: <auth_check_command from each runbook>
  2. Push a commit to a configured branch
  3. Run /verify-deployment (or /wrap-up-session, which calls it automatically)

To disable: delete the "## Deployment Targets" section from .claude/project.md.
To suppress the session-start nudge without enabling: touch .claude/deploy-nudge-dismissed
```

---

## Edge Cases

- **`.claude/` directory missing** — abort with: `.claude/ directory not found at the project root. /setup-deployment requires .claude/ to write .claude/project.md into.`
- **Multiple detect_files match for the same service** — that's fine, just pick the first matching file for the summary line. The service is still listed once.
- **User runs setup with services already configured** — Step 4's merge logic handles this without duplication. The interview in Step 3 only re-asks for services the user explicitly confirms in Step 2.
- **Two different runbooks declare overlapping `detect_files`** (e.g. both list `Dockerfile`) — list both as detected and let the user toggle in the `edit` flow. Don't auto-pick.
- **Project root is not a git repo** — proceed anyway. `/verify-deployment` will fail at its own pre-flight, but `/setup-deployment` is just writing config.
- **Runbook frontmatter is malformed** at Step 1 — skip that runbook with a warning, continue with the rest. Don't crash.

---

## Invariants

1. **Idempotent** — running setup twice with the same answers produces the same `.claude/project.md` state, not duplicate rows.
2. **Non-destructive** — never overwrites a user's existing Config block values; never removes existing rows for services the user didn't re-confirm.
3. **No hardcoded service list** — discovery is purely from `.claude/deployments/*.md`. Adding a new runbook there makes it immediately available to setup.
4. **Writes are confined to** `.claude/project.md` and `.gitignore`. **Never writes to CLAUDE.md** — that file is template-managed and overwritten by `/sync`, so any project-specific content there would be lost.
