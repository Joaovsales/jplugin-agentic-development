---
implementation_paths:
  - .agents/skills/perf/**
  - .agents/skills/task-registry/lanes/perf.md
  - .agents/skills/go/SKILL.md
  - .agents/skills/quality-gate/SKILL.md
  - specs/lane-catalogue.md
  - specs/go-front-door.md
  - README.md
  - tests/test-perf.sh
  - tests/test-go-lanes.sh
  - tests/test-lane-catalogue.sh
  - tests/fixtures/perf/**
---

# Spec: perf lane — Audit mode and Debug mode

## Summary

The `perf` lane gets two modes, both run by one new skill, `/perf`. **Audit**
is proactive: it inventories an app's critical paths, measures each with noise
control, estimates how fast each should be, reviews the hot paths for wasted
work, and writes a ranked report that files one task per finding. **Debug** is
the existing reactive loop, now carrying an expected number beside the baseline
and the after, and refusing to call a change inside the noise an improvement.
The decision not to miss: a number is only a measurement when it is N runs of
one repeatable command, summarised as min, median and spread — every script
refuses anything less.

## Behavior

### Mode selection

`/go` routes a goal to the `perf` lane on either kind of cue. The lane's step 1
picks the mode from the goal's words:

- **Audit** — the goal asks to audit performance, asks how fast an app or flow
  is, or names a whole app or flow with no symptom ("audit the performance of
  the shop", "how fast is this app").
- **Debug** — the goal reports one slow path ("checkout is slow", "the export
  takes 40 seconds", latency, memory, a profile attached).

A goal asking how fast something is goes to `perf` (Audit), not `investigate`:
its answer is a measurement, not a cited read of the code.

### Audit mode (`/perf audit <target>`)

1. **Inventory** the critical paths: startup, the main user flows, the top
   routes or endpoints, heavy jobs. A project verification skill (`verify-<app>`)
   or a route table is the source when one exists; the inventory names where it
   came from.
2. **Measure** each path with `measure.py run` (N ≥ 5 runs of one command, min,
   median, max, spread) or, for numbers another tool produced (per-endpoint
   latency, repeated lab traces), `measure.py summarize`. Web paths also get a
   lab trace — LCP, INP, CLS, long tasks — and the bundle size, recorded as lab
   data. Backends get per-endpoint latency and the query count.
3. **Estimate** how fast each path should be — a back-of-the-envelope number
   from the work the path really needs and what the hardware or network can
   do — and record the basis in one sentence. The gap is measured median ÷
   expected; the likely source is one of waste, cache misses, serial work that
   could run in parallel, waterfalls, N+1 queries, oversized payloads.
4. **Review** the hot paths for wasted work: `scan.py` lists mechanical
   candidates (N+1 calls, awaits inside loops, independent awaits run one after
   another) with `file:line`; the agent reads each and checks the rest of the
   non-pessimization checklist (needless copies and allocations, repeated
   parsing or serialization, layers that do nothing, re-renders). A candidate
   read and confirmed is a finding at confidence 75 or above; one that is not
   goes to *Unverified*.
5. **Report** — write `tasks/perf/<YYYY-MM-DD>-<slug>.json` in the audit
   schema; `audit.py validate` refuses a malformed one, `audit.py render`
   writes the Markdown report beside it, ranked by impact × confidence ÷ effort.
6. **File** — `audit.py file` runs one `task-registry upsert` per finding
   (dry-run by default, `--apply` to write), each carrying its measurement, the
   expected number, `file:line`, the suggested fix and the measure command as
   its reproduction. A filed finding is later handed to Debug mode with
   `/go "<finding> #N is slow"`.

Audit mode changes no product code. The lane ends at the report and the filed
tasks; its Debug-only steps are kept with ` — skip: audit mode`.

### Debug mode (`/perf debug <ref>`)

1. Name the slow path and one repeatable command that exercises it.
2. Baseline: `measure.py run --runs N -- <command>` saved to
   `tasks/perf/<slug>-baseline.json`, before any edit.
3. Expected: the same back-of-the-envelope estimate as Audit step 3.
4. Hand the baseline (the reproduction) and the expected number to `/debug`,
   then `/build` the fix.
5. After: the same command with the same N, saved as `<slug>-after.json`;
   `measure.py compare` prints the verdict and the Markdown table the PR body
   quotes — baseline, expected and after, one command.

A change is `improved` only when the after median is below the baseline's
minimum, `regressed` when it is above the baseline's maximum, and
`within-noise` otherwise. `within-noise` is never reported as an improvement.

### Quality gate

`/quality-gate` Phase 3 (Security and Load) runs `scan.py` over the gate's own
file list. Each candidate is a scale finding at confidence 50 until the
reviewer reads the loop and the assumed load reaches it (75) — the same
verification-promotion rule every phase uses.

## Inputs

- `measure.py run --runs N [--warmup W] [--timeout S] -- <command ...>` — the
  command runs without a shell; a shell pipeline is passed as
  `bash -c '<pipeline>'`.
- `measure.py summarize --unit <unit> --command '<what produced them>' <sample ...>`
- `measure.py compare <baseline.json> <after.json> [--expected X] [--format json|markdown]`
- `scan.py [--format json|findings] <path ...>` — files or directories;
  `.py` is parsed with `ast`, `.js .jsx .ts .tsx .mjs .cjs` by a brace-tracking
  line scanner; other files are ignored, and `node_modules`, `.git`, `dist`,
  `build`, `.venv` and `venv` are skipped.
- `audit.py validate|render|file <audit.json> [--repo <root>] [--apply]`

## Outputs

- `measure.py run|summarize` — one JSON object: `command`, `unit`, `runs`,
  `warmup`, `samples`, `min`, `median`, `max`, `spread` (max − min) and
  `spread_pct` (spread ÷ median × 100).
- `measure.py compare` — `verdict` (`improved` | `within-noise` |
  `regressed`), both summaries, `expected`, and in Markdown a table with
  baseline, expected and after columns and the verdict.
- `scan.py` — `{"candidates": [{"file", "line", "pattern", "evidence",
  "why"}], "skipped": [{"file", "reason"}]}`, sorted by file then line; the
  `findings` format prints each candidate as a four-axis line at confidence 50.
- `audit.py render` — the Markdown report: *Critical paths* (runs, min, median,
  spread, expected, gap, likely source), *Web vitals (lab data)*, *Findings*
  ranked, *Unverified*, *Coverage gaps*.
- `audit.py file` — one upsert per finding, id derived under the `perf`
  namespace from the finding's file and title, kind `task`, labels
  `performance` plus `now` (impact 3) or `next`.

### Audit schema (`perf-audit/1`)

The runtime copy, with every rule `audit.py validate` enforces, is
`.agents/skills/perf/references/audit-schema.md`.

```json
{
  "schema": "perf-audit/1",
  "target": "<app or flow>", "date": "YYYY-MM-DD", "sha": "<short sha>",
  "inventory_source": "<verify skill | route table | README | none found>",
  "paths": [{
    "id": "<slug>", "name": "<human name>",
    "kind": "startup | flow | endpoint | job | web",
    "measurement": { "...": "measure.py output" },
    "expected": {"value": 5.0, "unit": "ms", "basis": "<one sentence>"},
    "source": "<likely source of the gap>",
    "lab": {"data": "lab", "backend": "<backend and version>",
            "lcp_ms": 0, "inp_ms": 0, "cls": 0.0, "long_tasks": 0, "bundle_bytes": 0}
  }],
  "findings": [{
    "title": "...", "path": "<path id>", "file": "<repo path>", "line": 1,
    "pattern": "<n-plus-one | sequential-await | await-waterfall | other>",
    "evidence": "<verbatim line>", "fix": "<suggested fix>",
    "impact": 1, "confidence": 75, "effort": 1
  }],
  "unverified": [{"file": "...", "line": 1, "reason": "..."}],
  "coverage_gaps": ["<path not measured, and what would reach it>"]
}
```

## Edge Cases

- `--runs` below 5, a summary with fewer than 5 samples, or a measurement whose
  `samples` length differs from `runs` → refused, exit 2: a single-run number
  is not a measurement.
- A summary whose `min`, `median` or `max` does not match its own samples →
  refused by `audit.py validate`: hand-typed numbers are not accepted.
- The measured command exits non-zero on any run → `measure.py run` exits 1
  naming the run: a failing run's time is not a measurement.
- `compare` on two files with different commands, units or run counts →
  exit 2: baseline and after must come from the same command and N.
- A `web` path without a `lab` block, or a `lab` block whose `data` is not
  `"lab"` → refused: a single lab trace is never presented as field data.
- A finding below confidence 75, without `file`/`line`/`fix`, or pointing at a
  path id that does not exist → refused; with `--repo`, a `file:line` that does
  not exist in the tree is refused.
- A Python file that does not parse → listed under `skipped` with the error,
  never silently dropped.
- `.map(async …)` callbacks run concurrently: an `await` inside one is not a
  `sequential-await` candidate, though a query inside it is still `n-plus-one`.
- `audit.py file` run twice over the same report → the same derived ids are
  updated, never duplicated.
- No finding verified → the report says `Findings: none` and nothing is filed.

## Interfaces

### `measure.py`

- **Path:** `.agents/skills/perf/scripts/measure.py`
- **Hides:** timing, warmup, the summary statistics, the minimum-run rule and
  the noise-band verdict.
- **Interface:** `measure.py run|summarize|compare …` → JSON (or Markdown for
  `compare`).
- **Alternative considered:** `hyperfine`. It is the right tool where
  installed, but it is not on every machine the harness runs on and its JSON
  shape would leak into the report schema; the skill names it as an
  alternative feed for `summarize`.
- **Depth:** one call turns a command into a comparable, noise-labelled number.

### `scan.py`

- **Path:** `.agents/skills/perf/scripts/scan.py`
- **Hides:** language detection, AST walking and brace tracking, the call-name
  lists.
- **Interface:** `scan.py [--format json|findings] <path ...>`
- **Alternative considered:** a prose-only checklist. It cannot be pinned by a
  test and drifts between reviewers; the scanner proposes, the reviewer
  confirms.
- **Depth:** the reviewer starts from exact `file:line` candidates instead of
  reading every loop.

### `audit.py`

- **Path:** `.agents/skills/perf/scripts/audit.py`
- **Hides:** the schema rules, the ranking formula, the report layout and the
  upsert argument list.
- **Interface:** `audit.py validate|render|file <audit.json> [--repo R] [--apply]`
- **Alternative considered:** the skill telling the agent to type one upsert per
  finding, as `/sweep` does. A script makes "one task per finding" a property
  the test suite can check.
- **Depth:** one JSON file becomes a validated report and its tasks.

## Build Order

Sizing: 7 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 2 and 3: the fixture tree and the test file are two `tests` systems beside the script, 3 systems, because the fixture is the test's input and splitting them leaves a red suite between slices; slice 5: 6 files, 4 systems, because the lane, `/go`'s precedence, the two specs that restate the lane row and the two tests that pin them change one routing fact together.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Noise control | `measure.py run`, `summarize` and `compare` with the five-run floor and the noise-band verdict | `.agents/skills/perf/scripts/measure.py`, `tests/test-perf.sh` | — | 2, 3 | `bash tests/test-perf.sh` | 2 files · 2 systems · 2 ACs |
| 2 | Waste scanner | `scan.py` finds the planted N+1, await-in-loop and await waterfall in the Python and JavaScript fixture | `.agents/skills/perf/scripts/scan.py`, `tests/fixtures/perf/shop/**`, `tests/test-perf.sh` | 1 | 4 | `bash tests/test-perf.sh` | 5 files · 3 systems · 1 AC |
| 3 | Audit report | `audit.py validate`, `render` and `file` over the `perf-audit/1` schema | `.agents/skills/perf/scripts/audit.py`, `tests/fixtures/perf/audit/**`, `tests/test-perf.sh` | 2 | 5, 6, 7 | `bash tests/test-perf.sh` | 3 files · 3 systems · 3 ACs |
| 4 | Skill body | `/perf` SKILL.md with both modes and its three references; README row | `.agents/skills/perf/SKILL.md`, `.agents/skills/perf/references/**`, `README.md`, `tests/test-perf.sh` | 3 | 9 | `bash tests/test-perf.sh && bash tests/test-skills-table.sh && bash tests/test-skill-frontmatter.sh && bash tests/test-citations.sh` | 6 files · 2 systems · 1 AC |
| 5 | Two-mode lane and routing | `lanes/perf.md` with step 1 picking the mode, `/go`'s audit-versus-investigate precedence, the spec rows and their pins | `.agents/skills/task-registry/lanes/perf.md`, `.agents/skills/go/SKILL.md`, `specs/lane-catalogue.md`, `specs/go-front-door.md`, `tests/test-go-lanes.sh`, `tests/test-lane-catalogue.sh` | 4 | 1 | `bash tests/test-lane-catalogue.sh && bash tests/test-go-lanes.sh` | 6 files · 4 systems · 1 AC |
| 6 | Quality-gate scan | `/quality-gate` Phase 3 runs `scan.py` on the gate's file list | `.agents/skills/quality-gate/SKILL.md`, `tests/test-perf.sh` | 4 | 8 | `bash tests/test-perf.sh` | 2 files · 2 systems · 1 AC |
| 7 | Fixture audit end to end | A web page beside the shop fixture and a full Audit-mode walkthrough logged in `tasks/e2e-log.md` | `tests/fixtures/perf/web/**` | 3 | 10 | `bash tests/test-perf.sh` | 1 file · 1 system · 1 AC |

AC numbering follows § Acceptance Criteria in order. Slices 5, 6 and 7 are disjoint and run in parallel once their blockers are done. `/wrap-up-session` runs the full suite once.

Build prompt:

```
Invoke `/build` for `specs/perf-audit-and-debug.md`.
Plan: `## Plan: perf lane — Audit mode and Debug mode` in `tasks/todo.md`, 7 slices, ready set <1>.
Files: .agents/skills/perf/**, .agents/skills/task-registry/lanes/perf.md, .agents/skills/go/SKILL.md, .agents/skills/quality-gate/SKILL.md, specs/lane-catalogue.md, specs/go-front-door.md, README.md, tests/test-perf.sh, tests/test-go-lanes.sh, tests/test-lane-catalogue.sh, tests/fixtures/perf/**.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Every measurement is N >= 5 runs of one command summarised as min, median, spread; a single-run number is refused (D4).
Constraints: `improved` only when the after median is below the baseline minimum (D5).
Constraints: The perf check lives in /quality-gate Phase 3, not a new /sweep routine (D3).
```

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | One lane or two? | One lane, `perf`, whose step 1 picks the mode. | user | The issue asks for one lane with two modes. |
| 2 | Where does the audit procedure live? | A new skill, `/perf`, with `audit` and `debug` modes; the lane names it as its first skill step. | assumed | Lanes name skills and skills own procedures (`plan`, `tidy`, `build` lanes all name their skill). |
| 3 | Perf lens in `/sweep` or a quality-gate check? | A check inside `/quality-gate` Phase 3 (Security and Load), on the gate's changed files. | assumed | The issue scopes it to "changed hot paths", Phase 3 already owns "one query or call per item" under § Expected load, and a `/sweep` lens is a new producer routine (lane, routine prompt, contract tests) the issue does not need. |
| 4 | Minimum runs | 5; default 10. | assumed | Enough for a median and a spread on paths up to a minute; fewer is refused. |
| 5 | Noise rule | `improved` only when the after median is below the baseline minimum. | assumed | "Not measurably better than the baseline's spread is not a win" stated as one comparison anyone can check by eye. |
| 6 | Ranking | score = impact × confidence ÷ 100 ÷ effort, impact and effort on 1–3; ties broken by the path's gap, then `file:line`. | assumed | The issue's impact × confidence × effort, with effort dividing because more effort ranks lower. |
| 7 | Filing kind and labels | `--kind task --label performance` plus `now` (impact 3) or `next`. | assumed | No kind label routes the task to `fix`; `/go` then matches the goal text and reaches `perf` Debug mode. |
| 8 | Filing bar | Confidence 75 or above, as `/sweep` files; lower goes to *Unverified*. | assumed | One filing bar across producers. |
| 9 | Web measurement backend | `verify-evidence`'s backend order: Playwright CLI, then Chrome MCP; a Chrome DevTools performance trace is the alternative feed. Every number is labelled lab data. | user | The issue asks to match `verify-evidence` and to label lab traces. |
| 10 | Where do audits live? | `tasks/perf/` in the audited project, JSON and Markdown side by side. | assumed | Beside the other run artifacts (`tasks/sweeps/`); the human decides whether to commit them. |
| 11 | Does Audit mode open a PR? | No; it ends at the report and the filed tasks. | assumed | An audit changes no code; each finding reaches a PR through Debug mode. |

## Acceptance Criteria

- AC1: `task-registry lanes perf` prints step 1 naming both modes with their cues, a `/perf` first skill step, `/debug` before `/build`, and the chain `/perf -> /debug -> /build -> /quality-gate -> /wrap-up-session`; the lane's `cues:` carry both audit and slowness phrases; `/go` states that a how-fast or audit goal is `perf`, not `investigate`.
- AC2: `measure.py run --runs N` reports `runs`, `samples`, `min`, `median`, `max`, `spread`, `spread_pct`; `--runs` below 5 and `summarize` with fewer than 5 samples exit 2; a run whose command exits non-zero exits 1 naming the run.
- AC3: `measure.py compare` reports `improved` only when the after median is below the baseline minimum, `within-noise` for an overlapping change, `regressed` above the baseline maximum; refuses different commands, units or run counts; its Markdown carries baseline, expected and after columns.
- AC4: `scan.py` over `tests/fixtures/perf/shop/` reports the planted N+1 query, the await inside a loop and the independent-await waterfall, each at its exact `file:line`, in both the Python and the JavaScript fixture, and reports nothing for the fixture's clean functions (including `.map(async …)` and dependent awaits).
- AC5: `audit.py validate` accepts the fixture audit and refuses a single-run measurement, summary numbers that do not match their samples, a missing expected number, a web path without a lab block or with `data` other than `lab`, a finding below confidence 75 or without `file:line`, and (with `--repo`) a `file:line` absent from the tree.
- AC6: `audit.py render` writes measured, expected and gap for every critical path, a *Web vitals* section with LCP, INP and CLS labelled lab data, and findings ranked by the decision-6 score with `file:line`.
- AC7: `audit.py file --apply` against a local-provider repository files exactly one task per finding with the `performance` label and the measure command as reproduction; a second run files no new task.
- AC8: `/quality-gate` Phase 3 runs `scan.py` on the gate's file list and treats each candidate as a confidence-50 scale finding.
- AC9: `/perf` exists with frontmatter, both modes, the noise rule, the estimate method and the web backend order, and appears in the README skills table.
- AC10: an end-to-end audit of the fixture app — backend and web — produces a validated report with measured, expected and gap per path, lab LCP/INP/CLS, ranked findings with `file:line`, and one dry-run upsert per finding; the walkthrough is logged in `tasks/e2e-log.md`.

## Implementation Paths

- `.agents/skills/perf/**` — the skill, its references (estimate, non-pessimization, web lab) and the three scripts.
- `.agents/skills/task-registry/lanes/perf.md` — the lane with its two modes.
- `.agents/skills/go/SKILL.md` — the audit-versus-investigate precedence.
- `.agents/skills/quality-gate/SKILL.md` — the Phase 3 scan.
- `specs/lane-catalogue.md`, `specs/go-front-door.md` — the perf rows, kept current.
- `README.md` — the generated skills table row.
- `tests/test-perf.sh` — the scripts, the schema and the skill text.
- `tests/test-go-lanes.sh`, `tests/test-lane-catalogue.sh` — routing pins.
- `tests/fixtures/perf/**` — the fixture app with planted waste and the fixture audit.
