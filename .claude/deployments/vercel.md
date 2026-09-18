---
name: vercel
display_name: Vercel
detect_files:
  - vercel.json
  - .vercel/
  - .vercelignore
status_source: github-checks
check_contexts:
  - Vercel
  - Vercel – Preview
  - Vercel – Production
auth_check_command: vercel whoami
cli_status_command: vercel inspect --json
log_fetch_command: vercel inspect {deployment_id} --logs
dashboard_url_template: https://vercel.com/{project_id}
default_timeout_minutes: 15
common_failure_patterns:
  - match: "Type error:"
    hint: "TypeScript compilation failed in the Vercel build. Run `tsc --noEmit` locally with the same Node version Vercel is using to reproduce"
  - match: "Module not found: Can't resolve"
    hint: "Import path resolves locally but not in CI. Most common causes: case-sensitive filename mismatch (Linux), missing dependency, or alias not configured in tsconfig paths"
  - match: "Function exceeds maximum size"
    hint: "Serverless function bundle is over Vercel's 50MB limit. Move heavy deps behind dynamic imports or split the function"
  - match: "ENOENT"
    hint: "Build is reading a file that exists locally but isn't tracked or isn't in the build output. Check .vercelignore and the includeFiles config"
  - match: "Build exceeded maximum duration"
    hint: "Build is over the 45-minute hard limit. Profile with `vercel build --debug` locally and look for hanging post-build scripts"
  - match: "Environment Variable .* references Secret .* which does not exist"
    hint: "Vercel project is missing a secret referenced in vercel.json or env config — add it via the dashboard before retrying"
---

# Vercel Deployment Runbook

Vercel publishes commit check runs against the GitHub SHA on every deploy, separately for Preview and Production. The preferred polling path is GitHub Checks. The CLI fields (`cli_status_command`, `log_fetch_command`) are kept as a fallback for projects that disable the GitHub integration or run direct CLI deploys.

**Multi-context note**: Vercel typically publishes more than one check run per commit (Preview + Production). `/verify-deployment` waits for **all** matching contexts to resolve and fails if any of them fails.

## Manual troubleshooting

When `/verify-deployment` exhausts its 3 fix iterations and escalates, walk this list:

1. **Environment variables** — Vercel scopes env vars to Development / Preview / Production. A var that exists in Preview but not Production will pass preview builds and fail prod. Check the dashboard → Settings → Environment Variables.
2. **Build output directory** — `vercel.json` `outputDirectory` mismatch causes the build to succeed but produce nothing to deploy. Default is `.next` for Next.js, `dist` for most others.
3. **Node version drift** — Vercel uses the version pinned in `engines.node` (package.json) or the project's framework default. Local Node version mismatch is a frequent cause of "works locally, fails on Vercel".
4. **Edge runtime constraints** — Functions declared with `export const runtime = 'edge'` can't use Node-only APIs (`fs`, `path`, native modules). The error message often points at the importing file but the actual culprit is a transitive dep.
5. **ISR / caching** — A successful build can still produce a broken site if ISR is misconfigured. Check the deployment's Functions tab for revalidation errors.
6. **Monorepo root directory** — In a monorepo, Vercel needs the `Root Directory` setting in the project config. Wrong root → "Cannot find package.json" with no other useful info.

## Required setup on the project

For `auth_check_command` to pass locally, the developer running `/verify-deployment` needs:

- A logged-in Vercel CLI session (`vercel login` once), **or**
- `VERCEL_TOKEN` exported in the shell environment

For the GitHub Checks path to work, the Vercel → GitHub integration must be enabled on the repo (Vercel dashboard → Project Settings → Git).

## Dashboard URL

The `dashboard_url_template` interpolates `{project_id}` from the `Project ID` column of `.claude/project.md` § Deployment Targets. For Vercel, `{project_id}` should be `<team-or-username>/<project-name>` (e.g. `acme/marketing-site`) so the resulting URL points at the project page.
