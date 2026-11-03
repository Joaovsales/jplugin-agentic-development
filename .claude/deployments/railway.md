---
name: railway
display_name: Railway
detect_files:
  - railway.json
  - railway.toml
  - .railway/
status_source: github-checks
check_contexts:
  - Railway
  - railway/deployment
auth_check_command: railway whoami
cli_status_command: railway status --json
log_fetch_command: railway logs --deployment {deployment_id}
dashboard_url_template: https://railway.app/project/{project_id}
default_timeout_minutes: 15
common_failure_patterns:
  - match: "npm ERR! peer dep"
    hint: "Peer dependency mismatch — check package.json versions and consider running `npm install --legacy-peer-deps` locally to reproduce"
  - match: "Nixpacks build failed"
    hint: "Nixpacks couldn't infer the build steps — set `build.builder` and `build.buildCommand` explicitly in railway.json"
  - match: "ECONNREFUSED"
    hint: "Build code tried to reach a network service. Check for top-level `await` on a database/HTTP call running at import time"
  - match: "Module not found"
    hint: "Missing dependency or stale lockfile. Verify the package is in dependencies (not devDependencies) and the lockfile is committed"
  - match: "Healthcheck failed"
    hint: "Container starts but fails Railway's healthcheck — verify `healthcheckPath` in railway.json points at a real route that returns 200 fast"
---

# Railway Deployment Runbook

Railway publishes commit check runs against the GitHub SHA on every deploy, so the preferred polling path is GitHub Checks. The CLI fields (`cli_status_command`, `log_fetch_command`) are kept as a fallback for projects that disable Railway's GitHub integration.

## Manual troubleshooting

When `/verify-deployment` exhausts its 3 fix iterations and escalates, walk this list:

1. **Environment variables** — missing or stale env vars are not visible in build logs but break runtime healthchecks. Check the Railway dashboard → Variables tab against what the app reads on boot.
2. **Service dependencies** — Railway only rebuilds the service whose code changed. If your monorepo has sibling services (worker, scheduler, etc.) that share types or schemas, redeploy them too.
3. **Build vs deploy logs** — compilation can pass and the container can still fail to start. Open the failing deployment in the dashboard and check the **Deploy Logs** tab, not just **Build Logs**.
4. **Healthcheck path** — the app may serve traffic but the healthcheck route can be wrong, slow, or behind auth. Default expectation: `GET /` returns 200 within 30 seconds of container start.
5. **Region / volume mounts** — recently moved between regions or attached/detached a volume? Builds succeed but the container can't find its mount point.
6. **Resource limits** — OOM during build is sometimes silent. Check the deployment's metrics tab for memory spikes near build completion.

## Required setup on the project

For `auth_check_command` to pass locally, the developer running `/verify-deployment` needs either:

- A logged-in Railway CLI session (`railway login` once), **or**
- `RAILWAY_TOKEN` exported in the shell environment

For the GitHub Checks path to work, the Railway → GitHub integration must be enabled on the repo (Railway dashboard → Project Settings → GitHub).

## Dashboard URL

The `dashboard_url_template` interpolates `{project_id}` from the `Project ID` column of `AGENTS.md` § Deployment Targets. Example: if the table row says `my-api-prod`, the escalation message will link to `https://railway.app/project/my-api-prod`.
