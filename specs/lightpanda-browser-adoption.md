# Lightpanda Browser Adoption

> Status: awaiting approval → `/plan`
> Brainstorm date: 2026-08-13
> Supersedes nothing. Related: `specs/deployment-verification.md` (adapter-file precedent).

---

## 1. Context

The workflow touches a browser in exactly two places today:

- `.agents/skills/start-qa/SKILL.md:90` — launches `/chrome` for **human** manual QA.
- `.agents/skills/verify-evidence/SKILL.md:105` — `--scope e2e`, which requires a real browser MCP
  (Chrome or Playwright) and hard-STOPs rather than falling back.

Unattended runs (`/auto-improve`, `/yolo`, worktree runs) execute in environments with no
desktop Chrome — a Linux personal machine, local Docker, and cloud containers, alongside a
Windows work machine. In those contexts `--scope e2e` cannot run at all, so user-facing
acceptance criteria go unverified precisely where nobody is watching.

[Lightpanda](https://github.com/lightpanda-io/browser) (Zig, AGPL-3.0, beta) is a headless
browser built for agents: libcurl + html5ever + V8 + a CDP server, ~9x faster and ~16x
lighter than headless Chrome. It ships four modes — `serve` (CDP), `fetch` (URL → HTML or
markdown), `agent`, and **`mcp`** (JSON-RPC over stdio, or `--port` for HTTP with one
browsing session per connection).

The `mcp` mode is what makes this cheap: integration is an MCP registration, not CDP
plumbing.

### 1.1 The capability ceiling (the thing that shapes the whole design)

Per [issue #1799](https://github.com/lightpanda-io/browser/issues/1799), lightpanda has:

- **No screenshots, no PDF export**
- **No Canvas / WebGL** — no visual rendering of any kind
- **Partial CSS layout** — incomplete Flexbox/Grid
- **No Web Workers, Service Workers, WebRTC**
- **Limited WebSockets**

A page with broken layout can still expose a correct DOM. Therefore a naive "use lightpanda
when Chrome is absent" fallback would let `--scope e2e` report PASS on a visually broken
feature — turning the strongest gate in the workflow into a false-confidence machine. That
is the single highest likelihood × impact failure identified in the brainstorm, and every
decision below exists to defuse it.

---

## 2. Decision

Adopt lightpanda as an **optional, capability-scoped e2e browser tier**, documented by a
runbook file, gated by a fail-closed AC classifier, and detected at runtime with a silent
no-op when absent.

**Decline agent-reach.** Its zero-config slice (Jina Reader, `gh`, RSS, V2EX, yt-dlp)
overlaps almost entirely with tools already present — built-in `WebFetch`/`WebSearch`, the
`gh` CLI, and now `lightpanda fetch` for JS-heavy pages. The unique residue is YouTube
transcripts, which is `yt-dlp` directly (Code Economy rung 3) rather than a Python CLI with
20+ transitive backends (rung 5). Declining now is reversible at zero cost.

---

## 3. Scope

### In scope

1. `.claude/browsers/lightpanda.md` — runbook: install per platform, capability ceiling,
   when not to use it.
2. `--scope e2e` gains a **browser tier resolution order** and an **AC fidelity classifier**.
3. `tasks/e2e-log.md` entries record which tier executed the walkthrough.
4. `.claude/browsers/` declared as a **syncable path** across all seven hand-maintained
   enumerations, so downstream projects actually receive the runbook and INVARIANT 2 of
   `tests/test-syncable-paths.sh` holds (see §4.9).
5. MCP registration documented in the runbook as a copy-pasteable one-liner. `install.sh` is
   **not** modified.
6. A one-paragraph note in `/prd` and `/brainstorm` research steps: when `WebFetch` returns
   an empty SPA shell, `lightpanda fetch` is an available fallback if installed.
7. Tests covering the runbook contract, the classifier's fail-closed rule, and the extended
   syncable-path set.

### Out of scope (explicit non-goals)

| Non-goal | Reason |
|---|---|
| Changing `/start-qa` | Manual QA means a human looks at the app. Lightpanda cannot render. |
| Changing the AC format in `/plan` | Classification happens at verify time; zero ripple into specs or downstream projects. |
| A general optional-capability registry | N=3 optional tools. YAGNI (Code Economy rung 1). |
| Formalizing Chrome/Playwright as `.claude/browsers/*.md` adapters | Deferred — see §9. |
| Lightpanda `serve`/CDP mode | One interface (`mcp`) is enough; CDP adds a second integration path for no gain. |
| Lightpanda `agent` mode | The workflow already has an agent driving the browser. |
| Modifying `install.sh` | It has never touched MCP config. Registration is per-harness and per-scope; documenting the command keeps the installer's blast radius unchanged. |
| Fixing `.claude/deployments/`'s identical syncable-path gap | Pre-existing. Noted in §8, out of scope per the orphan rule. |
| Adopting agent-reach | See §2. |

---

## 4. Architecture

### 4.1 Browser tier resolution (in `--scope e2e` Pre-Flight)

Resolution is ordered, first match wins:

| Order | Backend | Fidelity | Eligible ACs |
|---|---|---|---|
| 1 | Chrome MCP (`/chrome`) | Full | All |
| 2 | Playwright MCP | Full | All |
| 3 | Lightpanda MCP | DOM-tier | DOM-functional only |
| 4 | none | — | STOP |

Detection: a backend is available if its MCP tools are exposed in the session. Lightpanda is
additionally considered available if `command -v lightpanda` succeeds and the MCP server can
be started. Absence of lightpanda is **never an error** — it is the graphify convention
already stated in `CLAUDE.md`.

### 4.2 The AC fidelity classifier

For each user-facing AC extracted from the spec, `--scope e2e` assigns one of two tiers.

**VISUAL** — requires a full-fidelity backend. Triggered when the AC references:

- appearance, layout, alignment, spacing, colour, theme, dark mode, responsiveness,
  breakpoints, "looks like", "renders correctly", "above the fold"
- screenshots or visual regression
- canvas, charts, graphs, maps, or any drawn output
- hover states, animations, transitions, drag-and-drop
- print or PDF output
- realtime behaviour depending on WebSockets, Web Workers, Service Workers, or WebRTC

**DOM-FUNCTIONAL** — lightpanda-eligible. The AC is satisfiable by asserting:

- navigation and URL state, redirects, HTTP status
- form fill, submit, and validation messages as text
- authentication through the real cookie-based login flow
- presence, absence, or text content of elements
- absence of console errors

**Fail-closed rule (non-negotiable): when classification is uncertain, the AC is VISUAL.**
Uncertainty resolves toward the stricter tier, never the permissive one. This is the property
that makes the whole design safe; it must be stated verbatim in the skill.

### 4.3 Outcome matrix

| Available backend | AC tier | Result |
|---|---|---|
| Full-fidelity | any | Walk through normally |
| Lightpanda only | DOM-FUNCTIONAL | Walk through, log as DOM-tier |
| Lightpanda only | VISUAL | `Result: BLOCKED — requires full-fidelity browser` |
| None | any | STOP (existing behaviour, unchanged) |

A BLOCKED AC is **not** a PASS and **not** a step failure. It does not halt the walkthrough
(existing Iron Law 4 governs failed steps, not unrunnable ones) — remaining DOM-functional
ACs still execute, so unattended runs extract the coverage they can. But `--scope e2e`
returns non-success whenever any AC is BLOCKED, and the caller (`/build` Phase 4,
`/wrap-up-session` Step 6.3) surfaces it. Partial coverage is reported as partial coverage.

### 4.4 Relationship to the existing Iron Laws

Iron Law 1 currently reads: *"A real browser must load the real app — no jsdom, no headless
emulation bypassing the network."* Lightpanda satisfies it — it loads over libcurl and makes
real HTTP requests, unlike jsdom. The qualifier "bypassing the network" is what scopes the
rule, and lightpanda does not bypass it. This spec adds no exemption to Iron Law 1; a reader
hitting that line should find this paragraph rather than infer a contradiction, so the skill
gains a one-sentence cross-reference at that point.

Iron Law 4 (*"a failed step halts the walkthrough"*) governs **failed** steps. A BLOCKED AC
has not failed — it was never attempted. §4.3 defines that case explicitly so the two do not
get conflated.

### 4.5 Evidence

The `tasks/e2e-log.md` entry header gains one line so the audit trail records fidelity:

```markdown
## E2E Walkthrough — <Feature> — <YYYY-MM-DD> <short-sha>

Spec: specs/<feature>.md
Commit: <full-sha>
Browser: lightpanda 0.3.6 (DOM-tier)
```

Without this, a reader six months later cannot tell whether a PASS was seen or inferred.

### 4.6 Runbook contract

`.claude/browsers/lightpanda.md`, mirroring `.claude/deployments/`'s frontmatter-contract
shape:

```yaml
---
name: lightpanda
display_name: Lightpanda
fidelity: dom            # dom | full
detect_command: "command -v lightpanda"
mcp_command: "lightpanda mcp"
platforms: [linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64]
license: AGPL-3.0
---
```

Body: per-platform install (Homebrew, AUR, `.deb`, pinned release binary, Docker), the
registration one-liner, the Windows situation, the capability ceiling from §1.1, and
troubleshooting notes.

Pin an explicit release tag rather than `nightly` — `0.3.6` at time of writing — so an
upstream change to a beta project cannot silently alter unattended-run behaviour. Bumping the
pin is a deliberate edit to this file.

### 4.7 Platform reality

Lightpanda release 0.3.6 publishes only `{aarch64,x86_64}-{linux,macos}` binaries and two
`.deb` packages. **There is no Windows build.** On the Windows work machine the runbook
directs the user to WSL2 or Docker, and if neither is set up, detection simply fails and
`--scope e2e` behaves exactly as it does today. The runbook must state this plainly rather
than implying parity across machines.

### 4.9 Distribution — the syncable-path invariant

`tests/test-syncable-paths.sh` holds INVARIANT 2: *every asset path a skill names, once
resolved, must be a descendant of a declared syncable path.* Because `verify/SKILL.md` names
`.claude/browsers/lightpanda.md`, that directory must join the syncable set — otherwise the
skill instructs downstream agents to read a runbook their project never received, which is
precisely the failure the invariant was written to catch.

The syncable-path set is retyped by hand in **seven** regions across three files:

| # | Location |
|---|---|
| 1–3 | `.agents/skills/sync/SKILL.md` — § Syncable Paths block, the `git diff --stat` command, the full `git diff` command |
| 4–6 | `.claude/skills/sync/SKILL.md` — byte-identical parity copy of 1–3 |
| 7 | `.claude/hooks/session-start.sh` — the template-drift check |

All seven must gain `.claude/browsers/` in the same task; the test pins them equal, so a
partial edit fails loudly rather than drifting.

**Pre-existing gap, not fixed here**: `.claude/deployments/` has the same hole — the
`verify-deployment` skill names `.claude/deployments/<service>.md` while that directory sits
outside the syncable set, so downstream projects never receive the deployment runbooks. Noted
per the orphan rule in `.claude/project.md` § Surgical Changes; fixing it is separate work.

### 4.10 Licensing

Lightpanda is AGPL-3.0. Use the **unmodified upstream binary or Docker image**. Do not vendor,
patch, or redistribute it with this template. The runbook carries this note so the constraint
travels with the tool rather than living only in this spec.

---

## 5. Error handling

| Condition | Behaviour |
|---|---|
| Lightpanda not installed | Silent. Fall through the resolution order. Not an error. |
| Lightpanda installed, MCP server fails to start | Log the failure, fall through to "none" → STOP. Do not retry silently. |
| Lightpanda errors mid-walkthrough on an unimplemented Web API | Treat as a step failure: STOP that AC, record the API in evidence, do **not** re-classify the AC as passing. |
| Backend resolves to lightpanda but every AC is VISUAL | Report BLOCKED for all, return non-success, name the missing capability. |

No silent failures, per `CLAUDE.md`. Every degradation is either invisible-by-design
(tool absent) or explicitly reported (tool present but insufficient).

---

## 6. Testing

Bash suite, consistent with `tests/run.sh`:

1. `tests/test-browser-runbook.sh` — `.claude/browsers/lightpanda.md` exists; frontmatter
   carries every required field; `name` matches the filename; `fidelity` is `dom` or `full`.
2. `tests/test-e2e-classifier.sh` — the `verify` SKILL.md in **both** trees contains the
   resolution-order table, both tier definitions, and the fail-closed sentence verbatim.
3. `tests/test-skill-parity.sh` — unchanged, but must still pass: `verify/SKILL.md` edits
   land in `.agents/skills/` first and are copied byte-identically to `.claude/skills/`.
4. `tests/test-doc-conventions.sh` — extend token greps to cover the new runbook directory.

There is no code to unit-test here; the artifacts are prose contracts, so the tests assert
the contracts are present and internally consistent. That is the same bar the existing
`test-doc-conventions.sh` and `test-skill-parity.sh` hold.

**Known limit of this approach**: AC-4 is behavioural — "a VISUAL AC yields BLOCKED, never
PASS" — and bash tests can only assert that the rule is *written*, not that a future agent
*obeys* it. Static verification is therefore necessary but not sufficient. AC-4 additionally
requires one recorded manual walkthrough in `tasks/e2e-log.md`: a spec with one VISUAL and
one DOM-functional AC, run with lightpanda as the only backend, showing one BLOCKED and one
PASS. That walkthrough is the acceptance evidence; the bash test is the regression guard.

---

## 7. Acceptance criteria

- **AC-1** `.claude/browsers/lightpanda.md` exists with valid frontmatter per §4.5, and its
  body documents install paths, the §1.1 capability ceiling, the Windows gap, and the AGPL
  note.
- **AC-2** `--scope e2e` Pre-Flight resolves a backend using the §4.1 ordered table and treats
  a missing lightpanda as a silent no-op.
- **AC-3** `--scope e2e` classifies every user-facing AC as VISUAL or DOM-FUNCTIONAL, and the
  skill states the fail-closed rule verbatim.
- **AC-4** With only lightpanda available, a VISUAL AC yields `BLOCKED`, never `PASS`, and
  `--scope e2e` returns non-success.
- **AC-5** With only lightpanda available, DOM-functional ACs still execute and log normally.
- **AC-6** Every `tasks/e2e-log.md` entry records the backend and fidelity tier.
- **AC-7** `verify/SKILL.md` is byte-identical across `.agents/skills/` and `.claude/skills/`;
  `tests/run.sh` passes.
- **AC-8** The runbook documents the MCP registration one-liner; `install.sh` is unmodified.
- **AC-9** `.claude/browsers/` appears in all seven syncable-path enumerations, and
  `tests/test-syncable-paths.sh` passes with INVARIANT 2 satisfied for the runbook.
- **AC-10** `/start-qa` is unmodified.
- **AC-11** No file in the repo references agent-reach as a dependency.

AC-4 is the one that matters. If it regresses, the feature is a liability rather than a gap
closed.

### Verification record

Branch `feat/lightpanda-e2e-tier`, off master @ `25999b1`.

| AC | Evidence |
|----|----------|
| AC-1 | `tests/test-browser-runbook.sh` — 26 assertions |
| AC-2 | `tests/test-e2e-classifier.sh` — resolution table pinned in both trees |
| AC-3 | same — fail-closed sentence pinned **verbatim**, both trees |
| AC-4 | `tasks/e2e-log.md` — lightpanda 0.3.6 sole backend, VISUAL AC `BLOCKED` |
| AC-5 | same entry — DOM-functional AC `PASS`, JS-rendered content resolved |
| AC-6 | `Browser:` line asserted in both trees' evidence template |
| AC-7 | `tests/test-skill-parity.sh` green; both `verify/SKILL.md` byte-identical |
| AC-8 | runbook documents the one-liner; `git diff origin/master...HEAD -- install.sh` empty |
| AC-9 | `tests/test-syncable-paths.sh` green; 3 enumerations probed red then reverted |
| AC-10 | `git diff origin/master...HEAD -- .../start-qa` empty; guard pins no lightpanda reference |
| AC-11 | doc-conventions asserts no `agent-reach` token outside `specs/` |

**Suite**: 21 test files, all pass, 1395 assertions, exit 0 — run on master `8828ba0`
after rebase (baseline at branch point: 18 files).

Earlier runs of this branch reported 20 files / 19 pass / 1347 assertions, with
`tests/test-codex-install.sh` failing. That failure was pre-existing on master and
Windows-only, reproduced at `0064efe` without this branch's commits, and is now **resolved
upstream** by #66 (a `$PPID`-keyed guard collapsing to PID 1 on Windows, then `print()`
encoding the non-ASCII banner as cp1252) and #67 (explicit UTF-8 at the remaining Python
IO boundaries). Recorded rather than deleted: this branch was verified against a red
baseline for most of its life, and that is a fact about the evidence above.

### What the AC-4 run changed

The evidence run did not merely confirm the design — it sharpened it. Geometry APIs are
**stubbed rather than absent**: `getBoundingClientRect()` returns every element as `5x5`
with `x == y`, ignoring CSS entirely. So a defensively written visibility check
(`r.width > 0 && r.x >= 0`) returns *true* for an element positioned 9999px off-screen.

This is materially worse than §1.1's original "no rendering path" framing. A missing API
throws where its caller notices; a stubbed one answers wrong in silence, leaving no runtime
signal to fail on. That is the concrete reason the classifier must decide **before**
execution rather than attempting a visual check and letting it fail. The runbook and
`tests/test-browser-runbook.sh` both carry this finding.

---

## 8. Open risks carried forward

| Risk | Mitigation | Residual |
|---|---|---|
| Lightpanda is beta; nightly changes break unattended runs at 3am | Pin to a release tag in the runbook, not `nightly` | Medium — upgrades need a deliberate bump |
| Machine-dependent code paths (Windows vs Linux) cause bugs that reproduce on one box only | The e2e-log records the backend, so divergence is visible in the audit trail | Medium |
| Classifier drifts toward permissive over time as BLOCKED results get annoying | Fail-closed rule stated verbatim and asserted by a test | Low |

---

## 9. Deferred

- **Browser adapters as a directory.** If a fourth backend appears, promote `.claude/browsers/`
  to a full adapter contract with `chrome.md` and `playwright.md`, and let `--scope e2e` read
  the directory instead of hardcoding the order — exactly what `.claude/deployments/` does for
  services. Not now: three backends do not justify the indirection.
- **agent-reach.** Revisit if research needs shift toward video or social content. Adopt
  `yt-dlp` alone first if only transcripts are needed.
- **Lightpanda `fetch` as a first-class research tool.** Starts as a documented option in
  `/prd` and `/brainstorm`; promote to a defined step only if it proves load-bearing.
