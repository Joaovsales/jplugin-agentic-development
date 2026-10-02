# Visual QA record

The source is the draft Codex Scout Routing review for issue #158. These checks assess the three prototype surfaces; they do not certify the routing implementation or the full img2threejs production pipeline.

## Playwright capture

`python3 design/qa.py` drove Playwright's installed Chromium against each `file://` page at 1440 × 900 and 390 × 844, with reduced motion enabled. It wrote [machine results](qa-results.json) and six full-page screenshots:

| Direction | Desktop | Mobile |
| --- | --- | --- |
| Brutalist | [Screenshot](screenshots/brutalist-desktop.png) | [Screenshot](screenshots/brutalist-mobile.png) |
| Minimalist | [Screenshot](screenshots/minimalist-desktop.png) | [Screenshot](screenshots/minimalist-mobile.png) |
| Spatial | [Screenshot](screenshots/spatial-desktop.png) | [Screenshot](screenshots/spatial-mobile.png) |

All six final captures had one `h1`, no console or page errors, no broken images, and document width equal to viewport width. Static HTML parsing found no duplicate IDs or broken in-page anchors; all three pages contain Scout, Ceiling, Luna, migration, build order, and acceptance content. Playwright activated both theme controls and the spatial front-view control. The spatial page reported a live model, rendered one canvas, and updated `aria-pressed` on view change.

The spatial model was also captured beside its source raster from the [reference](screenshots/spatial-reference-comparison.png), [front](screenshots/spatial-front-comparison.png), and [top](screenshots/spatial-top-comparison.png) views. The source has one viewpoint, so the front and top views test whether the inferred 3D form is coherent; they cannot prove hidden geometry or exact material values.

## Review and corrections

- The first brutalist capture exposed acceptance text compressed into narrow columns. The acceptance item now has one explicit grid text cell. Accent contrast and small labels were corrected after the Impeccable detector pass.
- The first minimalist capture remained too close to the original long document flow. A four-stage routing diagram and six-slice dependency timeline now carry the central argument.
- The first spatial capture raced with its CSS write; the missing stylesheet caused overflow and a console error. Final captures load the stylesheet cleanly. The 3D shell was darkened and moved closer to the source image after the first visual comparison.

The image-to-3D intake and admission gates passed. Its strict sculpt-spec quality gate failed, and later forge review gates were not run. The [spatial method record](prototypes/spatial/METHOD.md) names the missing fields and open stages. The browser reconstruction is a visual prototype, not a certified img2threejs output.

The final Impeccable source scan still emits stylistic and context-sensitive warnings: brutalist (13, including cross-theme color pairings and intentional uppercase labels), minimalist (5, chiefly border inset heuristics), and spatial (1, the flush source/render comparison frame). The agents inspected rendered colors and spacing; their method records explain the intentional choices. The browser checks above are the final surface evidence.
