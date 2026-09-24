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
## E2E Walkthrough — /go front door — 2026-09-16 (uncommitted on d6c5e5b, branch routing)

Spec: specs/go-front-door.md (AC6)
Driver: the skill loaded through the Skill tool in the main context and followed step by step. Each entry quotes the `[ROUTE]` line verbatim and names where the chain stopped.

### AC6(a) — `/go how does task-registry choose a provider` — PASS

```
[ROUTE] lane=investigate | chain=inline evidence gathering; /checkpoint only if asked | reason: the goal asks how something works and requests no code; no issue reference, so the lane table decides.
```

Lane block appended to `tasks/todo.md` as five plain numbered lines under `## Lane: investigate — how does task-registry choose a provider`; `grep -c '^\s*\[ \]' tasks/todo.md` was unchanged by the block (the three pending rows are this build's own plan). Step 3 kept its line with `— skip: answered from source`. Reply cited `registry/config.py:795-805` (`select_provider`: explicit `provider =`, then GitHub remote plus authenticated `gh`, then local with two distinct reasons). `git diff --stat` excluding `tasks/todo.md` showed no source change from the lane.

### AC6(b) — `/go #135` (open issue labelled `bug`) — PASS on the exit-2 edge case; routine path shown on a local fixture

Live, in this repository, `task-registry workflow '#135'` exited 2:

```
upstream check: FAILED — these configured routine labels do not exist in github: design-decision, in-progress, needs-investigation, tech-debt
  A routine selecting on a label the tracker does not have finds nothing and exits 0. That is the halt this check exists to make loud.
exit=2
```

`/go` therefore refused the whole request, printed that message verbatim, and named the configuration file: `docs/task-tracking.md`, the target of the `Task tracking instructions:` line in `.claude/project.md`. No `[ROUTE]` line was emitted and no lane block was written — the spec's edge-case table row "workflow exits 2" is the behaviour exercised, not the routine path or the untriaged path, because the tracker is misconfigured against its own `[routines]` block (four selector labels absent on GitHub) and creating labels is an external write outside this build's authority.

Supplementary, deterministic: a throwaway local-provider fixture (`provider = local`, one task upserted with `--label bug`) run through the same command:

```
issue:    cache-survives-logout  Cache entry survives logout
routine:  fix
matched:  bug
chain:    /debug -> /build -> /quality-gate -> /wrap-up-session
exit=0
```

which yields the registry-routed line

```
[ROUTE] lane=fix | chain=/debug, /build, /quality-gate, /wrap-up-session | reason: registry routine fix owns the issue (matched label bug); chain is the registry's verbatim.
```

and proceeds straight into `/debug`: its issue intake read the task through `task-registry show cache-survives-logout` (exit 0, labels `bug`, summary present) and its Phase 0.5 prelude stops at `Reproduction confirmed: NO` — the first skill's own gate, not one of `/go`'s.

### AC6(c) — `/go rename _label_list to _csv_list` — PASS

Run in a detached worktree of HEAD so the rename's plan artifacts stay out of this tree.

```
[ROUTE] lane=refactor | chain=inline before-proof, /plan, /build, /quality-gate, /wrap-up-session | reason: "rename X to Y" is a structural change with no behaviour change requested and no defect cue.
```

Lane block appended (five plain numbered lines). Step 1 before-proof: three callers at `config.py:401,458,496`; characterization run `None -> ()`, `'' -> ()`, `' bug , tech-debt ,, ' -> ('bug', 'tech-debt')`, `'a' -> ('a',)`; no test names the helper directly. Step 2 `/plan`: wrote `specs/rename-label-list-to-csv-list.md` and one `[ ] TDD:` row, then asked "Does this spec and plan meet your requirements? Once you confirm with **'y'**, I'll begin the TDD loop." The walkthrough stopped there. Worktree `git status`: only `tasks/todo.md`, the new spec, and the copied `go` skill — no code touched.

## Triggerability eval — /go Mode A — 2026-09-16 (d7b6cf0 merged with origin/master as 30fc533)

Spec: specs/go-front-door.md (AC7). Mode A per `.agents/skills/eval/SKILL.md`: one organic prompt per confusable boundary, N = 2, each candidate a blind `general-purpose` sub-agent on the Builder tier in its own worktree cut from d7b6cf0 (the `go` skill committed and listed in every candidate's available-skills block — verified by grepping its description in all eight transcripts). Every prompt carried the no-push clause and a tool-call budget. Rubric, fixed before dispatch and withheld from candidates: FIRED = a `Skill` tool-use block loading `go`; secondary read = the lane in the `[ROUTE]` line versus the expected lane.

| Boundary | Prompt (abridged) | Expected lane | r1 | r2 | Tools used (r1 / r2) |
|---|---|---|---|---|---|
| fix-vs-perf | `test-routine-selectors.sh` now takes 4+ minutes and ends `3/61 FAILED` on AC12; something in the last registry commits did this | fix | NONE | NONE | Bash×29 Read×6 Grep×6 / Bash×19 Write×2 Read×2 |
| refactor-vs-feature | rename `_label_list` to `_csv_list`, behaviour must not change, both trees identical | refactor | NONE | NONE | Bash×17 Read×3 ToolSearch×1 Monitor×1 / Bash×4 Read×1 |
| investigate-vs-fix | `workflow '#135'` exits 2 with the upstream-label message; is the command wrong or the repo misconfigured? don't change anything | investigate | NONE | NONE | Bash×11 Read×1 / Grep×4 Bash×3 Read×1 |
| babysit | what is outstanding on PR #128; get it as close to merge-ready as you can, locally only | babysit | NONE | NONE | Bash×25 Read×2 / Bash×22 Read×3 |

Grader output (`grade-skill-loads.sh <transcripts> go`):

```
-> go: 0/8 FIRED, 0 MISROUTED, 8 NONE
```

No candidate emitted a `[ROUTE]` line, and no candidate loaded *any* skill: zero `Skill` tool-use blocks across all eight transcripts. Every candidate did the work by hand — the two rename candidates completed the rename in both trees; the two exit-2 candidates diagnosed the missing labels on the configured repository correctly and changed nothing; the two PR candidates found no review threads and green CI, then merged `origin/master` into a local branch; the two slowdown candidates traced the symptom to `_repo()` in d6c5e5b escaping the `gh` mock on Windows.

**Cue decision: no change to the lane table.** AC7 says a miss is a cue defect, but the cues live inside the skill and are consulted only after it loads. Nothing loaded — not `go`, not `/debug`, not `/plan` — so the miss is at description routing, which the spec already names as not the mechanism (the 2026-08-28 audit in `tests/test-skill-invocation-chain.sh`'s header). With zero loads of any skill there is no signal a description rewrite could target, and the explicit command is proven by AC6 above. Recorded as data for the pre-mortem's "nobody types /go" risk; the mitigations are the banner and CLAUDE.md, not the description.

**Grader defect found and fixed.** The first grading pass died with "holds a Skill block this parser cannot read — transcript format changed" on every transcript. The anchor was a bare `"name":"Skill"`, and transcripts now carry the tool schema inline as `{"name":"Skill","description":...}`, so eight clean transcripts produced zero measurements. `grade-skill-loads.sh` now anchors on `"type":"tool_use"` within the same object; `tests/test-eval-skill.sh` models the drift fixture as a tool-use block and adds the inline-schema fixture that must grade NONE.

## Suite + quality gate — /go front door — 2026-09-16 51721fd (branch routing)

Spec: specs/go-front-door.md (AC8). `bash tests/run.sh` run once in the main clone after the quality-gate commit, nothing edited while it ran; full output at the session scratchpad `final.log` (5918 lines).

```
RESULT: 8/43 test files FAILED
exit=1
```

Failing files, each compared with the clean baseline taken from a detached worktree at d6c5e5b (master before this branch) on the same Windows machine:

| File | Baseline (d6c5e5b) | This run (51721fd) | Verdict |
|---|---|---|---|
| test-install-sh.sh | 1/94 | 1/94 | pre-existing |
| test-routine-selectors.sh | 60/196 | 60/200 | pre-existing (master added 4 passing assertions) |
| test-routine-skills.sh | 2/64 | 2/64 | pre-existing |
| test-skill-invocation-chain.sh | 4/72 | 4/72 | pre-existing |
| test-sync-retirement.sh | 47/329 | 47/329 | pre-existing |
| test-task-escalation.sh | 1/62 | 1/62 | pre-existing |
| test-task-registry.sh | 44/348 | 44/398 | pre-existing (master added 50 passing assertions) |
| test-upstream-drift.sh | 1/64 | 64 passed | fixed upstream by the merged master commits |
| test-verification-skill-integration.sh | 2/90 | 2/90 | pre-existing |

Every failing file is in the baseline set with the same failure count; no file failed that passed on the baseline. All eight are the known Windows `gh`-mock class (`tasks/solutions/` — PATHEXT resolves the real `gh.exe` ahead of the mock, so mocked registry assertions fail locally regardless of the code under test). Verdict for AC8: **green modulo the pre-existing Windows set — zero regressions**; Linux CI is the authority for those eight.

Files this build owns, from the same run:

```
=== tests/test-go-lanes.sh ===              -> 187 assertions passed
=== tests/test-doc-conventions.sh ===       -> 693 assertions passed
=== tests/test-eval-skill.sh ===            -> 47 assertions passed
=== tests/test-skill-parity.sh ===          -> 103 assertions passed
=== tests/test-skill-frontmatter.sh ===     -> 280 assertions passed
=== tests/test-session-start.sh ===         -> 95 assertions passed
```

`/quality-gate` ran on the changed files before this suite: Phases 1–2 inline (nothing applied), Phase 3 dispatched to `software-design-expert-review` with the seven-item contract, verdict HOLD on one MUST-FIX (chain resolution checked only `.agents/skills/`). Applied in 51721fd: either-root resolution, comma-separated `chain=` for registry routes, `task-registry doctor` for the exit-2 config file, the skip marker named as the one post-write edit, the Chain column pinned equal to each playbook by test. Reported, not applied: the grader regex's key-order assumption (manual), the lane-block accumulation in `tasks/todo.md` that neither `/wrap-up-session` nor `/tidy` folds (advisory, human), and the spec's exact-text banner allowlist (spec decision).

**Wrap-up re-run — 2026-09-16, after the four dispatched review passes.** The review fixes (see the `fix(go)` wrap-up commit) changed the pinned counts: `tests/test-go-lanes.sh` 187 → 206, `tests/test-eval-skill.sh` 47 → 49, `tests/test-doc-conventions.sh` 693 → 694; `test-skill-parity` 103, `test-skill-references` 192, `test-skill-frontmatter` 280 and `test-solutions-schema` 31 unchanged and green. The doc-conventions count floats by one with the `tasks/` tree (a loop over files), so it is a floor, not an exact pin.

Full suite at the wrap-up head: `RESULT: 9/43 test files FAILED`, exit 1 — the eight Windows gh-mock files with the same per-file counts as above, plus `test-upstream-drift.sh` 1/64 on its wall-clock assertion ("helper cannot outlive the checker deadline": elapsed 2 s against a `-lt 2` bound, one-second granularity around a Windows process spawn). That file was 1/64 on the d6c5e5b baseline too, passed once at 51721fd, and fails alone with no other tests running; the branch changes no file it reads and no `lib.sh` helper it calls. Zero regressions; Linux CI on the PR is the authority.

## E2E Walkthrough — lane catalogue — 2026-09-16 (uncommitted on 6640873, branch routing)

Spec: specs/lane-catalogue.md. The user-facing surface is the new `task-registry lanes` command (AC4); everything else is module and test behaviour pinned by `tests/test-lane-catalogue.sh` (289 assertions). Run live in the `routing` worktree on Windows, `python3 -B`.

### AC4 — `task-registry lanes` — PASS

Exit 0; twelve rows, alphabetical, each with `lane:`, `chain:`, `ends:`; `selects:` on consumers, `cues:` on interactive lanes, `status: deferred — …` on `build`. No provider was selected (no `gh` call, no tracker line). First rows:

```
lane:    architect (producer)
  chain:   /sweep -> /wrap-up-session
  ends:    ready, docs-only PR carrying the session record
lane:    babysit (interactive)
  cues:    PR URL or number plus get it green, address the comments, anything outstanding, CI red
  chain:   /receive-review -> /debug -> /plan -> /build -> /wrap-up-session
  ends:    PR merge-ready, or a named blocker
lane:    build (consumer)
  chain:   /build -> /quality-gate -> /wrap-up-session
  ends:    ready PR
  status:  deferred — deferred behind the blockedBy provider capability (#97) and the routine itself (#98) — not runnable yet
```

### AC4 — `task-registry lanes fix` — PASS

Exit 0; the block, then the four numbered steps verbatim from `lanes/fix.md` (step 1 `` `/debug <ref>` ``), then `## Reply`. No `note:` line — this repository does not override the chain.

### AC4 — `task-registry lanes nope` — PASS

Exit 2: `task-registry: no lane named 'nope'; known lanes: architect, babysit, build, fix, improve, investigate, janitor, none, perf, plan, refactor, tidy`. One message, raised by `LaneCatalogue.lane()` and printed by the CLI.

### AC4 — `task-registry lanes investigate` — PASS

Exit 0 on this repository. The broken-configuration, override, missing-skill, producer-key and github-without-repository cases are fixture projects in `tests/test-lane-catalogue.sh`, not repeated here.

### AC9 — suite against the baseline — PASS

Baseline: `bash tests/run.sh` in a detached worktree at 6640873 (the untouched `routing` head): `8/44 test files FAILED`. This tree before the design-review fixes: `8/45 test files FAILED` — the same eight files, and a per-file diff of failing assertion names is empty. After the design-review fixes the four suites the CLI change touches were re-run and diffed again: `test-task-registry.sh` 44/398, `test-task-escalation.sh` 1/62, `test-routine-selectors.sh` 60/200, `test-skill-invocation-chain.sh` 4/72 — identical names. All eight are the known Windows `gh`-mock class. Files this build owns: `test-lane-catalogue.sh` 289 passed, `test-go-lanes.sh` 91, `test-routines-contract.sh` 95, `test-sweep-routines.sh` 161, `test-routine-branch.sh` 21, `test-doc-conventions.sh` 708, `test-skill-parity.sh` 112.

Design review: `software-design-expert-review` dispatched once with the seven-item contract on the implemented module, verdict GO with five SHOULD-FIX and six NITPICK findings; all agent-owned findings applied (producer keys refused under `[routines.skills]`, ghost lanes refused, wrapped steps refused, `## Reply` required, `_lanes` takes one load outcome, `doctor` run end to end against a broken catalogue, `TERMINAL_SKILL` alias and `Lane.path` removed, `NoReturn` on the refuser). The one human-owned advisory (is the catalogue project-extensible?) is raised in the final report for the PR author to decide; nothing was pushed from this session. Not dispatched: the quality-gate's Phase 1–2 reviewers — the corroboration they would have added is not claimed.

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

## E2E Walkthrough — grilling adoption — 2026-09-21 (worktree-grilling-adoption)

Spec: specs/grilling-adoption.md (AC 11, AC 12, AC 13)
Tree: the uncommitted build on `worktree-grilling-adoption`, on top of 7c37424 (master 0de3f8a, #156, plus the plan and spec commit). Committed by `/wrap-up-session` as 8d69510 on `worktree-grilling-adoption`; the wrap-up review then tightened the test pins, declared seed questions in `/grilling` § 1, added the opt-out clause to `/brainstorm` Step 3 and the read-only clause to `/grilling` § 4 — prose outside the round format, so the three verdicts above stand for that commit.
Claude Code: 2.1.277
Driver: print-mode sessions (`claude -p … --output-format json`), the plugin loaded from this worktree with `--plugin-dir` so the new skills are the ones under test, an isolated `CLAUDE_CONFIG_DIR` holding only credentials (no user-scope skills, no installed plugins), cwd the scratch worktree `.claude/worktrees/jplugin-routing` (detached eb5fdbd, `.claude/skills/` deleted), `MSYS_NO_PATHCONV=1`, `--max-budget-usd 1.50` per session — the S2 spike's setup. Every verdict below is read from the session `.jsonl` transcript (first user turn, `Skill` tool-use blocks, `Edit`/`Write` blocks), never from what a session said about itself.

### AC 11: typing `/grill-me <idea>` starts a ❓/➡️ round and leaves `git status` unchanged — PASS

Typed (`/jplugin:grill-me` on Claude Code, per the namespace sentence in CLAUDE.md): `/jplugin:grill-me Should we move this repository's nightly test suite from a cron job on the build box to a GitHub Actions schedule?`

Transcript first user turn: `<command-message>jplugin:grill-me</command-message> <command-name>/jplugin:grill-me</command-name> <command-args>…</command-args>` — the harness routed the typed command with `disable-model-invocation: true` in place. No refusal, so the flag stays `true`, the writing-skills note stands as written, and no `[AMBIGUITY]` line is emitted. Skill loads: `jplugin:grilling` (the front door delegated as its body says). Tools: Agent (one Scout-tier fact lookup), Bash, Skill. File writes: none. Reply: three numbered `❓ **Qn**` questions, each followed by a `➡️` recommendation; the lookup found no build-box cron in the repository and the round re-rooted on that fact instead of asking the superseded questions. `git status --short` in the cwd after the session, excluding that worktree's pre-existing modifications (dated 2026-09-18, before any probe): empty. Session 521c8b35, 2 turns, $1.16.

### AC 12: `/brainstorm` on a sample idea produces a first ❓/➡️ round and writes one resolved term to `tasks/concepts.md` before the spec is written; the sample term is reverted — PASS on the second run, first run recorded as the finding that changed the prose

Sample idea: `/jplugin:brainstorm Add a quarantine state for flaky tests: the routine runner skips a quarantined test for a number of runs and files an issue instead of failing the whole run.` Both runs: `--permission-mode acceptEdits`.

Run 1 (session c6a96db1, 13 + 1 turns, $2.60), prose as first written. Turn 1: `jplugin:grilling` loaded, six facts read from the tree first, then a six-question round in format; the reply named **quarantine** as "new project vocabulary" whose definition depended on Q2. Turn 2 answered all six recommendations; round 2 followed in format, no `Edit` at all, `tasks/concepts.md` untouched. Finding: the layer said "the moment it resolves" and the agent narrated the resolution without acting — the write had no concrete trigger. Fix, before run 2: brainstorm Step 3 and `references/domain-modeling.md` now state that a term resolves on the user's answer and the reply to that answer writes the entry before asking the next round, with `glossary: **term** written` as the visible line.

Run 2 (session 0a4920b5, 14 + 2 turns, $2.54), tightened prose. Turn 1: five-question round in format, `jplugin:grilling` loaded, no writes. Turn 2 answered Q1–Q5; the reply opened with one `Edit` to `tasks/concepts.md` inserting `- **quarantine** — the non-blocking state of a test whose failure must not stop an unattended routine run: …` under Project vocabulary, alphabetically between `producer routine` and `run stamp`, reported `glossary: **quarantine** written`, declined a standalone `flaky` entry as a standard industry term (the glossary-only rule, applied unprompted), then asked round 2. No spec, no `tasks/todo.md` row, no store document.

Revert: `git -C .claude/worktrees/jplugin-routing checkout -- tasks/concepts.md`; the diff is empty afterwards and this template's own `tasks/concepts.md` was never in a probe's cwd.

### AC 13: `/eval` Mode A triggerability of `grilling` from at least three organic brainstorm-shaped prompts — 5/6 FIRED (83%)

Mode A per `.agents/skills/eval/SKILL.md` and `references/probe-recipe.md`: three organic prompts, none naming a skill, each ending in the verbatim no-push clause — (1) quarantine flaky tests instead of failing the routine run, "help me think through the design and the options"; (2) let `/sweep` file to a Linear board instead of GitHub Issues, "explore the design space with me first"; (3) a handover note between sessions on long builds, "pressure-test it before we write a spec". N = 2 reps each, six sessions in parallel, `--permission-mode acceptEdits --max-turns 30`. Rubric fixed before any run: FIRED = a `Skill` tool-use block loading `jplugin:grilling`; MISROUTED = only other skills loaded; NONE = no Skill block. Graded with `.agents/skills/eval/scripts/grade-skill-loads.sh <transcripts> jplugin:grilling`:

| prompt | rep | turns | loaded | verdict |
|--------|-----|-------|--------|---------|
| 1 quarantine | 1 | 12 | jplugin:brainstorm, jplugin:grilling | FIRED |
| 1 quarantine | 2 | 14 | jplugin:brainstorm, jplugin:grilling | FIRED |
| 2 Linear board | 1 | 14 | jplugin:brainstorm | MISROUTED |
| 2 Linear board | 2 | 19 | jplugin:brainstorm, jplugin:grilling | FIRED |
| 3 handover note | 1 | 13 | jplugin:brainstorm, jplugin:grilling | FIRED |
| 3 handover note | 2 | 14 | jplugin:brainstorm, jplugin:grilling | FIRED |

`-> jplugin:grilling: 5/6 FIRED, 1 MISROUTED, 0 NONE`. `jplugin:brainstorm` fired in 6/6, so the model routed every organic prompt to the caller and the brainstorm → grilling chain held in 5 of 6. The MISROUTED session ran Step 3 inline from the brainstorm text — six `❓` questions with a `➡️` on each — without loading the primitive: the spec's "primitive does not load" edge case, minus its tell, because the caller's own Step 3 now carries the format. Not a `grilling` description defect (no prompt targets it directly); it is slack in the chain, and `tests/test-skill-invocation-chain.sh` keeps the handoff written down. Every reply was in the round format; no session wrote a file. Cost $7.31.

Not measured: the Workflow tool's sanitized-worktree fan-out from the probe recipe (no multi-agent opt-in in this session). Six print-mode sessions in one project-shaped scratch worktree stand in for it with the same blinding: no eval vocabulary in any path or prompt, and no session told it was being measured.

## E2E Walkthrough — plan-slices-and-handover — 2026-09-22 (feat/106-plan-slices-and-handover)

Spec: specs/plan-slices-and-handover.md (AC 15)
Tree: branch `feat/106-plan-slices-and-handover` at f6e9049 (base 87ff22c = origin/master), the quality-gate commit; the fixture's project-local skill copies were taken at 2556d29 (slice 6 closed), before the Phase 3 fixes in f6e9049 — none of those fixes (seeded `[x]` rows, unknown-blocker refusal, implicit slice, fenced decoy rows) was on a path this run exercised.
Claude Code: 2.1.277
Driver: two print-mode sessions (`claude -p … --output-format json`) in the fixture repository `.claude/worktrees/e2e-106` — its own git repo, `provider = local`, `require_write_approval = true`, the 106 skills copied to `.claude/skills/` and `.agents/skills/`, spec `specs/greeting.md` (stdlib greeting toolkit, § Decisions with 5 `user` rows). `MSYS_NO_PATHCONV=1 PYTHONUTF8=1`. The plan session ran `/plan` with the arguments "carry the settled decisions forward, treat any gap the six questions still leave as an assumed row, run every step to its end". The build session ran the build prompt the plan session printed, verbatim, with `--permission-mode acceptEdits` and a Bash allowlist (`--dangerously-skip-permissions` was refused by the harness). Every verdict below is read from the session `.jsonl` transcripts and the fixture's git history, never from what a session said about itself.

| session | id | turns | cost | wall clock |
|---------|----|-------|------|------------|
| plan | ee94098b | 39 | $2.60 | 531 s |
| build | d0ac3717 | 147 | $19.08 | 1757 s |

### The `/plan` session ends with the build prompt and files nothing — PASS

First user turn: `<command-name>/plan</command-name>`. Text at 15:58:59: `DECISIONS CARRIED: 5 from specs/greeting.md`; five `Edit` calls added rows 6–11 as `assumed` and grew the ACs to 10. Skill load at 15:59:51: `slice` with `specs/greeting.md` — `slice.py validate` (exit 0 after one spec fix), four `upsert --derive-id plan --spec specs/greeting.md --fold-title …` dry runs and no `--apply`, `slice.py ready --spec … --index tasks/todo.md`, one `Write` of `tasks/todo.md` with the `## Plan: greeting` block (4 slices; 1 and 2 disjoint, 3 blocked by 1 and 2, 4 by 3). Last text at 16:03:55: `Spec and plan are ready to be built. Start a fresh session with this prompt:` followed by the prompt. Filing: `git ls-tree d959b1a` (the commit of the plan session's tree) has no `tasks/details/`; the local tracker's first record appears in aa61cf8, written by the build session.

### The fresh session files the slices before it builds — PASS (from the prompt's instruction 1, not `/build`'s pre-flight)

First user turn is the build prompt verbatim (no slash command). Skill loads: `slice` with `specs/greeting.md --file --approve` at 16:05:49, then `build` at 16:07:31 — the session ran the prompt's instruction 1 itself before `/build` loaded, so `/build`'s pre-flight found every header linked and filed nothing. The prompt and the pre-flight were two filing sites; the prompt template now names the pre-flight as the one site. Filing: one `upsert … --derive-id plan --spec specs/greeting.md --fold-title --title '<slice>'` dry run followed by the same command with `--apply --approve`, per slice, in table order (16:06:26 → 16:07:20); the reply printed four lines of the form `✓ Filed: plan.specs-greeting-md.greet-module → local, publication pending`. `tasks/details/` holds the four records. The build's first `slice.py ready --index tasks/todo.md --spec specs/greeting.md` (16:09:15) printed `ready: 1 greet module` / `surface: src/greeting/__init__.py, src/greeting/greet.py, tests/test_greet.py` / `ready: 2 farewell module` / `surface: src/greeting/farewell.py, tests/test_farewell.py` — two disjoint slices, no `intersects:` line.

### `DECISIONS CARRIED` — observed in the plan session, not in the build session

The line is `/plan` Step 1 output and appeared there (above). The build session printed nothing of the kind; nothing in `/build` asks it to. AC 15 places the phrase in the build session's output — read as "the run shows it" it passes, read literally it does not. Recorded as written; the spec sentence is the thing to tighten.

### Parallel dispatch of two disjoint slices — NOT OBSERVED

`ready` named slices 1 and 2 together and the surfaces were disjoint, so the pre-condition held. The session built both inline, in sequence: `Write tests/test_greet.py` → `Write src/greeting/greet.py` → commit aa61cf8 (16:09:35), then `Write tests/test_farewell.py` → `Write src/greeting/farewell.py` → commit 66e9781 (16:10:38). The transcript has five `Agent` calls in total, all reviewers (`software-design-expert-review` for the quality gate; three `code-reviewer` and one `critic` for wrap-up) and none a coder. The session's own closing report says why: "I ran the slices inline rather than dispatching per-slice agents: each is 1–3 files of stdlib Python, so dispatch overhead exceeded the work." § Parallel Dispatch in `/build` is an assessment, not a mandate, and the fixture's slices are below any threshold at which an agent would dispatch — so this run cannot show the parallel path. A fixture whose two ready slices are each large enough to earn a sub-agent is what the claim needs.

### A handover read by a blocked slice — PARTIAL

Each slice closed with a `> Handover:` blockquote under its heading in `tasks/todo.md`, e.g. slice 1: `> Handover: d959b1a..aa61cf8 — src/greeting/greet.py (greet(name, *, formal=False)), empty src/greeting/__init__.py, tests/test_greet.py (3 tests, green).` Slice 3 started only after `ready` printed `ready: 3 CLI entry point` (16:10:56) and its `src/greeting/cli.py` imports `from greeting.greet import greet` and `from greeting.farewell import farewell` with the call shapes the two handovers state. But the same context wrote both handovers minutes earlier — there was no delegation prompt into which a handover was pasted and no fresh reader whose only source was the blockquote. The handover's *content* was correct and sufficient; that a blocked slice *depends on reading it* was not demonstrated for the same reason the parallel path was not: nothing was dispatched.

### A surface report — PASS

After every slice commit the session ran `slice.py check --spec specs/greeting.md --slice <n> --base <previous head>`; each exit 1 with only bookkeeping paths: slice 1 `undeclared: tasks/details/plan.specs-greeting-md.*.md (4), tasks/todo.md`; slices 2 and 3 `undeclared: tasks/todo.md`; slice 4 `undeclared: tasks/e2e-log.md, tasks/todo.md`. No `untouched:` line. Each heading carries a `> Surface report:` line quoting the output and naming the paths as the pre-flight filing and plan index. Finding: `check` reports the registry's own writes as undeclared on every slice, so its exit code can never be 0 on a slice that files or hands over — `tasks/todo.md` and the tracker's detail directory belong to the build, not to any slice's surface (backlog).

### Two setup findings that bound what this run proves

1. **The harness loaded the user-scope skill copies.** Both sessions' `Skill` results name `~/.claude/skills/plan`, `…/build`, `…/quality-gate`, `…/wrap-up-session` as the base directory; only `slice`, which has no user-scope copy, resolved to the fixture's `.claude/skills/slice`. Those user-scope copies predate this branch (`grep -c 'DECISIONS CARRIED' ~/.claude/skills/plan/SKILL.md` = 0; no `Slice Close` in `~/.claude/skills/build/SKILL.md`). Each session noticed the vocabulary mismatch on its own — plan at 15:56:16 ("the argument mentions 'the six questions', which isn't in the loaded version"), build at 16:08:57 ("the project-local build skill differs from the one loaded — it's slice-aware") — read the project-local `SKILL.md` and followed it. So the skill *text* under test drove both sessions, but the routing that put it in front of them was the agent's judgement, not the harness. An isolated `CLAUDE_CONFIG_DIR` (the grilling-adoption walkthrough's setup) would remove this.
2. **Dispatched reviewers had no shell.** Every review agent reported Bash and PowerShell denied under the allowlist and reasoned from source only; the main context re-ran their runtime claims. Not a slice-workflow defect, but it means the fixture's review findings were verified by one context.

### Wrap-up

`/wrap-up-session` ran four dispatched passes, applied 3 MUST-FIX (cd3ae87 `fix: let help flags reach the parser`), and corrected its own e2e log (c6a5b98). No `## Handovers` section was produced, in a PR body or in the commit message the skill names for a repository with no tracker — the wrap-up ran from the user-scope `~/.claude/skills/wrap-up-session` copy, which predates the section (setup finding 1 below). AC 13 therefore has doc-pin evidence only; the first `## Handovers` section is the PR of this branch.

Verdict for AC 15: the planning-session contract, the pre-flight filing, the ready set, the handover blocks and the surface reports were observed and are cited above; parallel dispatch and a handover consumed across a dispatch boundary were not, because the fixture's slices were too small for the session to dispatch at all. Fixture commits 812bb0d…c6a5b98 are kept in `.claude/worktrees/e2e-106` (git-excluded) for re-reading; they are not part of this repository.

## E2E Walkthrough — quality-receipt-closure — 2026-09-23 (feat/163-wrap-up-reuses-quality-receipt)

Spec: specs/quality-receipt-closure.md (Decision 13, slice 6 `Verify:`; ACs 8–13 exercised live)
Tree: c445abb (base 3525c70), pushed; PR #191
Driver: this PR's own interactive `/wrap-up-session`. It followed the repository copy of the skill, because the installed `jplugin` plugin copy predates the branch. Every observation below was fed to `closure.py step`, and every action it printed was performed as written. The verdicts are read from the engine's printed lines and from `gh`, never from prose about them.

### Run 1 — terminal stopped (suite), before any push — PASS (a legitimate stop)

1. `receipt.py check` → `stale diff-changed parent 39e94696… delta specs/review-context-contract.md` (Step 3.2 reconciled that spec). Engine: `action quality-gate scope=delta`.
2. Delta gate: phases 1–4 inline, phase 5 affected tests under WSL at cc94bf0, 33/33 green. Receipt `79ad2899` GO, parent the human-approved HOLD `39e94696`. `gate: GO` → `action check-receipt` → `valid GO` → `action run-suite`.
3. Full suite (WSL, cc94bf0): 1/57 files red, `tests/test-skills-table.sh`, a README table left stale by slice 2. `suite: red` → `terminal stopped state=suite reason=tests`; state file `phase: done`, `pr_open: false`. No PR existed, so no draft was needed.

### Run 2 — terminal complete — PASS

The fix commit c445abb re-rendered the README table.

1. The `done` state loaded fresh. `receipt.py check` → `stale diff-changed … delta README.md` → `action quality-gate scope=delta`.
2. Delta gate: affected tests at c445abb, 40/40 green. Receipt `fa15ba1d` GO → `action check-receipt` → `valid GO fa15ba1d` → `action run-suite`.
3. Full suite (WSL, c445abb, tree a57c70bb): 57/57 green → `action commit-push`.
4. `git push -u origin feat/163-wrap-up-reuses-quality-receipt` (hooks enabled, no rebase, no force) → `push: ok` → `action pr-sync`.
5. Linkage check exit 0 on the draft; `gh pr create` → #191 → `pr: 191` → `action mergeability`.
6. `gh pr view 191 --json mergeable` → `MERGEABLE` (`mergeStateStatus: UNSTABLE`, checks still running, which is not a trigger) → `action watch-ci`.
7. No required checks, so the loop watched all of them: `gh pr checks 191 --watch` in the background → `test pass 1m9s` → `ci: pass` → `action verify-deploy`.
8. No `## Deployment Targets` section and no `tasks/deployments/*.md` → `deploy: n/a` → `action record-closure note=not applicable — no ## Deployment Targets section`.
9. Live body linkage check exit 0; `gh pr edit 191 --body-file …` re-synced `## Closure` → `record: recorded` → **`terminal complete state=record reason=closure recorded`**. State `phase: done`, `pr_open: true`.

Not exercised live: CI repair, conflict repair, deployment re-entry and mark-draft. `tests/test-closure.sh` and its 8 fixture scenarios cover those rows.

Finding: a Step 6 fix edits the tree the receipt covers, and the engine has no `suite: fixed` observation. The honest route is the one taken here: end the run on `suite: red`, commit the fix, and start a fresh run whose receipt check re-enters the gate at delta scope. The affected-test selector also does not map a `SKILL.md` frontmatter change to `tests/test-skills-table.sh`. Both are recorded as follow-ups in #191.

## Rebase onto the plugin-era harness — lane catalogue / /go — 2026-09-24 (branch routing, merge of origin/master 2d68d66)

PR #147 was `CONFLICTING` against master after #156 (plugin ships the canonical tree, `.claude/skills/` retired), #177 (single `AGENTS.md`, `CLAUDE.md` a pointer, hooks under `.agents/hooks/`), #176 (`/slice`), #184 (cached suite, `tests/affected.sh`) and #191 (quality receipt). Resolution, all in the `routing` worktree:

- `.claude/skills/**` — every mirror this PR added or edited is deleted with the retired root; the lane files, `lanes.py` and the `/go` skill exist once, under `.agents/skills/`.
- `CLAUDE.md` — master's one-line pointer. The `/go` entry-point sentence moved to `AGENTS.md` § *Workflow*, before step 1; `tests/test-doc-conventions.sh` pins it there and no longer pins a CLAUDE.md skills table or a banner line.
- `README.md` — the skills table is rendered from frontmatter (`scripts/render-skills-table.py`); re-rendered, `--check` silent, `/go` row present.
- `.agents/hooks/session-start.sh` — master's version; the hook lists no skills since the plugin, so the `/go` banner rows and `tests/test-go-lanes.sh` AC5 are gone. The host sweep now covers `.agents/hooks` and uses the skill's own file as its positive control.
- `task-registry.py` — kept master's `LEGACY_POINTER_*` imports, kept this PR's lazy `registry_config.DEFERRED_ROUTINES`.
- `lanes/janitor.md` — `/verify` → `/verify-evidence` (renamed on master; the all-token sweep in `tests/test-lane-catalogue.sh` would have refused the stale name).
- Skill roots are `.agents/skills/` only (`SKILL_ROOTS` on master); `/go` and `task-registry` SKILL.md say so; `specs/lane-catalogue.md` and `specs/go-front-door.md` carry a rebase note and drop the mirror/banner clauses.
- Task registers (`todo`, `history`, `e2e-log`, `checkpoint`, `concepts`) — union of both sides; the glossary keeps this PR's lane-derived *skill chain* and master's one-tree *syncable root*.

Owned tests on the merged tree, run solo: `test-lane-catalogue.sh` 228 passed, `test-go-lanes.sh` 49, `test-doc-conventions.sh` 754, `test-routines-contract.sh` 94, `test-sweep-routines.sh` 135, `test-routine-branch.sh` 21, `test-skills-table.sh` 75, `test-instruction-budget.sh` 24, `test-skill-references.sh` 161, `test-skill-frontmatter.sh` 156, `test-plugin-manifest.sh` 27, `test-syncable-paths.sh` 27. Full-suite comparison against a detached `origin/master` worktree follows below.
