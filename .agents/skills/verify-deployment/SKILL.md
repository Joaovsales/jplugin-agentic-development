---
name: verify-deployment
description: Wait for post-push deployment builds to resolve, fetch logs on failure, and loop a code-debugger fix cycle up to 3 iterations before escalating. Service-agnostic — driven by runbook files in .claude/deployments/.
disable-model-invocation: false
---

# /verify-deployment — Post-Push Deployment Verification

Wait for the deployment service(s) configured in `.claude/project.md` § Deployment Targets to finish building the current commit. On failure, fetch logs, delegate the fix to `code-debugger`, push the fix as a new commit, and loop. Maximum 3 fix iterations per service before escalation.

**Note**: The routing table moved from `CLAUDE.md` to `.claude/project.md` so `/sync` can overwrite the template-managed `CLAUDE.md` without wiping deployment config. This skill falls back to `CLAUDE.md` when the section is still in the legacy location and emits a one-time deprecation warning prompting the user to run `/sync` to auto-migrate.

This skill is **service-agnostic by construction**. No specific deployment service is named anywhere in this file. All service-specific behavior comes from runbook files in `.claude/deployments/<service>.md`. Adding a new service is a drop-in change to that directory.

---

## Pre-Flight

### 1. Reject uncommitted changes

Run `git status --porcelain`. If any output:

```
STOP — Uncommitted changes present.
/verify-deployment requires a clean working tree because it pushes new commits
during fix iterations. Commit or stash your changes and re-run.
```

Exit. Do not proceed.

### 2. Locate the routing table

Look for a section header line that matches **exactly** `^## Deployment Targets[[:space:]]*$` — the heading must be `## Deployment Targets` with no trailing text. Headings like `## Deployment Targets (placeholder — run /setup-deployment to populate)` are intentionally not matched, so the template repo can document the schema without activating verification.

**Search order (primary, then legacy fallback):**

1. **`.claude/project.md`** (primary location) — read the file if it exists and grep for the exact header regex above
2. **`CLAUDE.md`** (legacy fallback) — only if step 1 did not find a matching section. If the section IS found here, emit the deprecation warning below **once per invocation** and proceed using the CLAUDE.md section:

   ```
   ⚠ Deprecation: ## Deployment Targets found in CLAUDE.md. Run /sync to migrate
     to .claude/project.md — CLAUDE.md is template-managed and its project-specific
     content will be wiped the next time /sync overwrites it.
   ```

**If the section is missing from BOTH files:**

- For each runbook in `.claude/deployments/*.md` (excluding `README.md`), parse its frontmatter and read `detect_files`
- Check the project root for any matching signal file
- **If any signal matches**: print
  ```
  Deploy signals detected (<file>). Run /setup-deployment to enable automatic build verification.
  ```
  Exit 0 — nothing to verify.
- **If no signals match**: exit 0 silently. The project does not use a recognized deployment service.

**If the section exists:** parse the table. Each row has columns `Service | Runbook | Triggers on branch | Project ID`. Also parse the optional config block below the table for `Max fix iterations`, `Build timeout`, `Preferred status source`.

### 3. Resolve git context

Run:

- `git rev-parse HEAD` → current commit SHA
- `git rev-parse --abbrev-ref HEAD` → current branch
- `git remote get-url origin` → confirm a remote exists (else escalate: "No remote configured — cannot poll for deployment")

### 4. Filter applicable targets

Keep only target rows whose `Triggers on branch` matches the current branch. Branch matching is **exact** unless the target row uses a glob (e.g. `preview/*`); if a glob is present, match the current branch against it.

**If the filtered set is empty:**

```
No deployment targets trigger on branch <current-branch>. Skipping verification.
```

Exit 0.

---

## Per-Target Verification

For each applicable target, in the order they appear in the table:

### Step A — Load and validate the runbook

Read the runbook file referenced by the `Runbook` column. Parse the YAML frontmatter. Validate against the contract documented in `.claude/deployments/README.md`:

- Required (always): `name`, `display_name`, `detect_files`, `status_source`, `auth_check_command`, `dashboard_url_template`, `default_timeout_minutes`
- If `status_source: github-checks` → `check_contexts` is required
- If `status_source: cli` → `cli_status_command` is required
- `name` must match the filename stem
- `common_failure_patterns` entries (if present) must each have both `match` and `hint`

**If validation fails:** report the specific error and skip this target. Do not crash. Continue with the next target.

```
<display_name>: malformed runbook — <specific reason>. Skipping this target.
```

### Step B — Auth check (fail fast)

Run the runbook's `auth_check_command`. If it exits non-zero:

```
<display_name>: auth check failed.
Run `<auth_check_command>` manually and resolve credentials before retrying.
This does NOT count as a fix iteration.
```

Mark this target as `AUTH_FAILED` and move to the next target.

### Step C — Poll for build status

Initialize:

- `started_at` = now
- `iteration` = current value from `tasks/deploy-state.json` for this `{commit_sha, service}` key, or `0`
- `timeout` = project.md config `Build timeout` if set, else runbook `default_timeout_minutes`
- `max_iterations` = project.md config `Max fix iterations` if set, else `3`

Persist `{ service, iteration, last_sha, started_at }` to `tasks/deploy-state.json` so a session resume can pick up where polling left off.

**Polling loop** (until terminal status or timeout):

- **github-checks path**: call `mcp__github__get_commit` with the current commit SHA. Filter the returned check runs by name against the runbook's `check_contexts` list. **All matching contexts must resolve to success** — some services publish more than one check run per commit (e.g. separate Preview and Production contexts), and a single failure on any context fails the target.
  - States: `queued`, `in_progress`, `pending` → keep waiting
  - State `completed` with conclusion `success` → that context is done
  - State `completed` with conclusion `failure` / `cancelled` / `timed_out` → record the failing context, abort polling, jump to Step D
- **cli path**: run the runbook's `cli_status_command`. Parse the JSON output for a `state` or `status` field. Map values:
  - `pending` / `building` / `queued` → keep waiting
  - `success` / `ready` / `live` → done
  - `failed` / `error` / `cancelled` → jump to Step D

**Poll intervals**: 15 seconds for the first 2 minutes, then 30 seconds. Cap total wait at `timeout` minutes.

**Transient errors** (network failure, GitHub API 5xx, runbook command exit 124) are retried at the polling layer with exponential backoff (5s → 10s → 20s, then back to normal interval). They do **not** consume a fix iteration.

**Terminal states:**

| Status | Action |
|---|---|
| All contexts SUCCESS | Record `<display_name>: SUCCESS (iteration N+1 attempts)`. Move to next target. |
| Any FAILURE | Jump to Step D (fix-loop) |
| CANCELLED | Ask user: `<display_name>: build was cancelled — retry deployment? (y/n)`. If yes, restart Step C. If no, mark `CANCELLED`, move to next target. |
| TIMEOUT (no resolution within window) | Mark `TIMEOUT`, write the dashboard URL (interpolate `dashboard_url_template` with the project_id from the table row), move to next target. |

### Step D — Fix loop

Pre-condition: `iteration < max_iterations`. If `iteration >= max_iterations`, jump to Step E (escalation) immediately without spending another attempt.

#### D.1 — Fetch logs

Determine the source:

- **github-checks** with `log_fetch_command` set: prefer the runbook's `log_fetch_command`, interpolating `{deployment_id}` from the failing check run's `external_id` or `details_url`
- **github-checks** without `log_fetch_command`: fetch the check run's `details_url` (the build's web page) — this is best-effort; many services don't expose plain-text logs at that URL
- **cli**: run `log_fetch_command` with `{deployment_id}` from the prior status response

Follow the **Large-Artifact Handoff** convention (`.claude/project.md`): truncate logs to the last 500 lines if larger to fit the debugger's context window, and keep the original full log saved at `tasks/deploy-logs-<service>-<sha>.log` (gitignored via the same pattern as `deploy-state.json`).

#### D.2 — Match failure patterns

Scan the fetched logs for each `match` substring in the runbook's `common_failure_patterns`. Collect all matching `hint` strings. These are pre-curated debugging shortcuts — they go into the debugger's context.

#### D.3 — Delegate to `code-debugger` agent

Invoke the `code-debugger` agent with `model: "sonnet"`. The prompt must include:

- The failing service's `display_name`
- The (truncated) build logs
- The matched hints from D.2
- The runbook's body content (the human-readable troubleshooting section after the frontmatter)
- The current commit SHA
- The output of `git diff origin/main...HEAD` (changes since the base branch)
- A clear instruction: "Diagnose the root cause and apply a fix. Run the local test suite to confirm the fix doesn't regress anything. Do NOT commit — the calling skill will create the commit. Report what you changed and why."

**If the code-debugger reports it cannot find a fix** (no diff produced, or explicit "I don't know"): treat that as a failed iteration. Increment the counter. Log the reason. Continue to D.4 anyway — the escalation path will catch it after 3 attempts.

#### D.4 — Commit the fix as a NEW commit

Never amend. Each iteration must produce a distinct SHA so the deployment service has something new to build.

Stage the files the debugger touched:

```
git add <files-the-debugger-modified>
git commit -m "fix(deploy): <one-line summary from debugger> [deploy-retry N/3]"
```

Where `N` is the new iteration number (1-indexed in the message).

#### D.5 — Push

```
git push origin <current-branch>
```

Apply the same push failure handling as `/wrap-up-session` Step 7:

| Failure | Action |
|---|---|
| Network error | Retry up to 4 times with backoff 2s → 4s → 8s → 16s |
| Non-fast-forward | `git pull --rebase`, resolve any conflicts, re-run, push again |
| Permission denied | Escalate to user — do not retry |
| Branch protection | Escalate to user — do not retry |

#### D.6 — Increment and loop

- `iteration` += 1
- Update `tasks/deploy-state.json` with the new SHA from step D.4 and the incremented counter
- Restart Step C with the new SHA

### Step E — Escalation after max iterations

When `iteration >= max_iterations` and the latest build still failed, write `tasks/deploy-report.md` with:

```markdown
# Deployment Failure Report

**Service**: <display_name>
**Branch**: <branch>
**Final commit**: <sha>
**Dashboard**: <dashboard_url with {project_id} interpolated>
**Attempts**: <N> (max reached)

## Iteration history

| # | Commit | Result | Debugger summary |
|---|--------|--------|------------------|
| 1 | <sha-1> | failure | <one-line> |
| 2 | <sha-2> | failure | <one-line> |
| 3 | <sha-3> | failure | <one-line> |

## Final logs (last 500 lines)

```
<paste>
```

## Matched failure hints

- <hint 1>
- <hint 2>

## Suggested manual remediation

The fix loop exhausted itself, which usually means the failure is not fixable in code:

1. Check environment variables in the service dashboard
2. Check for quota / billing / rate-limit issues
3. Check that any required secrets are configured
4. Review the runbook's "Manual troubleshooting" section
5. Consider whether the build command, framework version, or runtime needs changing in the service's settings (not in code)
```

Mark this target as `FAILED_MAX_ITERATIONS` and move to the next target.

---

## Reporting

After all targets have a terminal state, output a per-target summary table:

```
Deployment Verification Results:
| Service           | Status                  | Attempts | Notes |
|-------------------|-------------------------|----------|-------|
| <display_name 1>  | SUCCESS                 | 1        | —     |
| <display_name 2>  | FAILED_MAX_ITERATIONS   | 3        | See tasks/deploy-report.md |
```

**Overall outcome** is the worst case across all targets:

| Per-target states present | Overall outcome | Caller action |
|---|---|---|
| All SUCCESS | `ALL_GREEN` | Caller proceeds |
| Any AUTH_FAILED | `AUTH_FAILED` | Caller STOPs (credentials must be fixed) |
| Any TIMEOUT | `TIMEOUT` | Caller STOPs and asks user |
| Any CANCELLED (after user said no) | `CANCELLED` | Caller STOPs |
| Any FAILED_MAX_ITERATIONS | `FAILED_MAX_ITERATIONS` | Caller STOPs (deploy-report.md exists) |
| All targets skipped (branch mismatch / missing section) | `SKIPPED` | Caller proceeds |

Clean up `tasks/deploy-state.json` only on `ALL_GREEN` or `SKIPPED` — leaving it in place after a failure lets a re-run pick up at the right iteration count.

---

## Edge Cases

- **Commit SHA changes mid-loop** (user pushed a new commit manually, force-pushed, or amended): on the next poll cycle, `git rev-parse HEAD` differs from `last_sha` in the state file. Abort the loop, warn the user: `Commit SHA changed during deployment verification — aborting loop. Re-run /verify-deployment to start over.`
- **Multiple check runs per service**: handled by checking that **all** contexts in `check_contexts` resolve to success. If 2 of 3 succeed and 1 fails, the target is FAILED.
- **No check runs returned within the first 30 seconds** (the service hasn't picked up the push yet): keep polling at the normal cadence. Don't escalate this as a failure — the service may be slow to register.
- **Runbook references a CLI that isn't installed**: `auth_check_command` exits non-zero (command not found = exit 127), which triggers the AUTH_FAILED path. Report includes "command not found — install the CLI or switch to github-checks".
- **`.claude/deployments/` directory missing entirely**: there are no runbooks to validate against. Skip verification with: `No runbooks found in .claude/deployments/. Run /setup-deployment to populate.`
- **`.claude/project.md` `Deployment Targets` section references a runbook file that doesn't exist** (or the same in the legacy `CLAUDE.md` location during fallback): skip that target with `<service>: runbook file not found at <path>`. Continue with other targets.
- **Code-debugger applies a fix that breaks local tests**: per the debugger's own protocol, it should report failure rather than commit. If a diff exists but tests fail, do NOT commit — skip directly to D.6 (count as failed iteration).

---

## Invariants

These properties of this skill are load-bearing:

1. **No hardcoded service names.** Every behavior that varies between deployment services flows from runbook frontmatter. Adding a new service is a drop-in `.claude/deployments/<service>.md` file with zero edits to this skill.
2. **Auth failure does not consume a fix-iteration slot.** AUTH_FAILED is a separate terminal state, reached before any iteration counter increments.
3. **Each fix iteration produces a NEW commit.** Never amend. Each retry needs a distinct SHA for the deployment service to rebuild.
4. **Maximum 3 fix iterations.** After the third failed build, write the report and stop. The user must intervene.
5. **Transient API errors retry at the polling layer**, not at the fix-loop layer. A flaky GitHub Checks call should not consume a fix attempt.
6. **State persists across re-runs** via `tasks/deploy-state.json`, scoped by `{commit_sha, service}` so resuming is possible. Cleared only on `ALL_GREEN` or `SKIPPED`.
7. **Pre-flight rejects uncommitted changes** so the fix loop never accidentally commits unrelated work.
