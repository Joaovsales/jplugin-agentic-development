# Minimalist technical journal — method record

## Design read

Reading this as an architecture review for technical maintainers, with a quiet editorial language that makes routing precedence and build dependencies easier to inspect.

Taste dials: `DESIGN_VARIANCE: 5` · `MOTION_INTENSITY: 2` · `VISUAL_DENSITY: 4`. The document needs generous reading space but contains exact contracts and fixtures, so density rises above the usual editorial preset.

## Sources and methods

| Source | Method applied | Observable output |
|---|---|---|
| [Original visual plan](../../../specs/codex-scout-routing.plan.html) and [source spec](../../../specs/codex-scout-routing.md) | Read the actual problem, constraints, components, data models, six slices, decisions, and eight acceptance criteria. Reused the substantive plan content, then changed its visual hierarchy. | [index.html](index.html) retains all major sections and their detail. |
| [taste-skill SKILL.md](https://github.com/Leonxlnx/taste-skill) | Inferred audience and page kind; selected dials before layout; avoided the centered hero plus identical metric cards. | Asymmetric oversized title, removed the original five-card dashboard summary, restrained motion. |
| [Impeccable SKILL.src.md](https://github.com/pbakaus/impeccable), `reference/new-work.md`, `reference/layout.md`, `reference/typeset.md`, `reference/craft-floor.md` | Used Read mode and the layout/type/craft checks: reading measure, distinct grouping, warm contrast, responsive reflow, focus states, reduced motion. | Sticky contents navigation, warm paper palette, tabular information, precise routing map, dependency timeline. |
| [Cursor DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/cursor/DESIGN.md) | Used its warm cream canvas, near-black ink, orange emphasis, hairline rules, and low-chrome editorial rhythm as **reference**, not as an official design system. | Native CSS design tokens in [index.html](index.html); no Cursor package or fonts copied. |
| [img2threejs SKILL.md](https://github.com/img2threejs/img2threejs/blob/main/SKILL.md) | Read its staged image → quality contract → spec → pass-by-pass code model → multi-view evidence approach. This page links the [spatial companion](../spatial/index.html), whose agent owns the actual reconstruction and evidence. | The companion link is visible at the end of [index.html](index.html). This variant contains no 3D model and makes no fidelity claim. |

## Tool calls and generated output

- `sed`, `rg`, `cat`, `find`, and `fc-list`: inspected the original HTML, source Markdown, design skill/reference files, installed fonts, and the local prototype folder. These calls were read-only.
- `mkdir -p design/prototypes/minimalist`: created this variant's folder.
- An initial `apply_patch` call to create the HTML failed on an unprefixed multiline `<pre>` line; it changed no file.
- `python3` (inline, first call): extracted the original main content, replaced the hero and metric cards, converted Markdown-style preformatted tables into semantic HTML tables, added a native CSS visual system, and wrote [index.html](index.html).
- `python3` (inline, second call): added the four-stage architecture map, six-slice timeline and dependency key, corrected local reference links, removed the emoji from the references heading, and linked the spatial companion. It updated [index.html](index.html).
- `python3` HTMLParser: checked 13 IDs, zero duplicate IDs, and zero broken in-page anchors before the diagram pass. The parent agent owns the final Playwright visual review.
- `rg` and `git status --short`: checked section/table coverage and that changes stayed in this owned folder.
- This file was written with a shell heredoc. No Playwright, 3D forge command, image-generation tool, external service, or commit was run by this agent.

## Design decisions and limits

The page preserves the spec's facts and draft status. It visually foregrounds the central consequence: Scout is a named Luna route while Ceiling inherits the parent. The six slices retain their actual blocking order; the compact dependency key is an overview, while each timeline row names its predecessor and acceptance criterion. Theme state is local to this document and follows the system preference on first load.

The self-contained prototype uses browser-available Georgia and Arial rather than bundling fonts. The source plan's text remains dense in contracts and data models because those are the reviewable substance. The linked spatial study is produced and checked separately; this method record does not imply its image-to-3D quality gates have passed.

## Legibility refinement and detector disposition

The parent agent's first Impeccable browser scan reported 16 low-contrast, 4 tiny-text, and 12 cramped-padding warnings on this page. I inspected computed styles with Playwright at 1440px and 390px. Muted text was `#77736b` on `#f7f7f4` (about 4.4:1), and folio, table headers, map labels, and slice metadata were 11px. I changed muted light text to `#706c64` (4.87:1), raised those labels to 12px, preserved dark muted contrast (6.82:1), and fixed the skip link's hover color on its dark background. Both inspected viewports had no document-level horizontal overflow in light or dark theme.

For spacing, I moved the table's top rule from its wrapper onto header cells so text has its actual 15px inset inside the visible rule. Diagram padding remains 20–42px. The original detector's diagram and route-band cramped-padding flags treated intentional bordering lines as if the children were flush; the rerun reports no cramped-padding finding. I also narrowed prose and lists to 62ch/64ch and the timeline to 760px, removed uppercase from long metadata, and reduced label tracking. The final Impeccable browser scan reports two style findings and no contrast, tiny-text, cramped-padding, line-length, wide-tracking, or all-caps findings.

The two remaining detector findings are intentional design choices:
- `italic-serif-display`: only “Routing.” is italic. Its weight and orange color distinguish the route concept from the title's subject; all body, code, and data remain upright.
- `overused-font`: Arial covers body, tables, and controls as one reliable self-contained sans face; Georgia handles the editorial display. Bundling a custom font would make this HTML prototype heavier and less portable.

Follow-up tools: `python3` filtered the parent's `scratch/impeccable-final.json`, Playwright read computed browser styles without taking screenshots, `impeccable detect --json file://…/index.html` ran twice after edits, and `python3` calculated WCAG contrast. Detector output is at `scratch/minimalist-detect-final.json`.
