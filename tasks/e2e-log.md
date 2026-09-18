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

## E2E Walkthrough — issue 117 task-registry CLI — 2026-09-09

Spec: specs/preserve-published-issue-references.md
Commit: working tree based on `9017248f0311b5980a4a1cdf075c1aea6aec45d2`
Driver: `verify-task-registry` local CLI recipe through isolated PTYs
Evidence: `tasks/verification/task-registry.117.Unyt8S/`

### AC-1: A local-pending update of a GitHub-linked task keeps the original GitHub issue reference in the compact index.

Tier: non-browser functional
Journey: The grounded local-provider walkthrough passed Doctor, preview, create, update, read-back, derived records, routine selection, and cleanup. The approval-gated GitHub fallback was exercised by the focused regression with a fake external provider.
Result: BLOCKED for live external-provider E2E — the local verification driver cannot authenticate to or mutate GitHub. Supplemental regression PASS: the index retained `github:42` and never rendered the local detail path.

### AC-2: A later approved upsert updates the original issue instead of creating a second issue.

Tier: non-browser functional
Journey: The approved second upsert was exercised by the focused regression after the local-pending write.
Result: BLOCKED for live external-provider E2E — the local verification driver cannot prove GitHub update/create behavior. Supplemental regression PASS: the preserved reference was fetched, one update occurred, and zero creates occurred.

### AC-3: Regression tests cover approval-gated fallback followed by approved publication.

Tier: non-browser functional
Evidence: `env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/test-task-registry.sh` — 326 assertions passed; full suite — all 38 test files passed.
Result: PASS

Cleanup: PASS — owned verification runtime removed; evidence survived at `tasks/verification/task-registry.117.Unyt8S/`.

## E2E Walkthrough — Memory maintenance history counting — 2026-09-09 9017248

Spec: specs/memory-maintain-history-count.md
Source: uncommitted implementation on base 9017248f0311b5980a4a1cdf075c1aea6aec45d2.
Hook SHA-256: 5bf409d75c0c2125c2b31187b9371b0b8b77286fb356aaf678e66403c803e0ae.
Driver: Bash lifecycle hook, invoked from a Python driver in a real PTY.
Each scenario creates an owned temporary project containing only its history;
executes the absolute repository `.claude/hooks/session-start.sh` with stdin
`{"source":"startup"}`, `CCW_SESSION_GUARD=0`, and a fixture-local
`CLAUDE_SESSION_SENTINEL`; captures stdout/stderr and exit status; and requires
`SKILLS AVAILABLE` to prove that a missing reminder was not an aborted banner.
This is a lifecycle-hook integration walkthrough, not an agent-triggering test.

### AC1 — Canonical history

Five `### [2026-09-09] — session` entries: exit 0, full banner, reminder at 5.
Negative: four entries produce no reminder. PASS.

### AC2 — Alternate and mixed history

Five `## 2026-09-09 — session` entries and four canonical plus one alternate
entry: each exits 0, full banner, reminder at 5. Before implementation both
new regression assertions failed. Ten separate same-date alternate entries
produce a reminder at 10. PASS.

### AC3 — Boundaries and invalid headings

Four/six canonical entries, empty/missing history, and four canonical entries
plus `## 2026-09-09suffix — invalid`: exit 0, full banner, no reminder in every
case. Regression suite additionally checks eight malformed/unrelated headings,
individually added to four valid sessions. PASS.

### AC4 — Counting contract

`bash tests/test-memory-maintain-doc.sh`: 15 assertions passed, including
hook/skill pattern agreement and byte-identical mirrors. The complete current
history counts 22 before appending this session, versus 19 with the old pattern.
PASS (contract test plus live grep).

### AC5 — Preserved behavior and regression suite

Source diff confines the skill change to heading recognition and makes its
existing positive-five gate explicit. `--force`, light-pass work, and glossary
bootstrap branches are preserved by inspection; no forced store sweep was run.
`env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null`:
38 files, 3,589 assertions passed. The unset applies only to the test process:
the inherited trusted-config override caused a pre-existing Doctor test failure.
`bash -n` and `git diff --check` pass. PASS.

Cleanup: owned runtime removed; stdout/stderr for all nine live scenarios and
source identity retained in `/tmp/memory-maintain-walkthrough/`. The observations
above are the durable record. Isolated mutation probes each went red: missing
alternate format (3 failures), missing date boundary (2), zero allowed (1), and
modulo bypassed (10). No mutation touched the working implementation.

Review: quality-gate structural/anti-pattern passes inline; APOSD dispatched,
GO. Four wrap-up passes separately dispatched: consistency, defensive/security,
test coverage, adversarial critic. All report zero findings; no confidence
promotion used. Reported, not applied: none. Security checklist: fixed regex and
quoted file inputs; no history text is evaluated as code, no new authentication,
secret, disclosure, cryptographic, dependency, or network surface.

Verification-map maintenance: clean / not applicable; the only local recipe,
verify-task-registry, declares the Python task-registry CLI. This change alters
its surrounding agent lifecycle hook, with no changed CLI feature entry point.

Spec reconciliation: six candidates, all unchanged after comparison with the
scoped heading-count diff: specs/compound-engineering-adoption.md,
specs/context-memory-management.md, specs/memory-maintain-history-count.md,
specs/pstack-verification-skill-integration.md, specs/separate-project-config.md,
specs/sweep-routines.md. The legacy context-memory spec's old store vocabulary
predates this fix; its cadence contract is unaffected. No deferred reconciliation.


### Committed verification identity — 2026-09-09 ca8142d

Spec: specs/memory-maintain-history-count.md
Commit: ca8142d85b6182d935ab1a14ddd8749a74f39ec0
The committed hook's SHA-256 matches the source exercised in all nine scenarios
above (5bf409d75c0c2125c2b31187b9371b0b8b77286fb356aaf678e66403c803e0ae).
All five AC results and review findings above apply to this source commit.
Final full suite: 38 files / 3,589 assertions, exit 0, zero failures.
This follow-up changes only the verification identity and wrap-up fingerprint.

## E2E Walkthrough — /system-design-planning worked example — 2026-09-11

Spec: specs/system-design-planning.md
Source: uncommitted implementation on base bf58555 (branch master).
Driver: the skill run once, in the main context, against its own Step 8 TODO(shortcut) (a --depends-on flag for task-registry upsert). Outputs: specs/upsert-depends-on.md, specs/upsert-depends-on.plan.html.

### AC: reads issue references only through task-registry.py show — EXERCISED
`python3 .agents/skills/task-registry/scripts/task-registry.py show 97` read the adjacent issue (title, labels, evidence) with no tracker CLI call.

### AC: spec section order constraints → system design → component contracts → data models → build order — EXERCISED
specs/upsert-depends-on.md headings appear in that order (## Constraints, ## System design, ## Component contracts, ## Data models, ## Build order, ## Decisions, ## Acceptance Criteria, ## Implementation Paths).

### AC: renders through visual-render.py to specs/<feature>.plan.html and prints the path before asking for review — EXERCISED
Render command exited 0; page 47,136 bytes; section ids in order problem constraints system-design contracts data-models build-order decisions; `✓ Visual written:` printed, then the gate text.

### AC: nothing filed and nothing built before "approved"; approval attaches to the rendered document — EXERCISED
Gate printed with both paths; no upsert invoked (tasks/details/ unchanged, no issue created); D2 left open for the reviewer.

### Step 5 adversarial pass — EXERCISED
critic dispatched under the Review Dispatch Contract (no diff — design review, deferrals: none). Verdict HOLD: 0 MUST-FIX, 9 SHOULD-FIX, 5 NITPICK, all at confidence 100; every finding folded into the spec (line-citation drift, LOCAL_PENDING capability source, pre-config validation placement, sequential filing under D2, replacement disclosure, parity per slice, clearing out of scope).

### AC: off-ramp `Skipping system-design-planning:` — NOT EXERCISED (the change met the bar).
### AC: appends `[ ] TDD:` rows under `### Slice` headings and files one task per slice — NOT EXERCISED (waits for approval; Step 8).

## E2E Walkthrough — fix routine reproduction outcomes — 2026-09-12

Spec: `specs/routine-reproduction-report.md`
Driver: `bash tests/test-routine-reproduction-e2e.sh`
Surface: canonical `task-registry.py` CLI against four isolated local-provider repositories.
Result: 20 assertions passed, exit 0. No GitHub write was attempted.

### AC1 — reproduced and fixable continues — PASS

Created a local bug through `upsert --apply`, then invoked `workflow` and
`select --routine fix`. Both exited 0, resolved the fix path, returned the parent,
and created no escalation artifact.

### AC2/AC9 — inconclusive reproduction escalates — PASS

Invoked `escalate` with `reason=inconclusive`, `reproduction-state=not-reproduced`,
the exact reproduction command, observation, timestamp, and an explicit reason
that evidence was unavailable. It confirmed the hold, retained exactly one run
artifact, and exited 1. A subsequent real selector invocation omitted the parent.

### AC2/AC14 — test cannot start — PASS

Invoked `escalate` with `reason=execution-blocked`, `reproduction-state=unverified`,
and a validated blocker v1 JSON file. It held the parent, created the actionable
local blocker, retained the run, and exited 1. Subsequent selection returned the
blocker and did not return its held parent.

### AC2/AC14 — reproduced, then verification blocked — PASS

Invoked `escalate` with `reason=verification-blocked` and
`reproduction-state=reproduced`. It confirmed the hold, retained exactly one
artifact, and exited 1. A subsequent selector invocation returned no parent.

## E2E Walkthrough — task-registry investigation escalation — 2026-09-12 7707342

Spec: `specs/routine-reproduction-report.md`
Commit: `7707342fae1644e8070ed866410ad7e07ad7bed1` plus the reviewed working-tree diff
Driver: `verify-task-registry` / util-linux `script -e`, local provider
Source SHA-256: `ca52c7e38e683bf3bd4505188b1be1ed6352ab2bba138a13c8dcd5a02c746afb`
Evidence: `tasks/verification/task-registry.mrdadZ/`

### CLI escalation entry point — PASS

Doctor identified the isolated repository, local provider, configuration, and
reachable store. `upsert --apply` created `verify.sample` through the public CLI
and `show` read it back. An escalation preview exited 0, created no hold, and a
second `show` still reported only the original `bug` label.

The applied inconclusive escalation exited 1 as required, reported
`hold: confirmed`, and produced one exclusive routine-run artifact in the owned
repository. Public `show` then reported `bug, needs-investigation`; a separate
`select --routine fix` returned `candidate: none`. Cleanup removed the owned
runtime, and every command, PTY transcript, exit status, identity record, and
cleanup proof survived in the evidence directory.

Verification-map maintenance outcome: **changed** — added the missing
`escalate-investigation` feature recipe to both byte-identical verification-skill
trees. A second source/map pass was idempotent. This direct CLI run does not claim
the agent-invoked workflow coverage required by AC14; those executions are
recorded separately below.

## E2E Walkthrough — isolated debug-skill outcomes — 2026-09-12 7707342

Spec: `specs/routine-reproduction-report.md`
Surface: actual `.agents/skills/debug/SKILL.md` procedure in four isolated
`routine/fix/` repositories; no shared product state and no GitHub writes.
Evidence: `tasks/verification/skill-runs/`

### AC1/AC14 — reproduced and fixable — PASS

`reproduced-and-fixable.md` records the exact focused test at exit 1 before the
fix and exit 0 after it. The actual debug prelude selected the root cause using
disconfirming checks, applied the minimal fix, and ran the full 42-file suite.
The parent retained only `bug`, remained selectable by `fix`, and produced zero
escalation artifacts. No commit or push occurred.

### AC2/AC9/AC14 — inconclusive reproduction — PASS

`inconclusive.md` records a runnable reproduction at exit 0 that did not exhibit
the report. The actual debug procedure rejected an unsupported proposed fix and
invoked its canonical owner exactly once with `inconclusive/not-reproduced`.
Escalation exited 1, retained claim and unrelated labels, added the hold, wrote
one comment and artifact, opened no PR, and left the parent unselectable.

### AC2/AC6/AC9/AC14 — test cannot start — PASS

`execution-blocked.md` records exit 66 before assertions because a named runtime
fixture was absent. The actual debug procedure isolated that practical blocker,
filed one validated stable bug blocker, and escalated exactly once with
`execution-blocked/unverified`. The parent became held and unselectable; the
independently actionable blocker remained open and was returned by the next
`fix` selection. One comment and artifact remained, with no commit or PR.

This run also exposed a duplicate artifact field that omitted the otherwise
correct blocker outcome. The implementation now passes the structured result to
artifact rendering, and `test-task-escalation.sh` pins
`"blocker_disposition": "local"` in the retained artifact.

### AC2/AC9/AC14 — reproduced, then verification blocked — PASS

`verification-blocked.md` records the initial focused reproduction at exit 1,
the post-fix focused test at exit 0, and the required pre-PR verification at
exit 78 before startup because its external credential was unavailable. The
documented verify/build handoff returned structured evidence to debug's single
owner. Exactly one `verification-blocked/reproduced` escalation exited 1; the
parent became held and unselectable, one comment and artifact remained, and no
blocker, commit, push, or PR was created.

## E2E Follow-up — final execution-blocked tree — 2026-09-12 7707342

Spec: `specs/routine-reproduction-report.md`
Evidence: `tasks/verification/skill-runs/execution-blocked.md`
Surface: actual `.agents/skills/debug/SKILL.md` procedure in a fresh isolated
`routine/fix/` repository against the corrected working tree.

The reproduction exited 66 before its assertion because the named runtime
fixture was absent. The canonical owner invoked one
`execution-blocked/unverified` escalation, which exited 1, confirmed the parent
hold, created one stable selectable bug blocker, wrote one comment and one
artifact, and opened no commit or PR. Decoding the retained artifact confirmed
`blocker_disposition=local`, canonical
`parent_ref=verification-execution-blocked-final.parent`, and ordered
hold/blocker/comment outcomes. Result: **PASS**.

## Committed verification identity — routine reproduction report — 2026-09-12

Spec: `specs/routine-reproduction-report.md`
Commit: `d880f45`

The committed source is the reviewed tree exercised by the CLI and isolated
`/debug` walkthroughs above. Final verification passed all 42 test files and
3,965 reported assertions. This follow-up records only the commit identity.

## E2E Walkthrough — /tidy --report evidence run — 2026-09-14 e7ab8fa

Driver: the skill's `--report` mode executed by hand in the main context against the tree at e7ab8fa (HEAD tree objects, because the shared working tree was dirty with another session's files and a real run STOPs under Law 1); machine-side surfaces (`~/.claude/`, `~/.agents/`, `git worktree list`, `gh pr list`) read live. Output: the session's `tidy-report-e7ab8fa.md`, delivered to the user and kept out of the tree per AC-14.

### AC-14: the report lists the six live rows of the spec's Problem table — EXERCISED
inventory 9 findings (`/graphify` row without a directory; `verify-task-registry` without a CLAUDE.md/README row; banner lacking 6 skills; AGENTS.md skipped, no skills table); retired clean (set = 4 names from `git log --diff-filter=D`, 0 live references outside `tasks/` `specs/`); installed findings (920-line `~/.claude/CLAUDE.md` drift, 7 shipped skills missing, installed banner advertising 2 retired skills); refs clean (518 tokens, 0 repository paths resolving nowhere); worktrees 21 local branches with merged PRs, 0 removable worktrees; strays 2 files under `.claude/worktrees/`; registers 36 archivable plan blocks and a stale checkpoint.

### AC-2: a missing surface is skipped with a note, not a finding — EXERCISED
AGENTS.md has no skills table at e7ab8fa; the report's inventory row says "skipped, no skills table" and counts no finding for it.

### AC-5 / AC-6: machine-side remedies printed, never run — EXERCISED
`bash install.sh` / `bash install.sh --prune-skills` and 21 `git branch -D <branch>` lines printed under Tier 1; nothing under `~/.claude/` or `~/.agents/` modified; the one live worktree kept because its branch has no merged PR.

### AC-7 / AC-8: Tier 2 filing — NOT EXERCISED (`--report` files nothing; the dedupe read and the `upsert` call are described in the report as the candidate it would file).

### AC-15: suite — EXERCISED
Clean worktree at e7ab8fa: 8/39 files RED, 148 of 3789 assertions (all environment-only on this Windows host, see `tasks/solutions/process/windows-suite-failures-compare-against-a-clean-head-worktree.md`). Changed tree: identical 8 files and 148 assertions, zero new failing assertion names, 3903 total.

## Spike S1 — every canonical skill loads from the plugin manifest — 2026-09-17 3d52d73

Spec: specs/claude-plugin-manifest.md (§ Build order slice 1; AC 1, AC 11)
Commit: 3d52d73 (worktree-plugin-manifest)
Claude Code: 2.1.227

**S1** — all skills under `.agents/skills/` load as `jplugin:<name>` in place from the directory, with no install step.

Commands run from the repository root:

```
claude plugin validate --strict .                      # marketplace manifest: Validation passed
claude plugin validate .claude-plugin/plugin.json      # plugin manifest: passes; --strict warns only that a
                                                       # root CLAUDE.md is not plugin context (expected here)
claude --plugin-dir . plugin details jplugin           # loads the plugin from disk and prints its inventory
```

`details` reported `Source: jplugin@inline`, `Skills (33)`, `Agents (0)`, `Hooks (0)`, and this list:

```
auto-push, brainstorm, build, checkpoint, create-verification-skill, debug, eval,
folder-context-optimization, html-presentation, learn, maintain-verification-skill,
memory-maintain, plan, prd, quality-gate, receive-review, refresh, security-scan,
software-design-expert-learn, software-design-expert-review, start-qa, sweep, sync,
system-design-planning, task-registry, tidy, verify, verify-task-registry, visual-plan,
visual-recap, wrap-up-session, writing-skills, yolo
```

`ls .agents/skills` at 3d52d73 is the same 33 names in the same order. Zero agents and zero hooks confirms the manifest carries only the `skills` key (spec § Decisions: agents and hooks stay project-level). Always-on cost reported: ~2,255 tokens per session.

**Verdict: PASS.**

## Spike S3 — two marketplaces under one name — 2026-09-17 3d52d73

Spec: specs/claude-plugin-manifest.md (§ Build order slice 1, spike question S3)
Claude Code: 2.1.227

Two directory sources carrying the same `marketplace.json` name were registered in turn
(the github source needs the manifest on the remote, which this branch has not pushed;
the collision is on the *name*, and the docs state the rule source-independently):

```
claude plugin marketplace add <checkout A>     # Successfully added marketplace: jplugin-agentic-development
claude plugin marketplace list                 # Source: Directory (<checkout A>)
claude plugin marketplace add <checkout B>     # Successfully added marketplace: jplugin-agentic-development  (exit 0)
claude plugin marketplace list                 # Source: Directory (<checkout B>)   <- A is gone
```

`~/.claude/plugins/known_marketplaces.json` held one entry for the name, pointing at B.
Docs (plugin-marketplaces): "Each user can register only one marketplace per name — adding
a second with the same name replaces the first."

**Verdict: REPLACED, silently.** Consequence for § Decisions and slice 4: the developer
machine's directory-source marketplace must carry a different name from the one project
settings declare, or opening any synced project replaces the developer's in-place source.
The probe marketplace was removed afterwards (`claude plugin marketplace remove`).

### S3 follow-up — the `-dev` fallback is not expressible — 2026-09-17

A second marketplace manifest named `jplugin-agentic-development-dev` was written to a scratch
directory with its one plugin entry pointing at the checkout, first as a relative path that
climbs out of the marketplace root, then as an absolute path:

```
claude plugin validate --strict <scratch>          # Validation failed (both forms)
claude plugin marketplace add <scratch>            # Successfully added marketplace: jplugin-agentic-development-dev
claude plugin install jplugin@jplugin-agentic-development-dev --scope user
#  ✘ Failed to install plugin: This plugin's marketplace entry is invalid: source: Invalid input
```

A plugin's relative source must live under the marketplace root, and a directory marketplace's
name is the name in the manifest at that directory — so one repository can publish exactly one
marketplace name. Decision recorded in the spec (§ Decisions, marketplace-name collision):
`install.sh` registers the checkout under the manifest's name and prints that opening a project
whose settings declare the github source replaces the directory registration; the installed
record keeps its `installPath`, so skills keep loading from the checkout until `plugin update`.
The probe marketplace was removed afterwards.

## Spike S2 — bare `/name` routes to `jplugin:<name>` with no un-namespaced copy — 2026-09-17 729ec6d

Spec: specs/claude-plugin-manifest.md (§ Build order slice 1, spike question S2; AC 2, AC 11)
Commit: 729ec6d (worktree-plugin-manifest); candidate tree 3d52d73 with `.claude/skills/` deleted
Claude Code: 2.1.227
Rubric: written before any candidate ran (scratchpad `s2-rubric.md`); graded from transcripts
with `.agents/skills/eval/scripts/grade-skill-loads.sh`, never from what a session said.

**Setup.** Nine print-mode sessions in the scratch worktree `.claude/worktrees/jplugin-routing`
(3d52d73, `.claude/skills/` deleted), plugin loaded with `--plugin-dir`, isolation through an
empty `CLAUDE_CONFIG_DIR` holding only credentials — no user-scope skills, no installed plugins —
in place of the rubric's rename of `~/.claude/skills/` (same property, and it leaves the live
user directory alone). `--max-budget-usd 1.50` per session. Two organic prompts per target plus
one bare-slash probe.

**Bare-slash probes (harness routing).** The first pass was invalid: Git Bash rewrote every
`/name` argument into `C:/Program Files/Git/name` before Claude Code saw it (MSYS path
conversion), so those three sessions are discarded as broken prompts (rubric rule 4) — two of
them still loaded the right skill from the mangled text, which says nothing about routing.
Re-run with `MSYS_NO_PATHCONV=1`:

| typed | harness expanded to | verdict |
|-------|---------------------|---------|
| `/quality-gate` | `<command-name>/jplugin:quality-gate</command-name>` | FIRED — routed by the harness, no Skill tool block needed |
| `/task-registry doctor` | `<command-name>/jplugin:task-registry</command-name>` `<command-args>doctor</command-args>` | FIRED |
| `/verify` | `<command-name>/verify</command-name>` — the body is Claude Code's **bundled** `verify` skill (`bundled-skills/2.1.227/…/verify`, "Don't run tests. Don't typecheck.") | **MISROUTED** — a name collision the un-namespaced copy currently masks |

Bundled skills shipped by Claude Code 2.1.227: `verify` only. It is the single collision with the
33 plugin skill names.

**Organic prompts (model routing), plugin only:**

| target | rep 1 | rep 2 | notes |
|--------|-------|-------|-------|
| `jplugin:task-registry` | FIRED | FIRED | 9 and 8 turns |
| `jplugin:quality-gate` | NONE (budget exhausted after 21 turns of a hand-rolled review) | FIRED | |
| `jplugin:verify` | NONE (27 turns, verified by hand) | NONE (24 turns, verified by hand) | |

**Control (same prompts, same commit, `.claude/skills/` present, no plugin):** `verify` fired in
1 of 2 reps (23 and 27 turns). The organic weakness of the verify prompt is not introduced by the
namespace; it is a property of the skill's description and pre-dates this change.

**Verdict: FAIL** on the rubric's PASS standard (every rep FIRED for every target). Passes:
task-registry in full. Fails: quality-gate on one organic rep; verify on both organic reps and,
decisively, on the bare slash. The bare-slash miss is the finding that changes the plan: once
`.claude/skills/` is deleted, `/verify` in every downstream project resolves to Anthropic's
bundled skill, whose contract contradicts this template's (`/verify` here runs the suite and
records e2e evidence). Slice 6 stays gated; § Decisions is reopened in the spec with the options.

## Spike S4 — a fresh clone is offered the plugin from `.claude/settings.json` — 2026-09-17 cf82395

Spec: specs/claude-plugin-manifest.md (§ Build order slice 1, spike question S4; AC 3, AC 11)
Commit: cf82395 (worktree-plugin-manifest)
Claude Code: 2.1.274 (the run started on 2.1.227; the CLI auto-updated between the first and
second interactive open, and every measurement below is from 2.1.274)

**Setup.** `git clone` of the branch into `.claude/worktrees/s4-clone` (`core.longpaths=true` —
one task-detail filename exceeds the Windows default). Origin `master` carries no
`.claude-plugin/` yet (nothing is pushed), so the clone's declaration keeps the marketplace
name and points its `source` at this branch: `{"source": "git", "url":
"file:///C:/Users/Joao.Souto/coding-agent-workflow/.claude/worktrees/plugin-manifest", "ref":
"worktree-plugin-manifest"}`, with `enabledPlugins["jplugin@jplugin-agentic-development"]:
true`. The mechanism under test — settings-driven registration, install and `ref` pinning —
does not depend on the transport; the github source itself can only be exercised after push.
Measured against the user's real `~/.claude` (the isolated-config variant of this spike proved
nothing: a one-turn print session exits before the marketplace clone finishes, so it recorded
"nothing registered" for a reason that was timing, not behaviour). Evidence is the
`--debug` log Claude Code writes to `~/.claude/debug/<session>.txt`, the two plugin registries,
and `claude plugin` CLI output.

**Marketplace registration — automatic, headless too.** `installPluginsForHeadless` runs in
`-p` mode and reconciles every declared marketplace (`[reconcile] 1 marketplace(s):
jplugin-agentic-development(install)` → `git clone succeeded` → `Added marketplace source` →
`installPluginsForHeadless: installed marketplace jplugin-agentic-development`). Three source
constraints fell out of the failed attempts before that line appeared:

| declaration | result |
|-------------|--------|
| `url` as a plain local path (`C:/Users/…/plugin-manifest`) | refused — only `https`, `http`, `ssh`, scp-like and `file://` URLs are accepted; the first interactive open showed no marketplace prompt because of this, not because prompts do not exist |
| `ref` = commit sha (`729ec6d…`) | `git clone --branch <sha>` → "Remote branch … not found"; **`ref` must be a branch or tag** |
| `url` = `file:///C:/…`, `ref` = branch | registered; `known_marketplaces.json` holds `source.ref: "worktree-plugin-manifest"`, checkout at `~/.claude/plugins/marketplaces/jplugin-agentic-development` on that branch at cf82395 |

**Plugin install — not automatic, no prompt.** After the marketplace was registered, headless
logs `Plugin not available for MCP: jplugin@jplugin-agentic-development - error type:
plugin-cache-miss` and `installed_plugins.json` is unchanged; the binary's own strings confirm
headless only ever "installed marketplace", never a plugin. Two interactive opens of the clone
(user at the keyboard, trust and external-`CLAUDE.md` dialogs answered) produced **no install
prompt**; `/jplugin:verify` reported `No commands match`, while the completion list still showed
the un-namespaced `/build`, `/quality-gate`, `/sync`, `/tidy` from the clone's `.claude/skills/`.
The offer in 2.1.274 is a diagnostic, not a prompt — the `plugin-not-installed` status text,
surfaced through `/plugin`, reads:

```
Plugin "<id>" is enabled in project settings but isn't installed — run `claude plugin install <id> --scope project`
```

**Install record and what loads.** `claude plugin install jplugin@jplugin-agentic-development
--scope project` from the clone: `✔ Successfully installed plugin (scope: project)`. The record:

```json
"jplugin@jplugin-agentic-development": [{
  "scope": "project",
  "installPath": "C:\\Users\\Joao.Souto\\.claude\\plugins\\cache\\jplugin-agentic-development\\jplugin\\1.0.0",
  "version": "1.0.0",
  "gitCommitSha": "cf823950003550e91d440fe2c823555c7911a6f7",
  "projectPath": "C:\\Users\\Joao.Souto\\coding-agent-workflow\\.claude\\worktrees\\s4-clone"
}]
```

The install record carries no `ref`; it carries the **commit the declared branch resolved to**
(`gitCommitSha` = cf82395, the branch tip), and the marketplace record carries the `ref`. A
following `claude -p --debug` in the clone logs `Loaded 35 skills from plugin jplugin custom
path: …\cache\jplugin-agentic-development\jplugin\1.0.0\.agents\skills` and
`getSkills returning: 80 skill dir commands, 36 plugin skills, 40 bundled skills`; `claude
plugin details` lists the same 35 names. Side effect worth knowing: the project-scope install
rewrote the clone's `.claude/settings.json` (keys reordered, content unchanged).

**Verdict: FAIL on AC 3 as worded, with the mechanism recorded.** "Offered on first open" is
false for 2.1.274 — the marketplace is registered silently and the plugin needs one explicit
`claude plugin install … --scope project` (or `/plugin`) per machine, after which the declared
`ref` is what loads. The `ref` `/sync` Step 5 writes today — the checked-out sha — cannot be
cloned at all, so the pinning-model row of § Decisions is reopened with the three shapes that
do work (branch, tag, omitted) before slice 6 proceeds. Cleanup: `claude plugin uninstall
jplugin@jplugin-agentic-development --scope project` from the clone and `claude plugin
marketplace remove jplugin-agentic-development`; a stray
`~/.claude/plugins/marketplaces/temp_git_*..clone` directory is left over from the refused
`C:/` attempt.

## Spike S4 — follow-up: clean first open on 2.1.277 — 2026-09-18 66f45e3

Spec: specs/claude-plugin-manifest.md (§ Build order slice 1, spike question S4; AC 3)
Commit: 66f45e3 (worktree-plugin-manifest)
Claude Code: 2.1.277 (auto-updated overnight from 2.1.274)

**Why a re-run.** The FAIL above was contaminated: the trust dialog was accepted during the
very first open, when the declaration still carried the refused `C:/` url, and the docs say
project plugins are set up "once they trust the project folder, with no separate prompt".
A second look at the 2.1.274 evidence also showed the versioned cache directory was left
over from the manual `claude plugin install`, so "skills visible" could not be attributed.

**Setup.** `claude plugin marketplace remove jplugin-agentic-development`, the leftover
`~/.claude/plugins/cache/jplugin-agentic-development/` deleted, and a third clone at a path
Claude Code had never seen (`.claude/worktrees/s4-clone3`, no project entry in
`~/.claude.json`), declaration `{"source": "git", "url": "file:///C:/…/plugin-manifest",
"ref": "worktree-plugin-manifest"}` plus `enabledPlugins` — same shape as before. Opened
by the user with `claude --debug`; both dialogs accepted; `/jplugin:` typed.

**Debug log (`~/.claude/debug/d40f0f15-….txt`), in order:**

```
Skipping orphaned enabledPlugins entry jplugin@jplugin-agentic-development: marketplace not registered
clearPluginCache: invalidating loadAllPlugins cache (post-trust: re-discover project @skills-dir plugins)
Installing 1 marketplace(s) in background
[reconcile] 1 marketplace(s): jplugin-agentic-development(install)
Marketplace checkout probe: no readable HEAD, cloning
Added marketplace source: jplugin-agentic-development
Loading plugin jplugin from source: "./"
Using manifest version for jplugin@jplugin-agentic-development: 1.0.0
Copying source directory ./ for plugin jplugin@jplugin-agentic-development
Successfully cached plugin jplugin@jplugin-agentic-development at C:\Users\…\plugins\cache\jplugin-agentic-development\jplugin\1.0.0
Loaded 35 skills from plugin jplugin custom path: …\cache\jplugin-agentic-development\jplugin\1.0.0\.agents\skills
```

The completion list showed `/jplugin:prd`, `/jplugin:sync`, `/jplugin:tidy` within ten
seconds of accepting trust, with no plugin prompt. `known_marketplaces.json` gained the
marketplace with `source.ref: "worktree-plugin-manifest"`; **`installed_plugins.json` gained
nothing** — a settings-driven install is recorded only by the versioned cache directory,
keyed by `plugin.json` `version` (1.0.0). A headless `claude -p` in the same clone before
the cache existed reported `plugin-cache-miss`: print mode registers the marketplace but
never copies the plugin, exactly as measured on 2.1.274.

**Verdict: PASS on AC 3** — a fresh clone installs and loads the plugin on first open once
the folder is trusted, and the declared `ref` is the branch that gets cloned. Two corrections
follow from the whole spike and are decided in § Decisions (2026-09-18):

1. **Pinning is by `version`, not by `ref`.** A commit sha as `ref` does not clone (`git
   clone --branch <sha>`), and the docs pin a plugin by its manifest `version` ("users only
   receive updates when it changes") — the model Addy Osmani's `agent-skills` uses: github
   source, no `ref`, `version` bumped per release. `/sync` Step 5 stops writing `ref`.
2. **`session-start.sh`'s "PLUGIN NOT INSTALLED" line reads `installed_plugins.json`,
   which a settings-driven install never touches**, so every downstream project would see the
   warning while the plugin works. The check must also accept the versioned cache directory.

Cleanup: the marketplace, cache and `s4-clone`/`s4-clone2`/`s4-clone3` are scratch; remove
with `claude plugin marketplace remove jplugin-agentic-development` and `rm -rf` of the three
clone directories and `~/.claude/plugins/cache/jplugin-agentic-development`.

## Spike S2 — follow-up: bare `/verify-evidence` routes to the plugin — 2026-09-18 eb5fdbd

Spec: specs/claude-plugin-manifest.md (§ Decisions, `/verify` after the copy is deleted; AC 2)
Commit: eb5fdbd (worktree-plugin-manifest) — the rename
Claude Code: 2.1.277

**Setup.** Scratch worktree `.claude/worktrees/jplugin-routing` detached at eb5fdbd with
`.claude/skills/` deleted, plugin loaded with `--plugin-dir`, the user's real config (its
`~/.claude/skills/verify` legacy copy is a different name and cannot shadow the probe), one
print-mode session, `MSYS_NO_PATHCONV=1`, prompt `/verify-evidence`.

**Result.** The transcript's first user turn is
`<command-message>jplugin:verify-evidence</command-message>
<command-name>/jplugin:verify-evidence</command-name>` — the harness routed the bare slash to
the plugin skill. The S2 FAIL was the name collision with Claude Code's bundled `verify`, and
the rename removes it; `/quality-gate` and `/task-registry` were already FIRED in S2.

**Verdict: PASS** for the slice 6 gate (AC 2). The organic-prompt weakness of the verify
description (S2 control 1/2) is unchanged by the rename and stays a separate `/eval` item.
