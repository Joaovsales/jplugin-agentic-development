# Brutalist prototype — method record

**Design Read:** Reading this as an architecture review for technical maintainers, with an editorial brutalist language: poster-scale type, sharp rules, warm paper, and a single signal red.

**Dials:** `DESIGN_VARIANCE: 7` · `MOTION_INTENSITY: 1` · `VISUAL_DENSITY: 6`.

## Inputs and use

| Source | What was used | What was deliberately not transferred |
| --- | --- | --- |
| [`codex-scout-routing.plan.html`](../../../specs/codex-scout-routing.plan.html) and source Markdown at the same spec stem | Issue #158 scope, routing values, four boundaries, three contracts, ten constraints, file states, six build slices, six decisions, eight acceptance outcomes | Existing GitHub-like dark cards, sidebar chrome, generic gradient heading |
| [taste-skill](https://github.com/Leonxlnx/taste-skill), `skills/taste-skill/SKILL.md` | Design Read and three dials; one accent, all-sharp shape system, explicit mobile collapse, reduced-motion support, avoidance of AI-purple and decorative status dots | React/Tailwind defaults, because this artifact must remain a single portable HTML file |
| [impeccable](https://github.com/pbakaus/impeccable), `skill/SKILL.src.md`, `reference/new-work.md`, `reference/craft-floor.md`, `reference/layout.md`, `reference/typeset.md`, `reference/adapt.md`, `reference/polish.md` | Read mode, hierarchy built for comprehension, bounded QA, focus and mobile interaction, 44px-ish touch controls, responsive reflow, honest copy | Durable `PRODUCT.md`/`DESIGN.md` setup and concept-choice workflow; this is an isolated prototype with a direction pinned by the parent assignment, and writing those shared files is outside this agent's owned surface |
| [awesome-design-md](https://github.com/VoltAgent/awesome-design-md), `design-md/posthog/DESIGN.md` | Specific reference: warm cream reading canvas, deep olive-charcoal ink, one saturated warm accent, flat bordered documentation surfaces, restrained code blocks | Brand-owned hedgehog illustrations, CTA pills, and PostHog-specific components; the page is not presented as PostHog |
| [img2threejs](https://github.com/img2threejs/img2threejs), `SKILL.md` | Read the image-to-3D process and kept visual depth in a separate routing-layer motif, making the plan's three layers legible | No image reconstruction was run in this prototype: no reference image is part of the issue #158 plan. The sibling spatial prototype owns the stack's actual reconstruction and staged evidence. The motif here is CSS geometry, not an img2threejs output. |

## Content and design decisions

- The first viewport states the actual risk: unpinned read-heavy children inherit parent model and effort. The three stacked planes make `Scout → policy → Ceiling` visible without implying that a single global model controls all roles.
- Scout, Planner, Builder/Reviewer, and Ceiling are shown as distinct routes. The non-Scout mappings are labeled as assumptions from the source plan.
- The migration section separates the five installed-file states; only an exact legacy candidate has an adoption path. Personal conflicts and invalid files stay visibly protected.
- The six slice cards preserve each dependency, AC link, file surface, and affected-test command. Native `<details>` disclose long paths while retaining keyboard access and a printable content path.
- The acceptance outcomes are complete, not a status dashboard. The source plan is draft; no implementation status is invented.
- Native CSS and small inline JavaScript keep the artifact self-contained. It has a keyboard-accessible contents drawer, Escape dismissal, in-page navigation with current-section indication, theme inversion, skip link, focus states, and reduced-motion rule.
- A final typography pass raised readable technical/body copy to 13–15px, increased the two compressed lead paragraphs to at least 1.3 line height, gave functional menu/summary controls a 44px minimum height, and tightened the mobile mast layout so the theme control stays on one line. The desktop title was reduced slightly to avoid crowding the routing-layer visual.

## Tools called and outputs

| Tool / command | Output or finding |
| --- | --- |
| `sed -n '1,240p' specs/codex-scout-routing.plan.html` | Read incumbent HTML, styling and client behavior. |
| `sed -n '1,260p' scratch/taste-skill/skills/taste-skill/SKILL.md`; `rg -n 'anti\|pre-flight\|motion\|font\|contrast\|responsive\|layout\|density\|a11y' scratch/taste-skill/skills/taste-skill/SKILL.md` | Read design inference/dials and located responsive, contrast, anti-slop, and motion rules. |
| `sed -n '1,260p' scratch/impeccable/skill/SKILL.src.md`; `sed -n '1,105p' scratch/impeccable/skill/SKILL.src.md` | Read setup, Read mode, design and QA guidance. |
| `rg --files scratch/awesome-design-md`; `cat scratch/awesome-design-md/design-md/posthog/DESIGN.md` | Chose a concrete warm-paper documentation system; extracted palette and flat surface discipline. |
| `sed -n '1,240p' scratch/img2threejs/SKILL.md` | Confirmed staged reconstruction requires a real image and evidence; none was claimed here. |
| `rg -n '<h[1-4]\|<section\|id="\|<li\|<summary' specs/codex-scout-routing.plan.html`; `rg -n '^## (Constraints\|System design\|Component contracts\|Data models\|Build Order\|Decisions\|Acceptance Criteria)\|^\\| [1-6] \\|\|^- ' specs/codex-scout-routing.md`; stdlib `html.parser` extraction | Captured problem, constraints, contracts, data model, six slices, decisions, and ACs. A first `bs4` extraction failed with `ModuleNotFoundError`; stdlib parser supplied the text without installing a dependency. |
| `cat scratch/impeccable/skill/reference/{layout,typeset,adapt,polish}.md`; `cat scratch/impeccable/skill/reference/{new-work,craft-floor}.md` | Applied semantic spacing, responsive flow, focus, and bounded inspection principles. |
| `scratch/impeccable/skill/scripts/impeccable context --target design/prototypes/brutalist/index.html` | Reported `NO_PRODUCT_MD`, `PRODUCT_INIT_REQUIRED`, and `MANUAL_DETECTOR_REQUIRED`; no active detector hook. The parent owns full visual QA. |
| `mkdir -p design/prototypes/brutalist`; `apply_patch`; two targeted `python3` file edits | Created `index.html`; then wrapped each acceptance-item body in one span after the first screenshot exposed CSS Grid splitting inline code into new cells. Replaced low-contrast signal colors, reduced tracking, and removed repeated small section-number marks. |
| `view_image scratch/brutalist-first.png` | Inspected the parent's first full-page capture; found narrow vertical AC text and corrected its cause. |
| `scratch/impeccable/skill/scripts/impeccable detect --json design/prototypes/brutalist/index.html` | One mechanical pass flagged red/white contrast, tight tracking, repeated section-number scaffolding, and generic Arial. The first three were corrected. The Arial-based stack remains a portability tradeoff for a self-contained prototype. Some variable/theme pairings in the detector were mutually impossible at runtime; the parent is checking the actual render. |
| `fc-list : family \| sort -u \| head -80`; `fc-match -f '%{file}\\n' 'Nimbus Sans Narrow' \| head -1`; Python WCAG-ratio calculation | Checked local font availability and verified chosen signal pairs: 5.38:1 on white, 4.54:1 on paper, and 6.96:1 for bright signal on dark ink. A local-only font was not embedded. |
| stdlib `html.parser` ID/link check; `git diff --check -- design/prototypes/brutalist`; `git status --short design/prototypes/brutalist`; `wc -l design/prototypes/brutalist/index.html` | 13 unique IDs, 12 valid internal links, no duplicate IDs. `git diff --check` printed nothing; as the files are untracked, that command did not validate their whitespace. `git status` showed the new prototype folder. |
| `view_image scratch/brutalist-fold.png`; `view_image scratch/brutalist-mobile-top.png`; `rg -n 'font:.*(10px\|11px\|12px)\|font-size:(10px\|11px\|12px)\|line-height:1\\.0[0-9]\|line-height:1\\.1' design/prototypes/brutalist/index.html` | Inspected earlier desktop/mobile captures and found the mobile theme label wrapping and small route labels. Located each small CSS role before editing. |
| Python summary of `scratch/impeccable-final.json` | Before edits: 10 `tiny-text`, 7 `undersized-ui-text`, 2 `tight-leading`, plus color and stylistic warnings for this file. |
| `scratch/impeccable/skill/scripts/impeccable detect --json design/prototypes/brutalist/index.html > scratch/brutalist-after.json`; Python `Counter` summary | After edits: 0 `tiny-text`, 0 `undersized-ui-text`, 0 `tight-leading`. Remaining: 5 low-contrast, 5 uppercase-body, 1 cramped-padding, 1 overused-font, 1 cream-palette. Exit 2 reflects those remaining findings. |

## Outputs and current limits

- `index.html`: self-contained architecture review prototype; no external fonts, libraries, images, or network dependency.
- `METHOD.md`: this trace.
- The first full-page parent capture, `scratch/brutalist-first.png`, exposed the acceptance-grid defect, now fixed in source. The parent is responsible for fresh desktop/mobile Playwright screenshots and final visual review.
- Two later parent captures, `scratch/brutalist-fold.png` and `scratch/brutalist-mobile-top.png`, were inspected for the typography pass. They predate the latest CSS edits; the parent owns fresh screenshots. The detector's remaining low-contrast snippets pair colors from incompatible themes (`#ff795a` on white; `#111111` on `#171714`). Actual token pairs are 5.38:1 (signal on white), 4.54:1 (signal on paper), 6.96:1 (bright signal on ink), and 4.54:1 (dark signal on light hero). The hero has explicit horizontal padding, so the `cramped-padding` output does not match the CSS. Uppercase metadata and cream paper remain deliberate editorial choices; Arial remains an offline portability compromise.
- No actual Three.js model or image-to-3D result is claimed by this variant. The spatial sibling carries that workflow.
