# Spatial prototype — method record

## Design read

**Design Read:** An architecture reviewer needs to understand a precise routing change and its risks quickly; make the policy tangible through a restrained technical exhibit, then return to the real contracts and build sequence.

Taste dials: `DESIGN_VARIANCE: 7` (asymmetric exhibit and fixed rail), `MOTION_INTENSITY: 2` (view changes only), `VISUAL_DENSITY: 6` (compact evidence and a full review record). The single copper accent marks Scout routing and review points. Sharp corners and thin rules are consistent throughout.

## Sources and how they were used

| Source | Method used | Result |
|---|---|---|
| `specs/codex-scout-routing.plan.html` and `.md` | Read both source artifacts; extracted the problem, constraints, native role contracts, six build slices, decisions, and eight acceptance criteria. | `index.html` keeps the architecture facts visible and labels this page as a prototype. The linked Markdown remains the authority for exact file surfaces and fixtures. |
| `scratch/taste-skill/skills/taste-skill/SKILL.md` | Applied its Design Read and dial method, anti-template composition, one accent, explicit mobile collapse, and restrained motion. | Split first viewport, varied section structures, and responsive CSS. |
| `scratch/impeccable/skill/SKILL.src.md`, `reference/new-work.md`, `reference/craft-floor.md` | Applied the **Read** mode, proof-first first viewport, browser-surface styling, contrast and spacing checks, and a bounded visual-review intent. Ran its context and detector commands. | Source/render comparison and the contracts are the evidence. The full Impeccable init/decision/comp workflow was not run: this is one scoped prototype within a three-agent experiment, with no project `PRODUCT.md` or `DESIGN.md` to change. |
| `scratch/awesome-design-md/design-md/hashicorp/DESIGN.md` | Studied its near-black technical canvas, restrained per-product accent logic, Plex-like functional typography scale, and charcoal surfaces with hairlines. Adapted those ideas, rather than treating the file as an installable design-system package. | Local Plex Sans/Mono, near-black and blue-charcoal surfaces, copper accent reserved for this instrument. This is not a HashiCorp-branded page. |
| `scratch/img2threejs/SKILL.md` and intake references | Used the image analysis vocabulary and actual forge intake/state gates. Reconstructed the authored image with a `THREE.Group` of boxes, tubes, sockets, fasteners, materials, lights, and shadows. | `assets/routing-instrument-reference.png` beside live `model.js`. See gate status below. |

## Image → 3D observations and decisions

`generate_reference.py` draws the original raster object using Pillow. It is a deliberately simple, single-object reference: a shallow cuboid enclosure, three inset input tracks, a raised copper selector, one outbound track, and 3+1 sockets on the front. `OBSERVATION.md` records macro, meso, micro, relationships, material inference, and unknowns before the 3D implementation.

The initial charcoal background failed the image admission gate because its foreground could not be segmented (`foregroundCoverage: 1.0`). I changed the raster background to pale gray and reran the gate; it then admitted the image (`foregroundCoverage: 0.4364`, one connected subject). The source and procedural render now use the same pale scene ground for direct comparison. The model is **stylized and approximate**. A single image cannot establish the back, interior, exact dimensions, bevels, or physical material values. The tracks and front socket locations are the identity features to compare; the model's lights create a real material response instead of copying baked pixel highlights.

## Tools called and outputs

| Tool or command | Output and status |
|---|---|
| `python3 design/prototypes/spatial/generate_reference.py` | Authored `assets/routing-instrument-reference.png` (1400 × 850 RGB). |
| `view_image assets/routing-instrument-reference.png` | Visually checked single-object silhouette and feature placement. |
| `python3 forge/next.py --state ...` (before state init) | Reported missing state, as expected. |
| `python3 forge/state.py init --state .img2threejs/state.json --reference ... --profile generic --spec object-sculpt-spec.json` | Created resumable generic-profile state. |
| `python3 forge/stage1_intake/probe_image.py ...` | PNG 1400 × 850, technical suitability pass; semantic inspection remained manual. |
| `python3 forge/stage1_intake/check_reference_admission.py ... --out .img2threejs/admission.json --probe-out .img2threejs/probe.json --json` | First run failed segmentation. Second run passed. Both outcomes informed the background correction. |
| `python3 forge/stage2_spec/new_pre_spec_assessment.py 'Scout routing instrument' --image ... --complexity simple --spec-query 'cuboid enclosure selector sockets satin metal' --out .img2threejs/assessment.json` | Wrote quality-contract skeleton and `core_3d` local-spec search evidence. |
| `python3 forge/stage1_intake/build_detail_inventory.py ... --mode grid-3x3 --out-dir .img2threejs/crops --out .img2threejs/detail-inventory.json` | Wrote nine reference crops and inventory scaffold. |
| `python3 forge/stage2_spec/new_sculpt_spec.py ... --assessment .img2threejs/assessment.json --out object-sculpt-spec.json` | Wrote a starter JSON spec; it remains a scaffold, not a passed production spec. |
| `python3 forge/state.py mark ...` | Recorded image analysis, suitability, admission, local search, assessment, inventory, spec authoring; projection route was explicitly skipped because the source has flat painted colors rather than a painted skin requiring texture projection. |
| `python3 forge/stage2_spec/validate_sculpt_spec.py object-sculpt-spec.json --strict-quality` | **Failed**. The scaffold lacks assessed object class fields, detailed component/material wiring, reference PBR, and lighting spec. I did not misreport this as a passed image-to-3D pipeline. |
| `curl` from unpkg and jsDelivr | Bundled `vendor/three.min.js` (Three.js 0.148.0) and three IBM Plex WOFF2 files locally; no runtime CDN dependency. |
| `node --check model.js` | Passed JavaScript syntax. |
| `scratch/impeccable/skill/scripts/impeccable context --target design/prototypes/spatial/index.html` | Found no project PRODUCT/DESIGN context; confirmed this is a new scoped surface and requested a manual detector pass. |
| `scratch/impeccable/skill/scripts/impeccable detect --json ...` | Flagged tiny functional labels and a CSS arrow triangle. Raised functional label floors to 11px and replaced the border triangle with a rotated square. Final run has one `cramped-padding` warning for the intentionally flush image/render diptych. |
| `rg`, `sed`, `find`, `view_image`, and `apply_patch` | Read source contracts and skill references, inspected the authored raster and parent-provided Playwright screenshot, located local assets, and wrote the prototype. Parent screenshot feedback led to closer model framing and darker material/lighting. |

The forge pipeline is **not complete**: material-region evidence, material-spec wiring, a passing strict validation, its locked build-pass generator, deterministic render diagnostics, turntable and self-intersection gates, AI review recording, and action-ready/part-coverage gates were not run. The browser model is hand-authored from the observed part hierarchy as a timeboxed prototype; the parent agent's Playwright screenshots are the visual QA evidence for the page and a source/render comparison, not forge pass certification. The final `forge/next.py` run reports `status=active`, `step=material-evidence`, `pass=blockout`, with those production stages pending. The `.img2threejs/state.json` file preserves this open status.

## Generated files

- `index.html`, `style.css`, `model.js`: the standalone responsive review surface and procedural viewer.
- `assets/routing-instrument-reference.png`, `generate_reference.py`, `OBSERVATION.md`: source raster, its generator, and prior observation.
- `object-sculpt-spec.json`, `.img2threejs/`: forge starter spec, state, admission, assessment, probe, and cropped intake evidence.
- `vendor/three.min.js`, `fonts/*.woff2`: local runtime assets for `file://` or HTTP viewing.
- `vendor/LICENSE-three.txt`, `fonts/OFL-ibm-plex-sans.txt`, `fonts/OFL-ibm-plex-mono.txt`: upstream license texts retained beside the bundled runtime and fonts. The parent agent fetched these after the browser review.

No routing policy files, skill dispatch instructions, or installer behavior were changed by this prototype.
