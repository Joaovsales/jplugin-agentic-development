---
implementation_paths:
  - .agents/skills/visual-plan/**
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/system-design-planning/templates/**
  - .agents/skills/plan/SKILL.md
  - .agents/skills/slice/SKILL.md
  - .agents/skills/slice/scripts/slice.py
  - .agents/skills/slice/references/**
  - tests/test-plan-render.sh
  - tests/test-plan-page.sh
  - tests/test-slice.sh
  - tests/fixtures/plan-render/**
  - design/plan-theme/**
---

# Spec: Readable visual plans

> Issue: [#233](https://github.com/Joaovsales/jplugin-agentic-development/issues/233) ·
> Decisions settled in a `/grilling` session on 2026-10-07 (Q1–Q24).

## Summary

A visual plan is the page a reviewer reads before approving a build. It is rendered
straight from the spec markdown, so it can never disagree with it, and it gives each
kind of content — decisions, acceptance criteria, risks, open questions, contracts,
slices — its own recognisable card, with real diagrams and collapsible detail. The
reviewer can mark items, answer questions and export that review back to `/plan`.

## Behavior

`/visual-plan specs/<feature>.md` and `/system-design-planning` Step 6 both run one
renderer, `.agents/skills/visual-plan/scripts/plan_render.py`, which reads the spec
file and writes `specs/<feature>.plan.html`. No agent-built JSON content model sits
between them; the agent's only authored inputs are sections of the spec itself.

The renderer parses a stdlib-only markdown subset (headings, paragraphs, ordered and
unordered lists, tables, fenced code, inline code, bold, italic, links). Known sections
become typed components; every other `##` section renders as generic markdown with
semantic tables and a collapsible body.

| Spec section | Component | Default |
|---|---|---|
| `## Summary` (else first paragraph of `## Problem`/`## Behavior`) | Lead card, large type | open |
| computed | Summary strip: counts of slices, ACs, decisions, risks, open items; each links to its section | open |
| computed | **Blockers** panel: open decisions, blocking questions, uncovered ACs, high-impact risks without mitigation | open |
| `## Open questions` | Question cards: dashed border, `?` icon, `Blocks` and `Needed from` tags | open |
| `## Decisions` | Decision cards: ID, status chip, title, chosen option with a check badge; other options, rationale and "Wrong when" (reversal callout) inside a disclosure | header open, body collapsed |
| `## Acceptance Criteria` | AC checklist: ID, text, "covered by slice N" from the Build Order `ACs` column, red **uncovered** badge when no slice names it | open |
| `## Risks` | Risk cards sorted by impact then likelihood: triangle icon, H/M/L text labels, mitigation, slice | open |
| `## Constraints` (table) | Constraint cards; a source of `inferred` carries a **verify** badge | collapsed |
| `## Component contracts` / `###` subsections | Contract blocks: monospace, copy button, NEW/changed chip parsed from the heading's parenthetical | collapsed |
| `## Data models` / `###` subsections | Schema blocks with semantic tables | collapsed |
| `## Build Order` | Slice dependency DAG (SVG) + slice cards: goal, surface, blocked-by, ACs, verify, size | DAG open, cards collapsed |
| fenced `flow` / `sequence` blocks, anywhere | Inline SVG diagram with caption and `<title>`/`<desc>`; DSL source in a collapsed "diagram source" disclosure | open |
| fenced `text` blocks that look like ASCII diagrams | Monospace inside a collapsed "text diagram" disclosure | collapsed |
| build prompt (from § Build Order) | Build-prompt panel, linked from the first screen, with **Copy build prompt** | open |
| References / links | Reference list | collapsed |

Every component type is distinguishable by colour, icon, text label and border shape
together — never colour alone. The page has one `h1`, a sticky table of contents with
scrollspy (a top `<details>` menu below 768 px that closes on selection), **Expand all**,
**Collapse all** and **Show only blockers** controls, and opens any collapsed section a
deep link or initial URL fragment targets.

**Readiness.** When the spec has any `open` decision or any open question whose
`Blocks` is not `none`, `/slice` prints `not ready: <ids>` instead of a build prompt and
exits non-zero, and the build-prompt panel reads **Not ready: D4, Q2** with copy
disabled. A superseded prompt is never shown as executable.

**Review state.** Each AC, decision, risk, question and slice card carries review
controls: `ok`, `questioned` (with a note), and for questions an answer field and for
open decisions an option picker. State lives in `localStorage` under a key that includes
the spec's SHA-256 prefix, so a re-rendered spec never shows stale marks. **Export
review** copies a markdown block:

```text
Review of specs/<feature>.md @ <sha256[:12]>
D3: questioned — <note>
D4: pick B — <note>
Q2: answer — <text>
AC5: ok
S4: questioned — <note>
```

`/plan`'s change-request path accepts that block: it refuses a block whose hash does not
match the current spec, applies each line (an answer moves the question into
§ Decisions as a settled row or deletes it; a pick settles the decision; a `questioned`
becomes a spec edit or an `open` decision), then re-runs `/slice`.

**Source.** The page header names its source as `Source: specs/<feature>.md · sha256
<prefix>`, a relative link to the spec beside it in the repository. It carries the same
hash prefix as the review state. The page does not embed or offer a download of the
markdown: it already renders the whole spec, and reviews return through the export
block. Viewing and navigation make no network requests.

**Theme.** One jplugin-owned plan theme, derived from the minimal technical journal
prototype in `design/prototypes/minimalist/`, is inlined into every page. It is authored
once with the shared design stack (Taste for direction, Impeccable for critique) and its
design rules are recorded in `design/plan-theme/DESIGN.md`. Rendering reads neither a
user-scope design-stack install nor a project `DESIGN.md`.

## Inputs

- `specs/<feature>.md` — the only content source.
- Spec fields the renderer understands (all backward compatible):
  - **Decisions**, either shape:
    - `/plan`: `# | Question | Decision | Source | Why` — `#` is the ID, `Source = open` is open.
    - `/system-design-planning`: `ID | Decision | Options | Recommended | Wrong when | Status` — `Status` is `settled` or `open`.
    - A table with no ID column is auto-numbered D1…; with no status it is `settled`.
  - **Acceptance Criteria** bullets prefixed `AC1:`; unprefixed bullets are auto-numbered.
  - `## Risks`: `ID | Risk | Likelihood | Impact | Mitigation | Slice`, H/M/L values; or the single line `None identified — <why>`.
  - `## Open questions`: `ID | Question | Blocks | Needed from`; `Blocks` is slice numbers or `none`.
  - `## Summary`: three sentences at most, optionally one `flow` block.
  - Diagram fences:
    - `flow`: one edge per line `A -> B : label`; `group <Name>: a, b` lanes; `(new)` / `(changed)` node markers.
    - `sequence`: `A -> B : msg` calls, `A --> B : msg` replies, `alt <cond>` / `else` / `end` blocks.
    - Both use Mermaid's arrow and `alt` syntax but accept only this subset.
- Command line: `plan_render.py <spec.md> -o <out.html>`.

## Outputs

- `specs/<feature>.plan.html` — one self-contained file: inline CSS, JS and SVG; legible in light and dark themes and in print.
- Exit 0 on success with `✓ Visual written: <absolute path>`; exit 1 with
  `<spec>:<line>: <reason>` on a parse failure of a known section or diagram.
- `/slice`: a build prompt, or `not ready: <ids>` and a non-zero exit.

## Edge Cases

- A spec written before this change (no IDs, no status, no Summary, no Risks/Open
  questions, ASCII diagrams) renders without error: IDs are auto-numbered, the summary
  falls back to the first paragraph, the absent sections are omitted, ASCII diagrams go
  into collapsed text-diagram disclosures.
- A malformed known section — a Decisions row with a missing cell, a Risks value outside
  H/M/L, an Open questions `Blocks` naming a slice the Build Order lacks, a Build Order
  cycle — fails the render with `file:line` and the reason; nothing is written.
- An unsupported line inside a `flow` or `sequence` fence fails with its line number; the
  renderer never falls back to an empty or partial diagram.
- A spec with no § Build Order renders without the DAG, the slice cards and the
  build-prompt panel, and says the spec has not been sliced.
- An AC that no slice names shows the **uncovered** badge and appears in Blockers.
- Duplicate IDs (two `D3` rows) fail the render.
- A long prose section, a table wider than the viewport, or a 30-node DAG causes no
  page-level horizontal overflow at 390 px; wide tables and diagrams scroll inside their
  own container and keep their column headings.
- `localStorage` that throws or is empty: the page renders and works, and review
  controls report that marks will not persist.
- A review export pasted against a changed spec is refused by `/plan` naming both hashes.
- Untrusted text in the spec is HTML-escaped everywhere, including inside SVG labels and
  the build-prompt copy payload.

## Build Order

Sizing: 13 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 1–7, 9 and 10 count `tests/test-plan-render.sh` and `tests/fixtures/plan-render/**` as two systems beside the renderer; both only verify the one renderer system. Slice 8 moves the `/slice` gate and the page's disabled-copy state together because they are one readiness contract. Slice 9 changes the page's export and its one consumer in `/plan` atomically. Slice 11 rewires three planner skills at once because they share the renderer contract and the spec template.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Renderer core | A stdlib markdown-subset renderer that turns any spec into a self-contained page with generic sections, semantic tables, loud parse failures and old-spec compatibility. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | — | 2, 14, 21 | `bash tests/test-plan-render.sh` | ~6 files · 3 systems · 3 ACs |
| 2 | Plan theme | The jplugin plan theme, authored with Taste and Impeccable from the minimalist prototype, recorded in `design/plan-theme/DESIGN.md` and inlined by the renderer. | `design/plan-theme/**`, `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh` | 1 | 20 | `bash tests/test-plan-render.sh` | ~5 files · 3 systems · 1 AC |
| 3 | Decision and criteria cards | Decision cards in both table shapes, the AC checklist with slice coverage, the lead summary, the summary strip and the Blockers panel. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 2 | 4, 5, 8 | `bash tests/test-plan-render.sh` | ~5 files · 3 systems · 3 ACs |
| 4 | Diagrams | Inline SVG for the Build Order dependency DAG and for `flow` and `sequence` fences, with strict DSL parsing. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 3 | 9, 10 | `bash tests/test-plan-render.sh` | ~5 files · 3 systems · 2 ACs |
| 5 | Risk and question cards | `## Risks` and `## Open questions` cards, their Blockers entries and blocked-slice marks in the DAG. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 4 | 6, 7 | `bash tests/test-plan-render.sh` | ~4 files · 3 systems · 2 ACs |
| 6 | Disclosure and navigation | Open and collapsed defaults, Expand all, Collapse all, Show only blockers, deep links into collapsed sections, scrollspy TOC and mobile menu dismissal. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 5 | 12, 13 | `bash tests/test-plan-render.sh` | ~4 files · 3 systems · 2 ACs |
| 7 | Build prompt panel | A first-screen build-prompt panel with exact copy, and the source line naming the spec and its hash. | `.agents/skills/visual-plan/scripts/**`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 6 | 15, 17 | `bash tests/test-plan-render.sh` | ~4 files · 3 systems · 2 ACs |
| 8 | Readiness gate | `/slice` refuses a build prompt while a decision is open or a question blocks a slice, and the page disables copy with the same ids. | `.agents/skills/slice/SKILL.md`, `.agents/skills/slice/scripts/slice.py`, `.agents/skills/slice/references/**`, `.agents/skills/visual-plan/scripts/**`, `tests/test-slice.sh`, `tests/test-plan-render.sh` | 7 | 16 | `bash tests/test-slice.sh && bash tests/test-plan-render.sh` | ~6 files · 4 systems · 1 AC; one readiness contract |
| 9 | Review export | Hash-keyed review state on every card, the export block, and `/plan`'s change-request path that applies it. | `.agents/skills/visual-plan/scripts/**`, `.agents/skills/plan/SKILL.md`, `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` | 8 | 18, 19 | `bash tests/test-plan-render.sh` | ~5 files · 4 systems · 2 ACs; producer and consumer atomic |
| 10 | Fidelity checks | Fixture checks that every component type is visually distinct and that every AC sentence, decision row, signature, limit and table row survives into the HTML. | `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**`, `.agents/skills/visual-plan/scripts/**` | 9 | 3, 22 | `bash tests/test-plan-render.sh` | ~4 files · 3 systems · 2 ACs |
| 11 | Planner wiring | `/visual-plan` and `/system-design-planning` call the new renderer; the system-design template and `/plan` gain Summary, Risks, Open questions, ID/Status, diagram rules and the editorial guidance; `content-model.json` is removed. | `.agents/skills/visual-plan/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `.agents/skills/system-design-planning/templates/**`, `.agents/skills/plan/SKILL.md`, `tests/test-plan-render.sh` | 10 | 1, 11, 24 | `bash tests/test-plan-render.sh && bash tests/test-doc-conventions.sh` | ~6 files · 4 systems · 3 ACs; shared renderer contract |
| 12 | Browser proof | A Playwright check over every fixture page at 1440 and 390 px in both themes, with screenshots for the owner's review. | `tests/test-plan-page.sh`, `.agents/skills/visual-plan/scripts/**`, `design/plan-theme/**` | 11 | 23 | `REQUIRE_BROWSER=1 bash tests/test-plan-page.sh` | ~4 files · 3 systems · 1 AC |
| 13 | Dogfood comparison | The upgraded snow-mcp OAuth plan re-rendered outside the repo, with before and after screenshots kept for the PR. | `design/plan-theme/**` | 12 | 25 | Owner review of `design/plan-theme/dogfood/` before/after captures | ~3 files · 1 system · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/readable-visual-plans.md`.
Plan: `## Plan: readable-visual-plans` in `tasks/todo.md`, 13 slices, ready set 1.
Files: .agents/skills/visual-plan/**, .agents/skills/system-design-planning/SKILL.md, .agents/skills/system-design-planning/templates/**, .agents/skills/plan/SKILL.md, .agents/skills/slice/SKILL.md, .agents/skills/slice/scripts/slice.py, .agents/skills/slice/references/**, tests/test-plan-render.sh, tests/test-plan-page.sh, tests/test-slice.sh, tests/fixtures/plan-render/**, design/plan-theme/**.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/readable-visual-plans.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: render only from the spec markdown, stdlib Python, no network and no bundled diagram library; malformed known sections fail with file:line; never colour alone; the plan theme is jplugin-owned and reads no design-stack install or project DESIGN.md; `visual-render.py` and `html-presentation` stay unchanged for `/visual-recap`; the page links its source spec and embeds no markdown copy; fixtures are generic, no downstream-project content in the repo; visual approval is the owner's screenshot review recorded in the PR, never a self-declared pass.
```

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| D1 | Scope relative to #233 | Extend #233 with the new criteria; one spec, sliced | user | Both halves rewrite the same renderer; splitting builds the disclosure layer twice |
| D2 | Content source for the page | Deterministic spec→HTML renderer; no agent-built JSON model | user | One source of truth; the "render dropped a row" defect class disappears and source-to-render checks become mechanical |
| D3 | Role of the design harness | One jplugin-owned plan theme authored with Taste/Impeccable; no runtime dependency | user | Reviewers learn the shapes once across projects; backend projects have no `DESIGN.md` |
| D4 | Diagram production | Deterministic Python → inline SVG for DAG, `flow`, `sequence` | user | Themeable, accessible, clickable, no binary or 600 KB bundle; DSL source stays diffable |
| D5 | Entry points | `/visual-plan` and `/system-design-planning`; `/visual-recap` stays on the old generator for now | user | `/plan` gains no extra step; recap moves in a later change |
| D6 | Default disclosure | Approval content open; reference content collapsed | user | NN/g and GOV.UK guidance: what the reviewer must approve stays visible |
| D7 | Interactivity | Read-only controls plus local review state and export | user | Turns the page into the place blockers are cleared |
| D8 | Decisions shape | Add `ID` and `Status` columns; rows render as cards | user | Smallest format change; "Wrong when" is the reviewer's objection trigger |
| D9 | AC shape | Keep prose, add `AC1:` prefix, coverage from Build Order | user | The uncovered badge is a free review check |
| D10 | Theme base | Minimal technical journal prototype | user | Calm long-reading base lets typed components carry the distinctions |
| D11 | Non-conforming specs | Unknown sections generic; malformed known sections fail with `file:line` | user | No silent failures on the content a reviewer must not miss |
| D12 | Markdown parsing | Stdlib-only subset parser | user | Repo scripts are stdlib Python; a pip dependency breaks the plugin downstream |
| D13 | Review export | Hash-bound markdown block consumed by `/plan`'s change-request path | user | An export with no consumer is prose the agent re-interprets |
| D14 | Required diagrams | DAG always; `/system-design-planning` needs ≥1 `flow` plus `sequence` per changed external contract or cross-component failure path | user | Without a requirement the "not enough diagrams" problem returns |
| D15 | Diagram DSL syntax | Mermaid-flavoured subset in `flow`/`sequence` fences, strict parser | user | Models write Mermaid arrows fluently; a distinct fence name sets no full-Mermaid expectation |
| D16 | New spec sections | Add `## Risks` and `## Open questions` | user | Risks and unframed unknowns get lost in prose today |
| D17 | Lead summary | Optional `## Summary`, fallback to the first paragraph | user | A sentence written for the reader beats a problem statement |
| D18 | Code placement | New `visual-plan/scripts/plan_render.py`; `visual-render.py` and `html-presentation` untouched; `content-model.json` and the text-block diagram rule leave `/system-design-planning` | user | `/visual-recap` and `/html-presentation` keep working |
| D19 | Visual proof | Generic fixtures, a Playwright page check at 1440/390 px in both themes, and an owner review of committed screenshots recorded in the PR | user | The complaint is visual quality; #247 rules out self-declared passes |
| D20 | Migration | No bulk re-render; re-render on the next spec change; snow-mcp OAuth plan upgraded and re-rendered as the final before/after check | user | Bulk re-renders churn history and need spec migrations |
| D21 | Risks shape | `ID / Risk / Likelihood / Impact / Mitigation / Slice`; required in `/system-design-planning`, optional in `/plan`; empty means `None identified — <why>` | user | A fixed shape makes it a card; the why-line stops filler |
| D22 | Open questions vs open decisions | Separate `ID / Question / Blocks / Needed from` table holding live questions only | user | A question has no framed options yet |
| D23 | Readiness gate | `/slice` refuses a build prompt while a decision is open or a question blocks a slice; the page disables copy | user | A build started with D4 open just guesses D4 |
| D24 | Resolving in the export | Export carries answers and picks, applied by `/plan` | user | Makes the visual plan the place blockers are cleared |
| D25 | The two existing Decisions shapes | The renderer reads both the `/plan` and the `/system-design-planning` shapes; only the latter gains `ID`/`Status` columns | assumed | `/plan`'s table already carries `#` and `Source = open`; changing it would rewrite every spec for nothing |
| D26 | `/slice`'s `[AMBIGUITY]` rule for open rows | Replaced by the D23 gate: an open row now stops the build prompt instead of becoming an `[AMBIGUITY]` line | assumed | D23 makes the old rule unreachable; keeping both texts would contradict |
| D27 | Where the Playwright page check runs | A Python check script driven by `tests/test-plan-page.sh`; when Playwright is not installed the test prints `SKIP: playwright not installed` and exits non-zero only under `REQUIRE_BROWSER=1`, which CI sets | assumed | Matches `design/qa.py`'s use of `playwright.sync_api`; a local machine without Chromium still runs the rest of the suite, and the skip is loud |
| D28 | Spec download in the page | No embedded markdown or download; a source line names the spec, with a relative link and its SHA-256 prefix | user | The spec and the plan are committed side by side; the page already renders the whole spec and reviews return through the export block, so an embedded copy only served a page shared without its repository |

## Acceptance Criteria

- AC1: `plan_render.py <spec> -o <html>` renders from the spec markdown alone, with a stdlib-only markdown subset parser; `/visual-plan` and `/system-design-planning` call it, and `/system-design-planning` no longer builds `content-model.json` or requires diagrams and tables in `text` fences.
- AC2: Unknown `##` sections render as generic markdown; a malformed Decisions, Acceptance Criteria, Build Order, Risks or Open questions section, a duplicate ID, or an unsupported diagram line exits 1 with `<spec>:<line>: <reason>` and writes no file.
- AC3: Each component in the § Behavior table renders with a distinct colour, icon, text label and border style; a fixture check confirms every component type is present and that no two types share the same icon and label.
- AC4: Decisions in both shapes render as cards with ID, status chip and chosen option visible and rationale, other options and "Wrong when" inside a disclosure; specs without ID or status columns auto-number and default to `settled`.
- AC5: Each AC renders with its ID and the slices that name it in the Build Order `ACs` column; an AC no slice names carries an **uncovered** badge and appears in Blockers.
- AC6: `## Risks` renders as cards sorted by impact then likelihood with text H/M/L labels; a high-impact risk with an empty mitigation appears in Blockers; `None identified — <why>` renders as a single line.
- AC7: `## Open questions` renders as question cards; a question whose `Blocks` names slices marks those slices as blocked in the DAG and appears in Blockers.
- AC8: The Blockers panel lists exactly the open decisions, blocking questions, uncovered ACs and unmitigated high-impact risks, each linking to its card; the summary strip shows counts that link to their sections.
- AC9: The slice DAG is an inline SVG derived from Build Order `Blocked by`, laid out in dependency layers; each node links to its slice card and has an accessible name.
- AC10: `flow` and `sequence` fences render as themeable inline SVG with a caption, `<title>` and `<desc>`, `(new)`/`(changed)` node styling and `alt`/`else` frames; the DSL source sits in a collapsed disclosure; the page loads no diagram library.
- AC11: `/system-design-planning` requires at least one `flow` diagram under § System design and a `sequence` diagram for each changed external contract or cross-component failure path, and requires a `## Risks` section; its spec template shows `ID` and `Status` Decisions columns, `## Summary`, `## Risks` and `## Open questions`.
- AC12: Approval content (summary, summary strip, Blockers, open questions, decision headers, ACs, risks, diagrams, build prompt) is open on load; constraints, contracts, data models, decision bodies, slice cards, text diagrams and references are collapsed; Expand all, Collapse all and Show only blockers work by mouse and keyboard.
- AC13: A section link or initial URL fragment opens every collapsed ancestor of its target and scrolls to it; below 768 px choosing a navigation item closes the menu.
- AC14: Markdown tables render as semantic `<table>` elements with header cells; wide tables scroll inside their own container; no fixture produces page-level horizontal overflow at 390 px.
- AC15: The build-prompt panel is linked from the first screen and the table of contents; **Copy build prompt** copies bytes equal to the canonical prompt in § Build Order.
- AC16: With an open decision or a blocking question, `/slice` prints `not ready: <ids>` and exits non-zero instead of printing a build prompt, and the page shows **Not ready: <ids>** with copy disabled; non-blocking questions do not gate.
- AC17: The page header names its source spec with a relative link and the spec's SHA-256 prefix, embeds no copy of the markdown, and makes no network requests while viewing or navigating.
- AC18: Review controls on AC, decision, risk, question and slice cards persist in `localStorage` keyed by the spec's SHA-256 prefix; **Export review** copies the block format in § Behavior; a failing `localStorage` leaves the page working and says marks will not persist.
- AC19: `/plan`'s change-request path applies an exported review block — answers, picks and questioned items — to the spec and re-runs `/slice`, and refuses a block whose hash does not match the current spec, naming both hashes.
- AC20: Every page uses the jplugin plan theme inlined from `design/plan-theme/`, whose `DESIGN.md` records palette, typography, layout, motion, accessibility and the component vocabulary; rendering reads no design-stack install and no project `DESIGN.md`.
- AC21: A spec written before this change renders without error, with auto-numbered IDs, the summary fallback, and ASCII diagrams in collapsed text-diagram disclosures.
- AC22: Source-to-render checks over the generic fixtures confirm every AC sentence, decision row, contract signature, numeric limit and table row in the spec appears in the HTML.
- AC23: A Playwright check drives every fixture page at 1440 and 390 px in light and dark themes — disclosures, keyboard controls, deep links, mobile menu dismissal, prompt copy, source link, review export, console errors, page overflow — and writes screenshots; the PR records the owner's review of those screenshots.
- AC24: Planning guidance in `/plan` and `/system-design-planning` tells the author to remove repetition, empty qualifiers and workflow narration from specs and to write connected sentences, not slash-packed shorthand.
- AC25: The snow-mcp `oauth-identity-source` spec, upgraded with IDs, status, a Summary, Risks, a `flow` and a `sequence` diagram, renders without error, and its before and after pages are compared in the PR (the spec stays outside this repository).

## Implementation Paths

- `.agents/skills/visual-plan/**` — the skill doc, `scripts/plan_render.py` (markdown subset, typed sections, review-state script), the SVG diagram generator, the page template and the inlined theme assets.
- `.agents/skills/system-design-planning/SKILL.md` and `templates/**` — Step 6 calls the new renderer; the template gains ID/Status, Summary, Risks, Open questions and diagram requirements; `content-model.json` is removed.
- `.agents/skills/plan/SKILL.md` — the spec template's optional Summary, Risks, Open questions and `AC1:` prefix; the editorial guidance; the review-export change-request path.
- `.agents/skills/slice/SKILL.md`, `scripts/slice.py`, `references/**` — the readiness gate replacing the open-row `[AMBIGUITY]` rule.
- `design/plan-theme/**` — the plan theme's `DESIGN.md`, CSS source and the authoring record (Taste direction, Impeccable findings).
- `tests/test-plan-render.sh`, `tests/fixtures/plan-render/**` — parser, component, diagram, failure-mode and source-to-render checks over generic fixtures.
- `tests/test-plan-page.sh` — the Playwright page check and screenshot capture.
- `tests/test-slice.sh` — the readiness gate.
