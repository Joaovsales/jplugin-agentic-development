# Visual plan design study

Three independent presentations of the same [Codex Scout Routing architecture review](../specs/codex-scout-routing.plan.html) test a small design stack before any harness integration.

Method records use `scratch/` for temporary upstream checkouts and captures; those local paths are not part of this study.

| Direction | Prototype | Method record |
| --- | --- | --- |
| Editorial brutalist | [Open](prototypes/brutalist/index.html) | [Read](prototypes/brutalist/METHOD.md) |
| Minimal technical journal | [Open](prototypes/minimalist/index.html) | [Read](prototypes/minimalist/METHOD.md) |
| Spatial technical exhibit | [Open](prototypes/spatial/index.html) | [Read](prototypes/spatial/METHOD.md) |

The prototypes are comparison artifacts. They do not replace `/visual-plan` or change the plan, build, wrap-up, or verification workflows. Their source content is the existing #158 spec; the interaction and visual treatment are experimental.

## Inputs

- [Taste skill](https://github.com/Leonxlnx/taste-skill) (`ce26fc2`) for brief inference and anti-template design decisions.
- [Impeccable](https://github.com/pbakaus/impeccable) (`0d6b47e`) for critique, polish, accessibility, and responsive checks.
- [Awesome Design MD](https://github.com/VoltAgent/awesome-design-md) (`f696123`) for specific documented visual references, named in each method record.
- [img2threejs](https://github.com/img2threejs/img2threejs) (`6e60b5e`) for the reference-image-to-procedural-3D experiment in the spatial direction.
- Playwright with its installed Chromium for screenshots and browser checks. Results are in [QA](QA.md) and [screenshots](screenshots/).

The GitHub repositories were read from temporary shallow checkouts. The prototypes and their method records are the files retained in this folder.

The spatial prototype bundles Three.js and IBM Plex font files for local viewing; their MIT and OFL texts are retained beside those assets.
