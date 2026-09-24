---
status: draft
implementation_paths:
  - .agents/skills/task-registry/lanes/*.md
  - .agents/skills/task-registry/scripts/registry/lanes.py
  - .agents/skills/task-registry/scripts/registry/config.py
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/SKILL.md
  - .agents/skills/task-registry/templates/task-tracking.md
  - .agents/skills/go/SKILL.md
  - .agents/skills/wrap-up-session/references/routines.md
  - tests/test-lane-catalogue.sh
  - tests/test-go-lanes.sh
  - tests/test-routines-contract.sh
  - tests/test-routine-selectors.sh
  - tasks/concepts.md
---

# The lane catalogue — one definition per lane, read by both routers

> Supersedes the *No `[lanes.skills]` configuration section* decision in
> `specs/go-front-door.md` and the `TODO(shortcut):` it left in
> `.agents/skills/go/SKILL.md`. Written 2026-09-16 on the `routing` branch during
> review of PR #147. Rebased 2026-09-24 onto the plugin-era harness: `.claude/skills/`
> is retired (#156), so the lane files have no mirror, and `CLAUDE.md` is a pointer
> to `AGENTS.md` (#177), so the `/go` entry-point sentence lives there.

## Problem

Two routers choose what an agent runs next. The scheduled one reads an issue's
kind label and answers with a **routine** (`task-registry workflow`). The
interactive one reads a goal in plain words and answers with a **lane** (`/go`).
They were built as separate vocabularies:

| Registry routine | `/go` lane | Relationship today |
|---|---|---|
| `fix` | `fix` | same chain, pinned equal by test |
| `improve` | `feature` | same idea, different name, no pin |
| `plan`, `build`, `janitor`, `architect`, `tidy` | — | reachable from `/go` only through `#N` |
| — | `investigate`, `refactor`, `perf`, `babysit`, `none` | no registry equivalent |

Three defects follow from the split:

1. **The `[ROUTE] lane=` field leaks routine names.** For a labelled issue `/go`
   prints `lane=<routine>`, so `lane=improve` and `lane=plan` appear although no
   lane table row or playbook carries those names. The documented vocabulary is
   seven values; the real one is thirteen.
2. **The `fix` chain is stated six times.** `routines.md` § *fix — steps*,
   `DEFAULT_ROUTINE_SKILLS` in `config.py`, the template's `[routines.skills]`
   block, this project's `docs/task-tracking.md`, the `/go` lane table row, and
   `lanes/fix.md`. Two of the pairs are pinned by test; the rest drift freely.
3. **Every routine attribute is a Python constant transcribed from prose.**
   `CONTRACT_ROUTINES`, `PRODUCER_ROUTINES`, `DEFERRED_ROUTINES`,
   `DEFAULT_SELECTORS` and `DEFAULT_ROUTINE_SKILLS` each restate one column of the
   routine table in `routines.md`. Adding a routine is a documented five-place
   edit (`routines.md` § *build is deferred*).

The go spec rejected a shared definition on three grounds: the registry requires
every chain to end at `/wrap-up-session`, it has no concept of a prompt, and its
chain steps must be skills. All three are true of *routines* and none is true of
the lane as a class. They are attributes, not structure.

## Behavior

A **lane** is one markdown file under `.agents/skills/task-registry/lanes/`,
named for the lane. The file is the whole definition: frontmatter that both
routers read, numbered steps `/go` records and the registry derives a chain from,
and a *Reply* section for the interactive close. The lane file is the **source**
of a lane's chain, selector, producer status and deferral. Three mirrors remain,
each pinned to the catalogue by a named test rather than trusted:

| Mirror | Why it stays | Pinned by |
|---|---|---|
| The routine table in `routines.md` | the contract document is what a human reads first | `tests/test-routines-contract.sh` |
| `routine_branch.CONTRACT_ROUTINES` | a different skill with no import path into the registry package | `tests/test-routine-branch.sh` (through the table) |
| The template's `[routines.skills]` block | a project copies it to declare its own chains | `tests/test-lane-catalogue.sh` (new pin) |

`DEFAULT_KIND_PRECEDENCE` also stays in `config.py`: it orders labels across
lanes and `_refuse_divergent_label_sets` requires its domain to equal the
selector union, so adding a `selects` label to a lane still edits that one tuple.
Adding a routine after this spec therefore touches the lane file, the precedence
tuple, the table row, `routine_branch.py` and the template block — five places,
every one of them pinned, where today's five are pinned in two pairs.

### The lane file

```markdown
---
routine: consumer
selects: bug, tech-debt
cues: broken, fails, wrong output, regression, error text pasted
ends: ready PR
---
# Lane: fix

Runs when the goal reports something broken, or an issue carries a `fix`
selector label. A typed defect and a labelled issue run identically.

1. `/debug <ref>` — root cause before code; the prelude stops before any edit until a candidate is confirmed
2. `/build` — TDD against the reproduced failure; no fix ships without a failing test that now passes — **non-skippable**
3. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
4. `/wrap-up-session` — review, tests, commit, push, PR — **non-skippable**

## Reply

The root cause with its `file:line`, the failing test that now passes, and the
PR URL. Name every step skipped and why.
```

**The name is the filename stem.** `lanes/fix.md` defines `fix`. It is stated
once, validated against `[a-z][a-z-]*`, and cannot disagree with itself — there
is no `lane:` key to drift from it and no duplicate to detect.

**Frontmatter keys.** Plain `key: value` lines between `---` fences; lists are
comma-separated. No YAML library — the same shape `[routines.selectors]` already
uses.

| Key | Required | Read by | Meaning |
|---|---|---|---|
| `routine` | no | registry | `consumer` or `producer`. Present means this lane is a **contract routine** the scheduler may run. Absent means interactive-only. |
| `selects` | no | registry | Provider labels this lane's selector claims. Allowed only with `routine: consumer`. A consumer with no `selects` is selectable by nothing (`build`, whose selector is not label-based). |
| `cues` | no | `/go` | The goal phrases that pick this lane. Present means the lane appears in `/go`'s match table. Absent means the lane is reached only through a registry answer. |
| `ends` | yes | both | The terminal artifact, free text: `ready PR`, `draft PR`, `a cited answer, no diff`. |
| `deferred` | no | registry | The reason this routine is not runnable yet. Present means deferred; `workflow` prints it. Allowed only with `routine`. |

**Step grammar.** A step is a line `N. <text>` at column 0, `N` ascending from 1.
A step whose text opens with a backticked skill — `` `/name`` followed by a space,
backtick, or argument — is a **skill step**, unless the step ends with
` — optional`, which makes it an **inline step** that happens to name a skill.
Everything else is an inline step. The lane's **chain** is the skill steps' names
in order. A skill named anywhere else in a step ("unlike `/plan`, this does not
ask") is prose and never enters the chain — but every `/skill` token anywhere in
a lane file must still resolve on disk, pinned by `tests/test-lane-catalogue.sh`,
so a prose-named alternative (`improve`'s `/system-design-planning`) is found
before work starts, not at the step.

The first skill step's argument is written `<ref>`. A registry-routed run
substitutes the issue reference (`/debug #42`); an interactive run substitutes
the goal text. One definition serves both routers because the argument is the
only thing that differs between them.

**Rules checked at load** (a shipped lane that breaks one is a template defect,
so the catalogue refuses to load and names the file):

- The filename stem matches `[a-z][a-z-]*`.
- A `routine` lane's chain ends at `/wrap-up-session` — the rule
  `_refuse_unterminated_chains` already enforces for configured chains, now
  applied to the shipped definitions too. An interactive-only lane carries no
  terminal rule; `investigate` ends with an answer.
- `selects` only on `routine: consumer`; `deferred` only on `routine` lanes.
- Every frontmatter key is one of the five above. An unknown key is refused, not
  ignored: a typo in `selcts` would otherwise silently make a routine unselectable.
- Steps are numbered from 1 without gaps; at least one step; no step is a
  checkbox row (`/build` dispatches every `[ ]` row it finds in `tasks/todo.md`).
- A step is one line. An indented line directly under a step is a wrapped
  step and is refused — silently dropping it would lose the tail from the
  playbook and, if it carried the skill or ` — optional`, from the chain.
- A lane is a routine (`routine:`), interactive (`cues:`), or both. One with
  neither is reachable by no router and is refused rather than listed.
- A `## Reply` section is present. `/go` copies it as what the lane ends
  with, so an absent one would be recorded as empty evidence.

### The catalogue module

`registry/lanes.py` is the one reader. Its interface is small and its
implementation hides the grammar above:

```python
catalogue()                           # memoised; reads the shipped lanes/ directory beside the package on first call
catalogue().lane("fix")               # -> Lane(name, routine, selects, cues, ends, deferred, steps, chain, reply)
catalogue().names                     # every lane, alphabetical
catalogue().routines                  # names with `routine:` set — was CONTRACT_ROUTINES
catalogue().producers                 # names with `routine: producer` — was PRODUCER_ROUTINES
catalogue().deferred                  # name -> reason — was DEFERRED_ROUTINES
catalogue().selectors                 # consumer name -> labels — was DEFAULT_SELECTORS
catalogue().chains                    # CONSUMER name -> chain — was DEFAULT_ROUTINE_SKILLS
catalogue().interactive               # lanes with cues, for /go's table
load_catalogue(directory)             # the un-memoised reader, for fixtures
```

`chains` covers **consumer** routines only — `plan`, `fix`, `improve`, `build` —
which is the domain `DEFAULT_ROUTINE_SKILLS` and `[routines.skills]` have today,
so `workflow`'s output and every `tests/test-routine-skills.sh` assertion stay as
they are. A producer's chain is read from its lane through `lane(name).chain`
and is never project-configurable; `[routines.skills]` has no producer key today
and gains none.

**Loading is lazy and its failure is a `ConfigError`.** Nothing reads a lane
file at import. `config.py` keeps its public names — `CONTRACT_ROUTINES`,
`PRODUCER_ROUTINES`, `DEFERRED_ROUTINES`, `DEFAULT_SELECTORS`,
`DEFAULT_ROUTINE_SKILLS` — as lazy module attributes (a module `__getattr__`)
that resolve to `catalogue()` views on first access, so every existing caller
and test keeps working and the literals move out of Python. `load_config` calls
`catalogue()` itself; a lane file that breaks a load rule raises
`LaneCatalogueError`, a `ConfigError` subclass, so it flows through the path
every command already has for a broken configuration. Under `strict=False` —
the `doctor` path — the fault is recorded on the `Config` and `doctor` prints a
`catalogue:` line naming it instead of dying before it can run. `import
registry.config` therefore stays side-effect free, and a test that imports it is
not a lanes-directory test.

`DEFAULT_KIND_PRECEDENCE` stays in `config.py`: it orders labels across lanes and
belongs to no one lane.

The `[routines.skills]` and `[routines.selectors]` project overrides are
unchanged in shape and semantics. They replace the catalogue's routine chains and
selectors wholesale, and every validator on them (`CONTRACT_ROUTINES` membership,
terminal step, on-disk skills, selector-without-chain) runs exactly as today.

### The `lanes` command

```
task-registry lanes              # one row per lane
task-registry lanes <name>       # one lane's playbook
```

`lanes` prints every lane as a table: name, routine kind or `interactive`,
selectors, cues, the **effective** chain, and the terminal artifact. The
effective chain is `config.routine_skills.get(name, lane.chain)`: the project's
`[routines.skills]` entry when the lane has one, else the shipped chain. So
`/go` and `workflow` print the same chain for the same lane, and a producer or
interactive-only lane prints its shipped chain. A deferred lane's row says so.

`lanes <name>` prints the lane's frontmatter summary, its numbered steps
verbatim, and its *Reply* section. It exits 2, naming the skill and the lane,
when a chain step is not on disk under either skill root — the "resolve the chain
before writing anything" rule `/go` currently states in prose, moved into the
module that owns the chain. When the effective chain differs from the file's
chain, it prints one `note:` line saying `[routines.skills]` replaced the shipped
chain and the steps shown are the shipped playbook. An unknown name exits 2
listing the known ones.

**`lanes` reads no tracker.** Every other registry command needs a provider to
do its job; `lanes` needs a directory read and, for a routine lane, one
configuration block. So it never selects or builds a provider — no `git remote`,
no `gh auth status` subprocess — and it loads the configuration with
`strict=False`. A configuration that cannot be read does not block a question
about how the code works: an interactive-only lane prints and exits 0, a routine
lane's row shows the shipped chain with `(shipped — configuration could not be
read: <error>)`, and only `lanes <routine lane>` by name exits 2 with that error,
because running a routine lane on a chain the project may have overridden is the
one case where the configuration is load-bearing. The issue-referenced path is
unchanged: `workflow` still exits 2 on a misconfigured tracker and `/go` still
refuses to route around it.

`[AMBIGUITY] whether lanes inherits the full command preamble (strict config,
provider selection) | options: A) inherit — a misconfigured tracker blocks every
/go goal B) narrow — no provider, non-strict config, exit 2 only for a routine
lane by name | picked: B | reason: today no interactive lane touches the
registry; A would make a typo in docs/task-tracking.md refuse "how does X
work" and add a gh subprocess to every goal.`

### What each consumer does with the catalogue

**`task-registry workflow`** is unchanged in output. Its `chain:` line already
reads `config.routine_skills`; that map now comes from the catalogue.

**`/go`** loses its lane table and its `lanes/` directory. Step 1 becomes: for an
issue reference, run `workflow` as today; otherwise run `lanes`, match the goal
against the `cues` column, apply the precedence rule (unchanged: `investigate`
decided first by "answer or change"; `fix` outranks `perf` outranks `refactor`;
a defect cue outranks `improve`; `none` when nothing matches), and print
`[ROUTE]`. Step 2 copies the steps from `lanes <name>`. The `lane=` vocabulary
is exactly the catalogue's names, so a registry-routed `lane=improve` is a lane
like any other. `chain=` names the recorded steps' skills; when `improve`'s
inline first step chooses `/system-design-planning` over `/plan`, the `/plan`
row is kept with ` — skip: spec written by /system-design-planning`, which is the
step ledger's own convention.

**`routines.md`** keeps everything that is not a per-lane fact: why there is no
autonomy computation, kind precedence, priority, claim and branch conventions,
closure on merge, the step ledger, and both spines. Its routine table stays and
is pinned equal to the catalogue by test. Its per-routine `### <name> — steps`
sections shrink to one sentence naming the lane file plus any rationale the lane
file does not carry; the step rows themselves live only in the lane file.

**`routine_branch.py`** keeps its own `CONTRACT_ROUTINES` tuple. It is a
different skill with no import path into the registry package, and it already
carries a test pinning its tuple to the routine table. That pin becomes
transitive to the catalogue. Naming the mirror is the honest floor; importing
across skill directories is not worth the coupling for seven strings.

### The lanes

Twelve files. The five that exist today move; `feature` is folded into
`improve`; `none` becomes a file; the seven routines gain files.

| Lane | `routine` | `selects` | `cues` | Chain (derived) | `ends` |
|---|---|---|---|---|---|
| `plan` | consumer | design-decision | spec only, decide between, design decision, no implementation yet | `/plan`, `/wrap-up-session` | draft PR carrying a spec |
| `fix` | consumer | bug, tech-debt | broken, fails, wrong output, regression, error text pasted | `/debug`, `/build`, `/quality-gate`, `/wrap-up-session` | ready PR |
| `improve` | consumer | enhancement, documentation | add, change, support, new behaviour | `/plan`, `/build`, `/quality-gate`, `/wrap-up-session` | ready PR |
| `build` | consumer | — | — | `/build`, `/quality-gate`, `/wrap-up-session` | ready PR (deferred: #97/#98) |
| `janitor` | producer | — | — | `/sweep`, `/wrap-up-session` | docs-only PR carrying the session record |
| `architect` | producer | — | — | `/sweep`, `/wrap-up-session` | docs-only PR carrying the session record |
| `tidy` | producer | — | — | `/tidy`, `/wrap-up-session` | PR carrying the record and Tier 0 repairs |
| `investigate` | — | — | how does X work, why was Y built this way, is Z safe, compare A and B | (none — its `/checkpoint` step ends ` — optional`) | a cited answer, no diff |
| `refactor` | — | — | rename, extract, inline, dedupe, move, no behaviour change | `/plan`, `/build`, `/quality-gate`, `/wrap-up-session` | PR quoting the before and after proof |
| `perf` | — | — | slow, latency, memory, takes N seconds, a profile attached | `/debug`, `/build`, `/quality-gate`, `/wrap-up-session` | PR quoting baseline and after numbers |
| `babysit` | — | — | PR URL or number plus get it green, address the comments, CI red | `/receive-review`, `/debug`, `/plan`, `/build`, `/wrap-up-session` | PR merge-ready, or a named blocker |
| `none` | — | — | no lane matches, or the goal is large or unclear | `/brainstorm` | whatever `/brainstorm` produces |

`improve`'s first step is an inline decision — choose `/brainstorm`,
`/system-design-planning`, or straight to `/plan` by CLAUDE.md § *Spec First*'s
criteria, skipped when the issue already links a merged spec — so its derived
chain stays the `improve` routine's chain and the interactive route keeps the
choice `feature` had. `babysit`'s red-job and requested-change branches become
two skill steps, each skipped with a reason when its case does not apply; that is
the step ledger's own convention and it makes the chain linear.

## Inputs

- The twelve lane files, shipped with the registry under
  `.agents/skills/task-registry/lanes/` — the one canonical tree since #156.
- `docs/task-tracking.md` `[routines.skills]` / `[routines.selectors]`, unchanged.
- `task-registry lanes [name]` from `/go`; `task-registry workflow <ref>` as today.

## Outputs

- `task-registry lanes` table and `lanes <name>` playbook, as above.
- `workflow`'s output, byte-for-byte as today for every existing case.
- `/go`'s `[ROUTE]` line and lane block, with `lane=` drawn from the catalogue.

## Edge Cases

| Case | Behaviour |
|---|---|
| A shipped lane file fails a load rule | `catalogue()` raises `LaneCatalogueError` naming the file and the rule. Every command that loads configuration strictly exits 2 with that message; `doctor` still runs and reports it on its `catalogue:` line. A broken shipped definition is a template defect and is never routed around. |
| A project's `[routines.skills]` overrides `fix` | `workflow` and `lanes` both print the override. `lanes fix` shows the shipped steps with a `note:` that the chain was replaced. |
| A project's `[routines.selectors]` names an interactive-only lane (`refactor = perf`) | Refused at load exactly as an unknown routine is today: `refactor` is not in `catalogue.routines`. |
| A project's `[routines.skills]` names a producer (`janitor = /sweep, /wrap-up-session`) | Refused at load: a producer's chain is shipped, not project-configurable, which is what keeps `catalogue.chains` a consumers-only domain. |
| `/go` matches a goal to a routine lane (`fix`, `improve`, `plan`) | Runs that lane's steps. The scheduled spine (select, claim, branch) is not part of the lane; `/go` never runs it. |
| `lanes <name>` for a lane whose chain names a skill absent from both roots | Exit 2 naming the skill and the lane. Nothing is written. |
| `lanes` with a configuration that cannot be read | The table prints; routine rows carry the shipped chain and the error. `lanes <interactive lane>` exits 0; `lanes <routine lane>` exits 2 with the error. No provider is touched. |
| `lanes` for a lane whose `/skill` appears only in prose | Not in the chain, not checked by the command; `tests/test-lane-catalogue.sh` pins that every `/skill` token in every lane file resolves on disk. |
| A lane file names a skill in prose but not at a step's head | Not in the chain. The step is inline. |
| Two lane files defining the same lane | Cannot happen: the name is the filename stem, so the filesystem holds one file per lane. |

## Acceptance Criteria

- [x] **AC1** `registry/lanes.py` loads every file under the shipped `lanes/` directory on first call to `catalogue()`, never at import, derives each chain by the step grammar, and exposes `routines`, `producers`, `deferred`, `selectors`, `chains` (consumers only), `interactive`, `names` and `lane(name)`. `config.py`'s `CONTRACT_ROUTINES`, `PRODUCER_ROUTINES`, `DEFERRED_ROUTINES`, `DEFAULT_SELECTORS` and `DEFAULT_ROUTINE_SKILLS` resolve lazily to those views and contain no lane literal; `import registry.config` reads no lane file.
- [x] **AC2** The loader raises `LaneCatalogueError` (a `ConfigError`) naming the file for: a filename stem outside `[a-z][a-z-]*`, an unknown frontmatter key, `selects` without `routine: consumer`, `deferred` without `routine`, a routine chain not ending at `/wrap-up-session`, a step gap or checkbox step, a step wrapped onto an indented line, a lane with neither `routine` nor `cues`, and a missing `## Reply` section. `doctor` on a project whose shipped catalogue is broken still runs to completion — exiting 1, as for any configuration fault — and prints a `catalogue:` line naming the fault once.
- [x] **AC3** Twelve lane files exist under `.agents/skills/task-registry/lanes/` with the attributes in *The lanes*; `.agents/skills/go/lanes/` no longer exists. Every `/skill` token anywhere in any lane file resolves to `<name>/SKILL.md` under `.agents/skills/`; the first skill step of every routine lane takes `<ref>`.
- [x] **AC4** `task-registry lanes` prints one row per lane with the effective chain and selects no provider; `lanes <name>` prints the numbered steps and the *Reply* section; an unknown name exits 2 listing known lanes; a chain skill missing from disk exits 2 naming it; a configured override prints the `note:` line; with an unreadable configuration the table prints, `lanes investigate` exits 0 and `lanes fix` exits 2.
- [x] **AC5** Every existing assertion in `tests/test-routine-skills.sh`, `tests/test-routine-selectors.sh`, `tests/test-routine-branch.sh` and `tests/test-task-registry.sh` stays green, and `workflow`'s output is unchanged for its fixtures. Two assertions move rather than stay: `tests/test-routine-selectors.sh`'s "config.py carries the literal `"plan"`" pin becomes a catalogue pin, and `tests/test-sweep-routines.sh`'s "`fix` step 4a reads `/debug #N`" pin reads `/debug <ref>` from the lane file.
- [x] **AC6** `tests/test-routines-contract.sh` pins the routine table in `routines.md` equal to the catalogue (names, selectors, deferred) and reads each routine's step rows from its lane file; `routines.md`'s per-routine sections carry no step rows. `tests/test-lane-catalogue.sh` pins the template's `[routines.skills]` block equal to `catalogue().chains`.
- [x] **AC7** `tests/test-go-lanes.sh` pins: `/go`'s SKILL.md names `task-registry lanes` and `workflow`, carries no lane table and no `lanes/` directory; every interactive lane with a code-changing chain names `/plan` or `/debug` before `/build`; `investigate` never names `/wrap-up-session`; the host sweep and banner pins are unchanged.
- [x] **AC8** `specs/go-front-door.md` records the supersession; `.agents/skills/go/SKILL.md` carries no `TODO(shortcut)`; `tasks/concepts.md` defines *lane*, *lane catalogue*, *contract routine* and *skill chain* in the new terms; the template's `[routines.skills]` comment names the catalogue as its source.
- [x] **AC9** `bash tests/run.sh` green except the known Windows `gh`-mock baseline.

## Testing approach

Python-level assertions on the loader through `python3 -c` probes, in the style
of `tests/test-routine-skills.sh`: fixture lane directories built in a temp dir
for every refusal in AC2, the shipped directory for the positive views. CLI
assertions on `lanes` through the same fixture-project helper the routine tests
use. The prose pins in `test-go-lanes.sh` and `test-routines-contract.sh` are
rewritten to read the lane files where they used to read the table or the
document.
