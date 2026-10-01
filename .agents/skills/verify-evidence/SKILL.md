---
name: verify-evidence
description: Enforce evidence-based verification before any completion claims. Supports --scope deployment and --scope e2e. Use before committing, creating PRs, marking tasks done, or claiming success.
argument-hint: "[--scope deployment|e2e]"
harness: universal
---

# /verify-evidence — Verification Before Completion

## Overview

Claiming work is complete without verification is dishonesty, not efficiency. Every claim of success must be backed by fresh, direct evidence obtained in the same message as the claim. Memory of a previous run is not evidence. Confidence is not evidence. Only output from a command you just ran is evidence.

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

---

## Default Mode (no flag)

Before making any completion claim, execute every step in sequence:

1. **IDENTIFY**: What command proves this claim? Name it explicitly before running anything.
2. **RUN**: Execute the FULL command — no truncation, no partial scope, no skipped phases.
3. **READ**: Read the complete output. Check the exit code. Count failures. Do not skim.
4. **VERIFY**: Does the output confirm the claim?
   - If NO: State the actual status with evidence. Do not claim completion.
   - If YES: State the claim WITH supporting evidence (exit code, test counts, output excerpt).
5. **ONLY THEN**: Make the claim.

Skip any step = lying, not verifying.

### Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Full test suite with 0 failures and exit code 0 | Partial suite run, running only the new test |
| Linter clean | Linter on all changed files with 0 errors | Assuming no lint errors |
| Build succeeds | Build command exits 0 with no errors | Previous build succeeded |
| Bug fixed | Reproduction test passes AND full suite green | Reading the fix and concluding it's correct |
| Requirements met | Each AC mapped to passing test or demonstrated behavior | Reviewing the spec and believing it matches |

### Red Flags — STOP

- Using "should", "probably", "seems to", "likely", or "appears to" in a completion statement
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit or push without a fresh test run in the same message
- Trusting an agent's success report without independently running verification commands
- Relying on partial verification

---

## `--scope deployment`

Wait for post-push deployment builds to resolve. On failure, fetch logs, fix, push, and loop. Maximum 3 fix iterations per service before escalation.

This scope is **service-agnostic** — all service-specific behavior comes from runbook files in `tasks/deployments/<service>.md`.

### Pre-Flight

1. Run `git status --porcelain`. If any output: STOP — uncommitted changes must be resolved first.
2. Locate the routing table: look for `^## Deployment Targets[[:space:]]*$` in `AGENTS.md`; no match there, look in `.claude/project.md` and, on a match, print `Deployment Targets found in .claude/project.md — /sync will move them to AGENTS.md` (Claude Code only). `CLAUDE.md` is the `@AGENTS.md` pointer and is not searched.
3. Resolve: `git rev-parse HEAD` (current SHA), `git rev-parse --abbrev-ref HEAD` (branch), confirm remote exists.
4. Filter: keep only target rows whose `Triggers on branch` matches the current branch. If empty: skip silently.

### Per-Target Verification

For each applicable target:

**A. Load and validate the runbook** from `tasks/deployments/<service>.md`. Required fields: `name`, `display_name`, `detect_files`, `status_source`, `auth_check_command`, `dashboard_url_template`, `default_timeout_minutes`.

**B. Auth check**: run `auth_check_command`. If non-zero: mark `AUTH_FAILED`, move to next target.

**C. Poll for build status**:
- `github-checks` path: poll `mcp__github__get_commit`, filter by `check_contexts`, wait for all to succeed
- `cli` path: run `cli_status_command`, parse `state` or `status` field
- Poll intervals: 15s for first 2min, then 30s. Timeout per runbook config.
- Transient errors retry at polling layer (5s → 10s → 20s backoff). Don't consume a fix iteration.

**D. Fix loop** (max 3 iterations on failure):
1. Fetch logs (via `log_fetch_command` or `details_url`)
2. Match `common_failure_patterns` hints
3. Diagnose and apply fix in main context
4. Commit fix as NEW commit: `fix(deploy): <summary> [deploy-retry N/3]`
5. Push and restart poll

**E. Escalation**: after 3 failed iterations, write `tasks/deploy-report.md` and mark `FAILED_MAX_ITERATIONS`.

### Outcomes

| State | Action |
|-------|--------|
| `ALL_GREEN` | Proceed, record attempt counts |
| `AUTH_FAILED` | STOP — report which auth check failed |
| `TIMEOUT` | STOP — report dashboard URL, ask user |
| `CANCELLED` | STOP — ask user whether to proceed |
| `FAILED_MAX_ITERATIONS` | STOP — point to `tasks/deploy-report.md` |
| `SKIPPED` | Proceed |

---

## `--scope e2e`

Force end-to-end browser validation of user-facing acceptance criteria.

Unit tests prove functions work. E2E walkthroughs prove features work.

### Pre-Flight

1. Read the active spec from `specs/` and extract **user-facing ACs**
2. Classify every AC before selecting a driver or backend
3. Resolve a project-local verification skill, then resolve its compatible
   driver or the generic browser backend (below)
4. Launch and diagnose the app using the selected local recipe, or `/start-qa`
   when using the generic fallback
5. Load authentication state as a real user would — cookie-based session, not injected tokens

### Project-local verification skill resolution

Discover `verify-*` entries in the canonical `.agents/skills/` tree; a project-local
copy left under `.claude/skills/` from before the plugin is a mirror, not a candidate.

- With **exactly one project-local `verify-<app>` skill**, read it and use its
  grounded Launch, Doctor, Drive, Evidence, Cleanup, and Helpers contract. Its
  declared surface and capability ceiling must satisfy the classified AC. A
  local recipe selects *how* to drive the app; it never relaxes the classifier.
- With **more than one project-local `verify-<app>` skill**, STOP and ask which
  application is in scope. List the candidates and do not choose one.
- With **no project-local `verify-<app>` skill**, recommend
  `/create-verification-skill`, then continue through the unchanged generic
  backend resolution below. This is a recommendation only: never create or
  launch it automatically.

If the selected local skill's capability ceiling is below an AC's tier, use a
compatible higher-fidelity backend when the recipe permits it; otherwise record
`BLOCKED`. A DOM-only local driver cannot pass a VISUAL AC.

For a non-browser surface, follow the local skill's Drive contract without
requiring a browser backend. For a browser surface, resolve the recipe's compatible
driver first. When there is no local skill, use the generic order below exactly
as before.

### Backend resolution

Ordered; first available wins.

| Order | Backend | Detected by | Fidelity | Screenshot | Eligible ACs |
|-------|---------|-------------|----------|------------|--------------|
| 1 | Playwright CLI | `command -v playwright-cli` | full | file | all |
| 2 | Chrome MCP | its MCP tools exposed in the session | full | session id | DOM-FUNCTIONAL only |
| 3 | Lightpanda MCP | its MCP tools exposed in the session | DOM only | none | DOM-FUNCTIONAL only |
| 4 | none | — | — | — | STOP |

The Playwright CLI is a shell command, not an MCP server, so every harness —
Claude Code, Codex, Pi — drives it the same way with no registration; never
substitute `@playwright/mcp`. It goes first because it is the only backend whose
screenshot is a file, and a VISUAL PASS needs its PNG on disk. A missing
backend is never an error — fall through. The runbooks, including each
capability ceiling, are `.claude/browsers/playwright-cli.md` and
`.claude/browsers/lightpanda.md` (Claude Code only — other harnesses read the
same runbooks from the template repo).

### AC classification

Classify each user-facing AC **before** walking it. The tier decides which
backends may run it.

**VISUAL** — needs a full-fidelity backend. The AC references appearance, layout,
alignment, spacing, colour, theme, dark mode, responsiveness or breakpoints;
"looks like" or "renders correctly"; screenshots or visual regression; canvas,
charts, maps or drawn output; hover, animation, transition or drag-and-drop;
print/PDF output; or realtime behaviour depending on WebSockets, Web Workers,
Service Workers or WebRTC.

**DOM-FUNCTIONAL** — lightpanda-eligible. The AC is satisfied by asserting
navigation and URL state, redirects and HTTP status, form fill/submit and
validation messages as text, authentication through the real login flow,
presence/absence/text of elements, or absence of console errors.

> **Fail closed: when classification is uncertain, the AC is VISUAL.**
> Uncertainty resolves toward the stricter tier, never the permissive one. A page
> with broken layout still exposes a correct DOM, so guessing DOM-FUNCTIONAL
> converts a missing check into a green one — the single failure this tier
> system exists to prevent.

### Outcome matrix

| Backend available | AC tier | Result |
|---|---|---|
| Playwright CLI | any | walk through normally |
| Chrome MCP only | DOM-FUNCTIONAL | walk through normally |
| Chrome MCP only | VISUAL | `BLOCKED` — **never** `PASS` |
| lightpanda only | DOM-FUNCTIONAL | walk through, log as DOM-tier |
| lightpanda only | VISUAL | `BLOCKED` — **never** `PASS` |
| none | any | STOP |

A `BLOCKED` AC has not failed — it was never attempted — so it does not halt the
walkthrough, and the remaining DOM-functional ACs still execute. But any run
containing a `BLOCKED` AC reports **non-success** to its caller (`/build` Phase 4,
`/wrap-up-session` § *E2E coverage*). Partial coverage is reported as partial coverage.

### Walkthrough Protocol

For a changed browser UI, require a committed executable
`tests/visual/<feature>.sh` or a committed equivalent project suite grounded
in the project verification skill. Run it locally through
`scripts/visual_check.py`'s `run_visual_check(project, feature,
changed_states, output)` contract. The script launches the real app, drives
every changed route/state through Playwright CLI, checks interactions and
console errors, captures desktop and mobile PNGs after reaching each state,
and writes `manifest.json` in `JPLUGIN_UI_OUTPUT`. The manifest's `states`
map gives each state `desktop`, `mobile`, `interactions: true`,
`console_errors: []`, and `visual_disposition: pass`. The validator checks
all changed states and capture files. Keep the local run output for review.
Missing CLI/Chromium, app launch failure, broken interaction, console error,
missing viewport or unresolved visual defect blocks UI completion; report the
exact command or state. A browser fixture that only writes PNG headers is
test evidence for the validator, never a production walkthrough.

For each user-facing AC:

1. **Describe the user journey** in plain language
2. **Execute each step in the real browser** through the backend — `playwright-cli` commands or MCP tool calls: navigate, click, type, submit, wait
3. **Assert observable state**: URL, required text/elements, network status, no console errors
4. **Negative path check**: at least one failure variant per AC

### Evidence Format

When the project tracks tasks externally, attach the evidence link to the task
through `/task-registry` (`show <task-id>` to confirm it landed). Never post to
the tracker directly — the evidence field is part of the normalized task
record, so it survives a change of tracker.

Append to `tasks/e2e-log.md`:

```markdown
## E2E Walkthrough — <Feature Name> — <YYYY-MM-DD> <short-sha>

Spec: specs/<feature>.md
Commit: <full-sha>
Browser: <backend> <version> (full-fidelity | DOM-tier)

### AC-1: <criterion text>
Tier: DOM-FUNCTIONAL (asserts element text)
Journey: <plain-language steps>
Steps executed:
  ✓ Navigate /path → 200, element visible
  ✓ Fill form, submit → 302 redirect
  ✓ Assert session state
Negative: invalid input rejected with inline error ✓
Result: PASS

### AC-2: <criterion text>
Tier: VISUAL (references layout)
Journey: <plain-language steps>
Result: PASS
Screenshot: tasks/e2e-artifacts/<short-sha>/<AC-id>.png

### AC-3: <criterion text>
Tier: VISUAL (references layout)
Result: BLOCKED — requires a full-fidelity browser; only lightpanda (DOM-tier) available
```

Every VISUAL `PASS` carries a `Screenshot:` line naming a PNG the backend wrote
**after** the walkthrough reached the state the AC describes — one per VISUAL
AC, no "before" shot. DOM-FUNCTIONAL entries need none, though one is allowed
when the backend can take it. `tasks/e2e-artifacts/` is gitignored; the PNGs
reach the PR through the `e2e-evidence` branch at `/wrap-up-session`, never
through the feature branch. `python3
.agents/skills/verify-evidence/scripts/e2e_evidence.py check [--log <path>]
[--sha <short-sha>]` refuses every VISUAL PASS whose line or file is missing,
naming the entry and AC; it is silent and exits 0 when all are present.

The log is **append-only**. Never overwrite prior walkthroughs — they form the audit trail.

### Failure Handling

For a practical obstacle, return a **structured blocked outcome** containing the
exact failing command or walkthrough step, retained evidence (or why none is
available), and whether reproduction was already confirmed. The caller owns the
policy response. `/verify-evidence` must not invoke `task-registry escalate`; this avoids
two reports for one failure. A completed check that finds a defect is a failed
verification and returns through the existing debug/build repair loop.

- **Step fails**: STOP, report exact step + evidence, hand back to `/build` or `/debug`
- **No backend (`playwright-cli` absent, MCP browser unavailable)**: STOP. Do not fall back to curl or unit tests.
- **`playwright-cli` present, its Chromium missing**: a step failure naming
  `playwright-cli install-browser chromium` — never a silent drop to Chrome MCP
- **VISUAL AC, only a DOM-tier backend**: record `BLOCKED`, continue with the
  remaining DOM-functional ACs, report the run as non-success
- **VISUAL AC, only Chrome MCP**: record `BLOCKED` — requires a file-capable
  full-fidelity browser, since Chrome MCP's screenshots are session ids, not
  files; the DOM-functional ACs still run on it; report the run as non-success
- **DOM-tier backend errors on an unimplemented Web API**: treat as a step
  failure and name the API in evidence. Never re-classify the AC as passing —
  the gap is real and the feature was not verified
- **Auth fails twice**: STOP, report to user — this is usually a session misconfiguration
- **Dev server unreachable**: STOP, invoke `/start-qa`, then resume

### Iron Laws

1. A real browser must load the real app — no jsdom, no headless emulation bypassing the network.
   A DOM-tier backend satisfies this: lightpanda loads over **libcurl** and makes real HTTP
   requests, unlike jsdom. "Bypassing the network" is what the law forbids, and it does not.
   What it cannot do is *see* the result — which the classifier handles, not this law.
2. Authentication must go through the real login flow — no token injection
3. Every user-facing AC gets its own walkthrough entry — no batching
4. A failed step halts the walkthrough — do not cascade to the next AC
5. Evidence is the `tasks/e2e-log.md` entry — if the entry doesn't exist, the walkthrough didn't happen,
   and a VISUAL PASS without its PNG on disk is not a PASS

---

## Integration

- **Default mode required by**: `/build` (after each task and in Phase 4), `/debug` (Phase 3), `/wrap-up-session` (§ *Full suite*)
- **`--scope e2e` invoked by**: `/build` Phase 4 (user-facing ACs), `/wrap-up-session` § *E2E coverage*
- **Project recipe maintained by**: `/maintain-verification-skill --scope changed`
- **`--scope deployment` invoked by**: `.agents/skills/wrap-up-session/references/closure-actions.md` § *Deployment verification*
