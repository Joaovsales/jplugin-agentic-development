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

## 2026-09-07 — Cut 1 (9b686fe): the migration remedy, end to end

Cut 1 has **two** user-facing behaviour changes, not one. AC14/15/16 are
repo-structure criteria with no user surface, but the cut also retires a
`provider =` value a downstream project may have checked in — which the review
correctly flagged as user-facing, and which this log originally denied while the
session's own test file described it as "the likeliest real encounter with
Cut 1". Both are walked through below.

### A. `task-registry migrate` -> `scripts/migrate-task-registry.py`

Driven against a throwaway repo, not a fixture stub — real files, real writes:

1. **Dry run is the default and writes nothing.** A repo with a closed plan
   block, an open row inside it, a superseded spec, and a `blocked-by:` written
   as prose. Output reported `DRY RUN (nothing written)`, classified 1 stale /
   1 completed / 2 superseded, and `find . -type f` was byte-identical after.

2. **`--apply` mints ids in place.** Ids landed after the title and before the
   em-dash summary; the completed history row got none; indented continuation
   detail survived byte-for-byte.

3. **A prose dependency resolves to the id it minted.**
   `(blocked-by: Colour LUT pass)` became
   `(blocked-by: morph-recipes-specs-morph-md.colour-lut-pass)`.

4. **An unresolvable dependency is reported, not dropped.**
   `blocked-by: something nobody wrote` came back under "Unresolved
   dependencies (reported, nothing dropped)" and was left as written.

5. **The audit trail is written** to `tasks/task-registry-migration.md`,
   listing completed rows too.

6. **Unreadable rows exit non-zero.** A row with a status box and no title
   returns 1 from `--apply`, so a partial migration is never reported as a
   complete one.

Also confirmed the retired subcommand fails honestly: `task-registry migrate`
exits 2 with `invalid choice: 'migrate'` rather than an import error.

### B. A downstream project whose config still says `provider = jira`

Driven against a throwaway repo carrying `provider = jira` in
`docs/task-tracking.md` — the state every downstream consumer of this template
is in the moment they `/sync` Cut 1, because `docs/` sits outside every syncable
root and keeps the declaration after the adapter is deleted.

7. **The failure is loud, not silent.** `doctor` refuses rather than quietly
   falling back to the local store, so a project cannot keep running against a
   tracker it thinks is configured.

8. **The message says retired, and says what to do.** Not "unknown provider",
   which would tell an operator their config was always wrong:

   ```
   docs/task-tracking.md: retired provider 'jira' (expected one of: github, local)
     — retired in Cut 1 of specs/workflow-routing.md — the adapter was never run
     against a real Jira. Set `provider = github` or `provider = local`.
   ```

Not covered, and recorded as a gap rather than claimed: there is no sync-time
detection for this, the way `/sync` Step 6.5 detects an unmigrated learning
store. A project learns at first use rather than at sync. Carried in the wrap-up
report as owner: human.

---

## Cut 2 — the todo.md sync engine (specs/workflow-routing.md) — @ 6c5fe6f+staged

Cut 2's own ACs (AC14/15/16) are structural and checked by `grep`/`wc -l`, not
by walkthrough. Two **behaviors** changed for someone actually running the CLI,
though, and both were driven end to end rather than asserted only in-suite.

### A. A malformed row in `tasks/todo.md` — read still works, writes refuse

Driven against a throwaway repo whose index carries one unparseable row
(`- [?] Bad ...`) beside a good one.

1. **`show` still answers, and names the damage.** It writes nothing, so it has
   no reason to refuse — and refusing would deny every task over one bad row,
   with no other command able to diagnose the file (`doctor` never reads the
   index):

   ```
   task: ok.one
     title:    Good row
     ...
     degraded:
       - unreadable index row -- tasks/todo.md:4 — unknown status box '[?]'
         (expected one of: ' ', '~', '!', 'x', '-')
   exit=0
   ```

2. **`upsert --apply` refuses, with file:line.** Exit 1, and `grep -c` confirms
   no second row was appended for the id.

3. **The dry run refuses identically.** Previously it returned a preview
   (`index row would be synced`) for a run that `--apply` would refuse — the
   preview described a different run than the one it was authorizing.

### B. The same, on the GitHub path — no provider call at all

The defect all four review passes found. Driven against the repo's own `gh`
mock with `provider = github`, `--apply --approve`, and the same malformed row.

4. **Zero provider calls before the refusal.** `gh.log` is 0 bytes. Before the
   fix the same run left `issue create --repo fixture-owner/fixture-repo ...` in
   that log and *then* printed a failure — an issue existing upstream with
   nothing in the repository pointing at it, reported to the operator as a
   failure. That is AC-19's "before any provider write", and it now holds on the
   only path that writes.

### C. The wrap-up debt banner emits a command that survives being pasted

5. Driven with a ledger heading `feat/o'brien abc1234..def5678` — git permits
   `'` in a branch name. The emitted line now passes `bash -n`; before the fix
   it failed with an unterminated quote. The derived id
   (`wrap-up-debt.feat-o-brien-abc1234-def5678`) round-trips through
   `is_valid_id`, and agrees with `slugify_id` on all five probed headings.

## 2026-09-08 — verify-task-registry creation

Surface: real task-registry CLI, Python + util-linux script PTYs, local provider.
Source revision and dirty state: `tasks/verification/task-registry.8jm2nf/identity.txt`.
Executed the Bash blocks extracted directly from the generated SKILL.md in order:
Launch → Doctor → record-task → read-task → routines → Cleanup.
No product implementation changed; this is generated verification documentation.

Evidence directory: `tasks/verification/task-registry.8jm2nf/` (retained after cleanup).
Every drive has `<name>.command.txt`, `<name>.pty.txt`, and `<name>.exit.txt`.

| Feature / entry point | Commands, in order | Result |
|---|---|---|
| Doctor | doctor | PASS: local, reachable, docs/task-tracking.md, tasks/details; identity records isolated --repo, SHA and CLI hash |
| record-preview/create/update | preview, create, reopen, update, updated | PASS: no preview file; title, summary, criterion read back; update preserved one record |
| read-id/path/missing | read-id, read-path, read-missing | PASS: both references show saved summary; missing exits 1 naming verify.absent |
| routine-selectors/select/workflow | selectors, select, workflow | PASS for local vocabulary/selection: bug → fix → /debug /build /quality-gate /wrap-up-session; upstream label check explicitly NOT RUN |
| routine-claim preview/apply | claim-preview, before-claim, claim, claimed, select-after | PASS for observed behavior: preview refuses with exit 1 and no mutation; apply persists in-progress; subsequent selection has no candidate |
| record-derived source/spec | not executed | NOT RUN |
| GitHub, installation, agent invocation, complete scheduled routine | no live driver in this skill | BLOCKED when required by a criterion; no coverage claim |

Cleanup: PASS, only owned `/tmp/verify-task-registry.*` runtime removed; no background
processes or ports created. `cleanup.txt` names the removed directory;
`survival.txt` records surviving doctor/create/reopen evidence. All expected command
exits are 0 except read-missing and claim-preview (expected 1).

Draft iterations also retained under `tasks/verification/`: Doctor first rejected
an unfenced configuration, then exposed relative config/default detail paths;
a later run exposed the local claim-preview refusal. Each iteration's EXIT trap
removed its runtime. Final replay exited 0 using the corrected written instructions.

Generated-document validation: skill parity 88 assertions, skill references 158,
syncable paths 10, doc conventions 458 — all passed (714 total). Exact four-H2
feature structure and complete directory byte parity passed. A separate cold-read
review reported no findings; it did not execute the walkthrough. No full product
suite claim is made for this documentation-only addition.

## E2E Walkthrough — verify-task-registry wrap-up — 2026-09-08 2bde026

Scope: generated skill's local CLI contract (non-browser functional behavior).
Driver: the only canonical verify-* candidate, verify-task-registry; compatibility
mirror checked byte-identical. Fresh replay extracted the Bash blocks directly
from SKILL.md and the three feature files, in their documented order.

Evidence: `tasks/verification/task-registry.oOCGvp/`. Sequence: doctor → preview →
create → reopen → update → updated → read-id → read-path → read-missing → selectors
→ select → workflow → claim-preview → before-claim → claim → claimed → select-after
→ cleanup → survival check. All 17 drive exit files agree with expected results
(0, except missing-reference and local claim-preview refusal, both 1).
Doctor identified local provider, explicit isolated repo, config and data root.
Read-back confirmed title/summary/criterion, then updated content, then the
in-progress label and candidate exclusion. Owned runtime was removed and the
named evidence survived. Derived source/spec, external tracker, installation and
full agent workflow entry points remain unverified; none are required to prove
the requested generated skill's minimum local walkthrough.

Spec reconciliation: 1 candidate, unchanged — specs/compound-engineering-adoption.md
matched its legacy .claude/skills/** pattern; the new recipe preserves the existing
skill/parity conventions and changes none of that spec's mechanisms. No spec edit.
Changed-map maintenance: clean — one target, valid contract and matching mirror;
no product CLI source path or visible CLI behavior changed in this session.
Security scan: PASS — explicit local provider and owned scratch root; shell args
quoted with Bash %q; no new dependencies, auth endpoints, SQL, HTML, cryptography,
or credential handling. Evidence contains local paths and test task text, no secrets.
Raw PTY transcripts retain original CRLF bytes and command trailing spaces; source
Markdown whitespace is checked separately to preserve the original evidence.

### Final review correction and replay — 2026-09-08 2bde026

Four separately dispatched wrap-up passes: consistency, defensive/security,
coverage, adversarial critic. One SHOULD-FIX / confidence 100 / manual / agent:
record-task.md required `show` to return task.source_path, but the CLI renderer
only exposes the derived ID/title and the index row location. Fixed deliberately
in both mirrors: exact derived source/spec recipes assert only available output
and document the source-field read-back limit. No product code changed.

Final replay: `tasks/verification/task-registry.vp2BH0/`, 21 command/output/exit
triples. Repeated all preceding feature sequences and added `derived`,
`derived-read`, `derived-spec`, `derived-spec-read` after the one-record update
check. PASS: verify.readme-md / Source follow-up, verify.specs-check-md /
Spec follow-up / specs/check.md. All prior read/selection/claim checks still
passed with these two unclassified tasks present. Exit status 0, expected negative
commands 1, cleanup succeeded, evidence survived. Derived source/spec entry points
are now verified; earlier NOT RUN entries above describe the earlier runs only.

Full suite before the recipe correction: `bash tests/run.sh </dev/null` — all 38
test files passed. Follow-up documentation checks and final review recorded below.

Follow-up checks: parity 88, references 158, frontmatter 256, syncable paths 10,
doc conventions 458, learning schema 31 assertions passed (1,001 total).
Critic recheck: ACCEPT, finding resolved, no introduced findings. Final mirror
bytes, 21 expected command exits and all recorded runtime removals checked.
Review independence: four passes dispatched; no confidence promotion needed.
Review totals: 0 MUST-FIX, 1 SHOULD-FIX fixed deliberately, 0 unresolved/skipped.
No configured deployment targets; interactive non-routine branch.
