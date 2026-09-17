---
name: github-actions
display_name: GitHub Actions
detect_files:
  - .github/workflows/
status_source: github-checks
check_contexts:
  # Customize per project — these are sensible defaults for many repos but
  # the actual check run names come from your workflow `jobs.<id>.name` or
  # fallback to the job key. Inspect a recent commit on github.com to see
  # the exact context strings to put here.
  - test
  - lint
  - typecheck
  - build
auth_check_command: "true"
log_fetch_command: gh run view {deployment_id} --log-failed
dashboard_url_template: https://github.com/{project_id}/actions
default_timeout_minutes: 10
common_failure_patterns:
  - match: "Process completed with exit code 1"
    hint: "Generic job failure — scan earlier log lines for the actual error message; the exit-code line is almost always just the final symptom"
  - match: "npm ERR! Test failed"
    hint: "Unit tests failed in CI. Run `npm test` locally with the same Node version pinned in engines.node or .nvmrc to reproduce"
  - match: "Type error:"
    hint: "TypeScript check failed. Run `tsc --noEmit` locally; most common cause is a missing type import or a strict-mode difference with the CI tsconfig"
  - match: "ESLint found"
    hint: "Lint check failed. Run `npm run lint` locally and fix reported violations; do not disable rules to pass CI"
  - match: "Cannot find module"
    hint: "Dependency missing in CI. Verify the package is in dependencies (not devDependencies if the build step needs it) and the lockfile is committed"
  - match: "No space left on device"
    hint: "CI runner exhausted disk. Check for a runaway cache step or a build that writes to /tmp without cleanup; this is an infra issue, not a code bug"
  - match: "The job running on runner .* has exceeded the maximum execution time"
    hint: "Job hit GitHub Actions' 6-hour timeout (or a shorter timeout-minutes setting). Profile locally and look for hanging post-install scripts or infinite loops"
---

# GitHub Actions Runbook

GitHub Actions publishes commit check runs under the job name (or `jobs.<id>.name` if set). `/verify-deployment` polls these via the GitHub Checks API, so no separate auth is needed beyond the existing GitHub MCP access.

## Auth check is a no-op

The `auth_check_command: "true"` field is intentional. Unlike Railway or Vercel runbooks — which need a CLI session to fetch logs on failure — GitHub Actions logs are reachable via two GitHub-native paths:

1. **Primary**: the check run's `details_url` from `mcp__github__get_commit`, fetched via web fetch
2. **Fallback**: `gh run view --log-failed` if the `gh` CLI is installed locally (not required)

If neither is available in your environment, `/verify-deployment` will still detect the failure via the check run's `conclusion` field — you just won't get rich log hints fed to the debugger. That's a graceful degradation, not a crash.

## `check_contexts` must be customized

The shipped defaults (`test`, `lint`, `typecheck`, `build`) work for many Node/TS projects but your workflow may use different job names. To find the exact strings:

1. Open a recent commit on github.com
2. Scroll to the "All checks have passed/failed" section
3. The exact names shown there are what `check_contexts` needs to match

Common project-specific variations you'll want to rename:

- `test (ubuntu-latest, 18.x)` — matrix jobs include the matrix values in the name
- `ci / test` — if the job is inside a named workflow, it's prefixed with the workflow name
- Custom job names like `Unit Tests`, `Integration Tests`, `E2E`

Run `/setup-deployment` after editing `check_contexts` to re-validate the runbook against the routing table.

## Dashboard URL

The `dashboard_url_template` interpolates `{project_id}` from the `Project ID` column of `CLAUDE.md` § Deployment Targets. For GitHub Actions, use `<owner>/<repo>` (e.g. `joaovsales/jplugin-agentic-development`). The resulting URL opens the Actions tab for the repo.

## Manual troubleshooting

When `/verify-deployment` exhausts its 3 fix iterations and escalates, walk this list:

1. **Flaky tests** — re-run the workflow manually from the Actions tab. If it passes on retry without any code change, the test is flaky and should be quarantined in a separate PR, not patched by the fix loop.
2. **Secrets and environment variables** — a job that runs locally but fails in CI almost always means a secret or env var is missing from the repo's Actions secrets. Check Settings → Secrets and variables → Actions.
3. **Matrix failures** — if only one matrix entry fails (e.g. `test (windows-latest)` fails but `test (ubuntu-latest)` passes), the issue is OS-specific. The fix loop can't reproduce this locally without the matching OS.
4. **Runner image drift** — GitHub occasionally updates `ubuntu-latest` or `macos-latest` images, which can silently break builds. Pin to a specific image tag (e.g. `ubuntu-22.04`) if this is a recurring problem.
5. **Required status checks vs advisory** — some jobs are marked as required in branch protection rules. Failing a required check blocks merge; a failing advisory check does not. `/verify-deployment` treats all failures equally — the user decides post-escalation whether the failing check was required.

## CI is typically fast

`default_timeout_minutes: 10` — CI jobs that take longer than 10 minutes are unusual and usually mean something is wrong. If your workflow genuinely needs longer (large test matrix, slow integration tests), override in `CLAUDE.md` § Deployment Targets → `**Config:**` → `Build timeout: 20m`.

## Adapter contract note

This runbook is a "post-push check" in the loose sense — GitHub Actions isn't literally a deployment, but at the GitHub Checks API layer it's indistinguishable from Railway or Vercel. The `.claude/deployments/` directory holds adapters for any post-push check run, including CI, lint, security scans, and deploy pipelines. See `.claude/deployments/README.md` for the full contract.
