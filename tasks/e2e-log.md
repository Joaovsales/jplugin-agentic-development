# E2E / Evidence Log

> Append-only. Never overwrite prior entries — they form the audit trail.

---

## Downstream Delivery — worktree-bootstrap distribution — 2026-08-17 2820378

Spec: specs/worktree-bootstrap-distribution.md (AC8)
Commit: 282037822a7b946726d6506a097d43edbfce1ef0
PR: https://github.com/Joaovsales/coding-agent-workflow/pull/65

**AC8** — Downstream reachability of `bootstrap-worktree.sh` demonstrated, not asserted.

### (a) The script is an incoming file over `/sync`'s syncable path list

Diffed the branch against `origin/master` restricted to the declared syncable paths —
the same argument list `/sync` and the `session-start.sh` drift check use:

```
git diff --name-only origin/master fix/distribute-worktree-bootstrap -- \
  .agents/skills .agents/agents .claude/skills .claude/agents \
  .claude/hooks .claude/settings.json CLAUDE.md
```

11 files, including both copies of the script:

```
.agents/skills/build/scripts/bootstrap-worktree.sh
.claude/skills/build/scripts/bootstrap-worktree.sh
```

Before this change the script lived at `scripts/bootstrap-worktree.sh` and this same
command returned nothing for it — the file was invisible to `/sync` while four skills
instructed agents to run it. The remaining three files in the commit
(`specs/`, `tests/`, `project-template/.gitattributes`) correctly do **not** appear:
they are outside the syncable set by design.

### (b) `install.sh`'s `cp -r .agents/*` delivers it executable

Copied `.agents/*` into a scratch directory standing in for `~/.agents`:

```
-rwxr-xr-x  3728  fake-home-agents/skills/build/scripts/bootstrap-worktree.sh
```

Git index mode — the meaningful check on Windows, where the filesystem bit is not
authoritative — is `100755` on both trees, same blob:

```
100755 a3afbd4d118c08bd011b593d0f8ff87bbbc15f6e 0  .agents/skills/build/scripts/bootstrap-worktree.sh
100755 a3afbd4d118c08bd011b593d0f8ff87bbbc15f6e 0  .claude/skills/build/scripts/bootstrap-worktree.sh
```

### (c) It executes from the delivered location

Invoking the copy under the scratch `~/.agents` reached its `git worktree add` call and
was rejected by git on the argument, not by the shell on the file — proving the delivered
copy is runnable rather than merely present. `bash -n` reports clean syntax.

Result: PASS

### Environment note

`bash tests/run.sh` locally: 17/18 files pass. `tests/test-codex-install.sh` →
*"SessionStart output validates as Codex JSON"* fails on Windows only, and is
**pre-existing on master** — reproduced at `0064efe` in a clean detached worktree without
this commit. Cause: Python 3.13 on Windows defaults to cp1252, so `json.loads` raises
`UnicodeEncodeError` on the hook banner's non-ASCII characters before parsing. CI (Linux)
reports the full suite green for this commit.

---

## E2E Walkthrough — Lightpanda DOM tier — 2026-08-17 ad475ec

Spec: specs/lightpanda-browser-adoption.md (AC-4, AC-5)
Commit: ad475ec82e926db24ee98217bf654ed6db0432d7
Browser: lightpanda 0.3.6 (DOM-tier) — Docker `lightpanda/browser:0.3.6`, sole backend

**AC-4/AC-5** — with only a DOM-tier backend available, a VISUAL AC yields BLOCKED
and never PASS, while DOM-functional ACs still execute.

### Fixture

A checkout page served by nginx over a private Docker network (real HTTP, no host
port). Two deliberate properties:

- `#total` is filled in by JavaScript after load.
- `#submit-btn` is present and correctly labelled, but styled
  `position:absolute; left:-9999px; top:-9999px` — **DOM-correct, visually absent.**

### AC-1: "the order total is displayed on the checkout page"
Tier: DOM-FUNCTIONAL (element text content)
Journey: load the page, assert the total resolves after scripts run.

Raw HTTP, i.e. what `WebFetch` sees:
```
<p id="total">loading…</p>
```

Lightpanda `fetch --dump html`:
```
<p id="total">Order total: $42.00</p>
```

The scripts ran against a real network fetch — the distinction Iron Law 1 turns
on. Result: **PASS**

### AC-2: "the submit button is visible on the checkout form"
Tier: VISUAL (visibility is a rendering property)
Result: **BLOCKED** — requires a full-fidelity browser; only lightpanda (DOM-tier) available

Not attempted. Recorded as BLOCKED, so the run reports non-success while AC-1's
coverage is kept.

### Why BLOCKED rather than attempted-and-checked

The reflex is to attempt it defensively and let the check fail. Probing the
backend shows why that does not work — geometry is **stubbed, not missing**:

```
submit-btn=[110,110,5,5]  total=[130,130,5,5]  checkout=[80,80,5,5]  h1=[65,65,5,5]
```

Every element reports 5x5 with x == y; an `<h1>` and a `<button>` are not the same
size, and the `left:-9999px` offset is ignored entirely. So the careful assertion

```js
const r = el.getBoundingClientRect();
if (r.width > 0 && r.x >= 0) { /* "visible" */ }
```

**returns true for an element 9999px off the left edge.** A missing API throws and
its caller notices; a stubbed one answers wrong in silence. There is no runtime
signal to fail on, so the tier must be decided before execution — which is what
fail-closed classification does.

Method note: the first geometry probe returned nothing and could have been read
as "API absent". A control run showed `console.log` output does not reach stdout
in `fetch` mode — the probe was faulty, not the API. The values above were
re-obtained by writing results into the DOM, which the dump captures. An empty
result is not evidence of absence.

Result: PASS (AC-4 and AC-5 both satisfied)

### Addendum — 2026-08-18: commit reference rebased

The `Commit:` line above records `ad475ec82e926db24ee98217bf654ed6db0432d7`, the SHA
this branch carried when the walkthrough ran. The branch was later rebased onto master
`8828ba0` to pick up #66/#67/#68, so that SHA is unreachable and `git show` on it fails.
The same content is now `c91ae4a` ("feat(research): offer lightpanda fetch for
JS-rendered pages; guard the decisions").

Corrected by addendum rather than by editing the line above: the log is the audit trail,
and an entry silently rewritten to look as though it always pointed at the right commit
is worth less than one that shows what moved. Nothing about the run itself changed — same
fixture, same `lightpanda/browser:0.3.6` image, same observed values.

---

## 2026-09-05 — Deterministic retirement in `/sync`

Spec: `specs/sync-deterministic-retirement.md`
Branch: `Joaovsales/sync-is-non-deterministic-retired-vs-project-spe`
Commit: recorded at commit time (see the `test(sync)` commit adding §21)
Harness: `tests/test-sync-retirement.sh` §21, run under `bash tests/run.sh`

### Why a walkthrough was needed

Sections 1–20 all invoke the script as `python3 "$RETIRE"` — the copy on disk in
this repo. `SKILL.md` Steps 3 and 6.4 do not. They pipe the script **out of the
template ref** into `python3 -`, so a downstream `/sync` runs whatever the
template ships, read from stdin, against the project. No assertion covered that
form, so a script that worked from a file and failed from stdin would have passed
the entire suite.

### What was exercised, verbatim from the skill

A fixture project with the template as a `workflow` remote (as Step 1 leaves it),
the template carrying its own copy of `sync-retire.py`, and a real retirement in
the template's history (`.agents/skills/legacy/` shipped, then removed).

1. **Step 3 dry run** — `git show workflow/main:.agents/skills/sync/scripts/sync-retire.py | python3 - --from-ref workflow/main`
   → exit 0; reported `retire: .agents/skills/legacy/SKILL.md`; reported
   `dry-run (no changes written)`; **deleted nothing**. Reading the program from
   stdin does not imply `--apply`.
2. **Step 6.4 apply** — same pipeline with `--apply`
   → exit 0; `.agents/skills/legacy/SKILL.md` deleted; `.agents/skills/ours/SKILL.md`
   (project-specific, no provenance) untouched; `.claude/sync-keep.candidate` written
   for the human to promote.

### The `set -o pipefail` claim, tested rather than trusted

`SKILL.md` warns that without `pipefail` a failed `git show` feeds `python3 -` an
empty program which exits 0, silently skipping the retirement gate. That warning
is now verified rather than asserted:

- without `pipefail`, `git show` on a non-existent path → **exit 0, no output at all**
- with `pipefail`, the same pipeline → **exit 128**, git's failure reaching the caller

The warning is accurate and the guard is load-bearing.

Result: PASS — both user-facing acceptance criteria ("a file retired upstream is
removed without a human classifying it" and "a project-only path is reported
before deletion, never deleted silently") verified through the invocation a real
`/sync` executes, not a test-only one.
## Integration Proof — category routines spine — 2026-09-05 (branch `analysis/simplify-routing`, uncommitted)

Spec: specs/category-routines.md (AC3, AC5, AC12; composition of spine steps 1-3)
Base: c3809a1

**Not a formal E2E walkthrough.** This repository still has no project-local
`verify-<app>` skill and no browser-backed user surface, so `/verify --scope e2e`
cannot produce one — the same condition recorded in
`tasks/solutions/process/issue-lane-routing-e2e-gap.md` on 2026-09-01. This entry
is integration evidence against the `gh` mock and is labelled as such.

### What ran

The adversarial review pass found that no test exercised the routine spine as a
**composition** — only the parser, the selector function, the vocabulary, and the
prose, never steps 1-3 together. With the `claim` subcommand now shipped, they
compose:

```
step 1  task-registry select --routine fix
          candidate:     77 — Crash on cold start
          matched label: bug
step 2  task-registry claim 77 --routine fix --apply --approve
          claim: wrote in-progress to 77 for routine fix
          gh call: --add-label in-progress
step 3  routine_branch.py format fix 77 "Crash on cold start"
          routine/fix/77-crash-on-cold-start
step 5  routine_branch.py parse routine/fix/77-crash-on-cold-start
          fix 77   (exit 0)
```

The branch is the only channel carrying routine+issue into wrap-up, and it
round-trips: what step 3 wrote, step 5 read back.

### Residual gap, stated rather than closed

No routine has run under a real host. `build` is deferred (#97/#98) and
`/auto-improve` does not execute the spine — it neither calls `select` nor creates
a `routine/` branch. So AC6, AC7 and AC9 (draft-only-for-plan, `Closes #N`
linkage, and the step ledger in the PR body) are verified as **documentation
contracts**, not as observed artifacts. Closing that needs a routine host, which
is #98's subject.

Result: PASS for the composition above; the host-level gap is recorded, not
claimed as covered.

## Integration Proof — task-tracking pointer states (#82) — 2026-09-06 (branch `Joaovsales/task-tracking-config-a-pointer-to-a-missing-file`, uncommitted)

Spec: `specs/task-registry.md` (one-line note under configuration discovery).
The surface is the CLI alone — `task-registry doctor` and the refusal preamble of
every other command — so the walkthrough is six throwaway projects run through
the real script, not a browser session.

### What ran

| project | pointer | `doctor` configuration line | `doctor` exit |
|---|---|---|---|
| none | no pointer, no default file | `none (defaults + local fallback)` | 0 |
| ok | `CLAUDE.md` → existing `docs/tracking.md` | `docs/tracking.md` | 0 |
| missing | `CLAUDE.md` → absent `docs/tracking.md` | `BROKEN — CLAUDE.md declares \`Task tracking instructions: 'docs/tracking.md'\`, but 'docs/tracking.md' does not exist — create it from .agents/skills/task-registry/templates/task-tracking.md, or remove the pointer` | 1 |
| dir | `CLAUDE.md` → `docs` (a directory) | `BROKEN — … 'docs' exists but is not a file — …` | 1 |
| prose | `.claude/project.md` sentence ending `docs/tracking.md.` with the file present | `docs/tracking.md` | 0 |
| escape | `AGENTS.md` → `../../etc/passwd` | `BROKEN — AGENTS.md: task tracking pointer '../../etc/passwd' resolves outside the project root — refusing to use it` | 1 |

Every BROKEN diagnosis is followed by `Every command except this one refuses to
run until it is fixed.`, and `reconcile` on the *missing* project exits 1 with the
same sentence on stderr, prefixed `task-registry:`. This repository itself
reports `none`, exit 0 — `CLAUDE.md` no longer carries a live pointer.

### Result

PASS. AC1 (distinguishable, names path and declaring file), AC2 (no pointer stays
silent), AC3 (template `CLAUDE.md` emits no parseable pointer) observed directly;
AC4–AC6 are the test suite (`tests/test-task-registry.sh` "Pointer states",
`tests/test-doc-conventions.sh`, `bash tests/run.sh` 36/36). Residual gap, stated:
a pointer to a file that exists but has no ` ```ini ` block still tracebacks under
`doctor` — pre-existing on `master`, unchanged here, and the non-strict docstring
now says so rather than claiming otherwise.

---

## E2E Walkthrough — task-registry legacy-row publication — 2026-09-06 51afded

Spec: no spec — the user explicitly waived the redundant `/plan` gate for bug #90
Commit: working tree based on `51afded886851c6e2c9b49bf64a6c8967a94b7fe`
Browser: not applicable — non-browser CLI integration
Harness: `tests/test-task-registry.sh`, invoking the real task-registry CLI against
an isolated repository and fake `gh` process boundary

### AC-1: A multi-line legacy row preserves its detail in the provider body

Tier: CLI-FUNCTIONAL
Journey: parse a migrated-shaped TDD row, invoke publication rendering, and inspect
the body passed across the provider boundary.
Steps executed:
  ✓ Parsed the quoted deliverable as the title.
  ✓ Collapsed the arrow clause and indented continuations into the body summary.
  ✓ Kept the following task and section outside the logical row.
  ✓ Replaced the complete logical span without duplicating continuation text.
Negative: a malformed TDD row exits non-zero and never invokes `gh issue create` ✓
Result: PASS

### AC-2: Legacy titles exclude implementation guidance

Tier: CLI-FUNCTIONAL
Journey: parse both quoted TDD and ordinary arrow rows through the public index
model used by `publish`.
Steps executed:
  ✓ Preferred the backtick-quoted TDD deliverable.
  ✓ Split ordinary legacy titles at `->`.
  ✓ Removed a dangling conjunction before the arrow.
Negative: an empty quoted name is reported as unpublishable ✓
Result: PASS

### AC-3: The shipped configuration template documents naming conventions

Tier: CLI-FUNCTIONAL
Journey: validate both canonical and compatibility skill trees through the
repository's documentation and parity checks.
Steps executed:
  ✓ Found the `## Naming conventions` stub.
  ✓ Found the rule that raw `->` plan text belongs in the issue body.
  ✓ Confirmed both skill trees are byte-identical.
Negative: parity detects a one-tree-only template change ✓
Result: PASS

---

## E2E Addendum — task-registry legacy publication boundary — 2026-09-07 7aedccb

Spec: `specs/task-registry.md` (AC-14, AC-15, AC-19)
Commit: `7aedccb`
Browser: not applicable — non-browser CLI integration
Harness: `tests/test-task-registry.sh`, real `task-registry publish --apply`
against the fake-`gh` process boundary

This addendum extends the preceding walkthrough after living-spec reconciliation
and adversarial review. A valid multi-line legacy row containing both `->` and an
em dash was published through the CLI. The captured `gh issue create` invocation
carried the exact derived title (`recover active thread`) and complete body
(`extend composer — preserve attachments across reloads`), and the local index
was rewritten as one canonical linked row with no orphaned continuation.

Negative journeys also crossed the CLI boundary: an ambiguous multiple-arrow row,
an empty quoted TDD row, and unbalanced HTML comments made the entire mixed batch
exit non-zero before any provider read or write. Exact 60,000-character input was
accepted; 60,001 was refused without truncation.

Result: PASS
## Integration Proof — `task-registry workflow` six outcomes (AC1, AC2, AC13) — 2026-09-07 (branch `feat/workflow-routing-phase-a`)

`specs/workflow-routing.md` AC2 requires all six outcomes to be distinguishable
in **both** stdout and exit code. That is a user-facing CLI contract — a nightly
wrapper branches on the code, a human reads the text — so the unit assertions in
`tests/test-routine-selectors.sh` are not sufficient evidence on their own.

### Fixture

A throwaway project root with the repository's own `tests/fixtures/task-registry/gh`
mock on `PATH`, five open issues, and a `docs/task-tracking.md` declaring
`build = question` — `build` ships no selector by default, so the deferred-routine
outcome is only reachable through configuration.

### What ran, verbatim

| Outcome | Command | stdout (key line) | exit |
|---|---|---|---|
| routine owns it | `workflow 11` | `routine:  fix` / `chain:    /debug -> /build -> /quality-gate -> /wrap-up-session` | 0 |
| deferred routine | `workflow 20` | `status:   deferred — build is deferred behind the blockedBy provider capability (#97) and the routine itself (#98) — not runnable yet` | 0 |
| no kind label | `workflow 15` | `routine:  none — the issue carries no kind label a routine selects` | 0 |
| already claimed | `workflow 12` | `status:   IN FLIGHT — it carries in-progress, so routine fix already holds it. Do not claim it again.` | 0 |
| unknown reference | `workflow 4242` | `task-registry: no open task matches '4242' — …` | **1** |
| upstream label fault | `workflow 11`, tracker missing `question` | `upstream check: FAILED — these configured routine labels do not exist in github: question` | **2** |
| config fault | `workflow 11`, two routines claiming `bug` | `task-registry: routines: more than one routine selects the same label — bug -> fix, improve` | **2** |
| AC13 — no argument | `workflow` | ``task-registry: `workflow` requires the issue it should look up`` | **2** |

The 1-versus-2 split is the point and was checked as a control in the same run:
with the configuration repaired, `workflow 4242` returns to exit 1. A wrapper
retries a missing issue and pages a human for a broken tool; sharing one non-zero
code makes both responses wrong.

### Correction made during this walkthrough

The first attempt reported `exit=0` for all three exit-2 cases. That was the
harness, not the implementation: `out="$(run ...)"; echo "$out"; echo "$?"` reads
the exit status of the intervening `echo`. Re-run capturing `code=$?` on the line
immediately after the assignment. Recorded because the same mistake would make any
future exit-code walkthrough report a false pass.

### AC7 — `doctor` on this repository

```
provider:       local
selected because: --provider local
configuration:  docs/task-tracking.md
```

Run with `--provider local` so the result does not depend on the network or on
`gh` being authenticated. Before this session the line read
`none (defaults + local fallback)`.

---

## `workflow` — the four outcomes the review found (2026-09-07, follow-up)

Same fixture shape as the walkthrough above, re-run after the review fixes. Four
rows of that table were wrong or missing; this section supersedes them rather
than editing them, because the earlier reading is what the PR description and the
handover were written against.

| Outcome | Command | stdout (key line) | exit |
|---|---|---|---|
| the `#` form | `workflow '#11'` | `routine:  fix` — byte-identical to `workflow 11` | 0 |
| closed issue | `workflow 12` | `task-registry: 12 is done — no routine starts on a closed task. Reopen it upstream if the work is not actually done.` | **1** |
| unknown reference | `workflow 999` | `task-registry: no task matches '999' in github — github: `gh issue view` exited 1 — could not find issue #999` | **1** |
| tracker unreachable | `workflow 11`, `gh label list` failing | `upstream check: COULD NOT RUN — github has a label vocabulary but did not answer: …` / `Nothing to edit — the tracker did not answer. Retry.` | **1** |

The last row is the correction that matters to a scheduler. It used to exit 2 —
the code the skill now tells a nightly wrapper to page on — for a condition no
file edit can clear.

### What changed underneath

`workflow '#11'` failed before this run, though `#11` is the form every markdown
link and every human uses: the command compared the raw argument against
`external.id`, which holds the bare number. It now resolves the argument through
`provider.resolve_reference` and reads the single issue, which also removes the
500-issue page-limit blind spot the backlog scan had.

Verified in the same run that the closed-issue guard reads state rather than the
fixture: flipping #12 back to `OPEN` returns exit 0 with its chain printed.
