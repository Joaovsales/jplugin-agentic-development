# Plan theme

The one visual language every visual plan uses, in every project. It is owned by
jplugin, inlined from [`plan.css`](plan.css) by
`.agents/skills/visual-plan/scripts/plan_render.py`, and never reads a project's own
`DESIGN.md` or a user-scope design-stack install: a reviewer learns the shapes once and
reads every project's plans with them (specs/readable-visual-plans.md, D3).

The base is the minimal technical journal prototype in
[`design/prototypes/minimalist/`](../prototypes/minimalist/index.html): warm paper, near-black
ink, hairline rules, an editorial display face for headings and a plain sans for reading.
A calm base lets the typed components carry the distinctions (D10).

## Palette

Tokens live on `:root` and are redefined for dark mode under
`@media (prefers-color-scheme: dark)` (guarded by `:root:not([data-theme="light"])`) and
again under `:root[data-theme="dark"]`.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--paper` | `#f7f7f4` | `#161714` | page background |
| `--surface` | `#ffffff` | `#1f211d` | cards, diagrams |
| `--ink` | `#26251e` | `#f2f0e8` | headings, primary text |
| `--body` | `#4f4e48` | `#d5d1c6` | reading text |
| `--muted` | `#6b675f` | `#a49f92` | metadata, labels (≥ 4.5:1 on paper in both themes) |
| `--line` / `--strong` | `#dcdad2` / `#b9b7ac` | `#41443d` / `#64685f` | hairlines, control borders |
| `--accent` | `#b93f18` | `#ff9569` | focus ring, active navigation, build prompt |

Each component type owns one hue (`--c-<type>`) for its icon, label and border, and a
light tint (`--t-<type>`) for states that need a wash (open decision, blocked slice,
uncovered criterion, blockers panel). Hue values are chosen for ≥ 4.5:1 against
`--paper` and `--surface` in their theme, because the hue also colours text labels.

## Typography

- Display: Georgia → Times New Roman (`--display`) for the page title, section headings,
  the lead summary and the summary-strip numbers.
- Reading: the system UI sans (`--sans`) at 16 px / 1.62, measure capped at 68ch.
- Data: the system monospace (`--mono`) for IDs, chips, labels, table headings, code,
  contracts and diagram labels.
- No webfonts are bundled or fetched: the page must render offline and stay small.
- Labels are 11–12 px uppercase monospace with 0.04–0.06em tracking; nothing reading-length
  is uppercase.

## Layout

- One `h1` in the masthead with the folio (spec path and status) and the source line.
- Desktop: a 220 px sticky table of contents beside a fluid main column, inside a
  1440 px shell with `clamp(16px, 4vw, 64px)` gutters.
- Below 768 px the table of contents becomes a top `<details>` menu, sticky, that closes
  when an item is chosen.
- Main column order: lead summary, summary strip, Blockers, controls, then the spec's
  sections in source order, then the build-prompt panel inside § Build Order.
- Wide tables and diagrams scroll inside their own container (`.table-scroll`,
  `.diagram-scroll`) and keep sticky column headings; the page itself never scrolls
  horizontally at 390 px.

## Motion

Smooth scrolling for in-page links only, disabled under `prefers-reduced-motion: reduce`
along with every transition. Nothing animates on load. Disclosure is native `<details>`,
so opening and closing is instant and needs no script.

## Accessibility

- Never colour alone: every component type differs in colour, icon, text label and border
  shape together (see the vocabulary below); every status is a text chip.
- Icons are decorative glyphs with `aria-hidden="true"`; the text label beside them names
  the type.
- Focus is a 2 px accent outline with offset on every interactive element, including SVG
  diagram nodes and the scroll containers (`tabindex="0"`, `role="region"`, a label).
- Controls are `<button>` elements with visible names; toggles expose `aria-pressed`.
- Diagrams carry `<title>` and `<desc>`, a caption, and their DSL source in a disclosure.
- Print opens every disclosure, hides navigation and controls, and prints link targets.

## Component vocabulary

| Component | Hue | Icon | Label | Border shape |
|---|---|---|---|---|
| Lead summary | ink | ¶ | Summary | none — large display type |
| Summary strip | muted | # | At a glance | ink top rule, hairline bottom |
| Blockers panel | `--c-blocker` | ! | Blockers | 6 px solid left edge |
| Open question | `--c-question` | ? (ringed) | Question | 2 px dashed |
| Decision | `--c-decision` | ◆ | Decision | 1 px solid |
| Acceptance criterion | `--c-criterion` | ✓ | Criterion | 3 px left rule, no box |
| Risk | `--c-risk` | ▲ | Risk | 3 px double |
| Constraint | `--c-constraint` | ⊟ | Constraint | 1 px dotted |
| Component contract | `--c-contract` | { } | Contract | 6 px solid left edge on a hairline box |
| Data model | `--c-model` | ⊞ | Data model | 4 px solid top edge |
| Slice | `--c-slice` | ▤ | Slice | 2 px solid, rounded trailing corners |
| Diagram | `--c-diagram` | ◇ | Diagram | 1 px hairline figure |
| Text diagram | muted | ≡ | Text diagram | 1 px dashed |
| Build prompt | `--c-prompt` | ▶ | Build prompt | 2 px solid accent |
| Reference | `--c-reference` | ↗ | Reference | dotted top rule only |

States add to the shape rather than replace it: `open`, `uncovered` and `blocked` switch
the border to dashed and add the blocker tint and a text chip; `new` and `changed`
diagram nodes use a heavier stroke, dashed for `changed`.

## Authoring record

- **Direction (Taste).** Reused from the minimalist study's recorded read
  ([METHOD.md](../prototypes/minimalist/METHOD.md)): an architecture review for technical
  maintainers, dials `DESIGN_VARIANCE: 5`, `MOTION_INTENSITY: 2`, `VISUAL_DENSITY: 4` —
  generous reading space with density raised for contracts and tables. The theme keeps
  the study's asymmetric editorial title, warm paper and hairline rhythm, and drops its
  one-off architecture map in favour of generated SVG diagrams.
- **Critique (Impeccable).** The study's Impeccable passes already fixed muted contrast
  (`#77736b` → `#706c64`, here `#6b675f`), tiny 11 px labels, table header insets and
  long uppercase metadata; those fixes are carried over. The component hues were added
  for this theme and checked for ≥ 4.5:1 text contrast by calculation.
- **Not run in this build session.** Neither the Taste nor the Impeccable skill was
  installed in the build environment (no `impeccable` CLI, no user-scope design-stack
  skills), so no fresh detector pass was run on the generated pages. The theme is not
  declared visually approved: approval is the owner's review of the Playwright
  screenshots `tests/test-plan-page.sh` writes, recorded in the pull request (D19).
