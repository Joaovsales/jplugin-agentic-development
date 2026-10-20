# Spec: Visual Plan & Visual Recap Skills

> Status: **Draft — awaiting approval**
> Author: session `claude/visual-plan-recap-skills-3wgpnv`
> Inspiration: `BuilderIO/skills` (`visual-plan`, `visual-recap`) — adapted to
> a self-hosted, file-based, no-MCP model.
> Superseded for `/visual-plan`: specs/readable-visual-plans.md renders the plan page from the
> spec markdown through `.agents/skills/visual-plan/scripts/plan_render.py`; the content model and `visual-render.py`
> path below remain the contract for `/visual-recap` only.

## 1. Summary

Add two **opt-in** skills that turn text-only planning and change-summaries into
polished, self-contained **HTML visual documents**, rendered locally via the
existing `html-presentation` skill — no external service, no MCP connector.

- **`/visual-plan`** — before implementation. Reads the spec `/plan` wrote and the
  real files/symbols, and renders `specs/<feature>.plan.html`: narrative,
  architecture/data-flow sketch, annotated file map, open-questions block,
  optional wireframe.
- **`/visual-recap`** — after implementation. Reads the branch's `git diff` and
  renders `tasks/recaps/<branch>.recap.html`: 1–3 paragraph narrative,
  mechanically-derived structured blocks (data-model / api-endpoint / file-tree),
  and 3–8 "key change" annotated diff sections.

Both are **borrowed discipline, local backend** (the approved "Hybrid" model):
we keep BuilderIO's block taxonomy, the "true by construction" rule, and the
key-changes structure, but drop their hosted app.

## 2. Goals / Non-Goals

**Goals**
- Richer review surface than a chat-only plan/summary, as a file in the repo.
- Zero external dependencies; works offline and in CI/non-interactive sessions.
- Survives `/sync` (no edits to template-managed skills).
- Opt-in and gated — used only when a change warrants it.

**Non-Goals (v1)**
- No hosted/shareable links, no live prototypes (BuilderIO-hosted features).
- No Mermaid/JS-charting libraries (would violate the no-CDN, self-contained rule).
- No automatic invocation from `/plan` or `/wrap-up-session` (those are
  `/sync`-managed; auto-hook is a future upstream contribution — see §9).

## 3. Rendering Strategy (de-risked by spike)

`generate-presentation.py` is a markdown-subset → styled HTML renderer. Spike
findings:

| Capability | Native support | Plan |
|-----------|----------------|------|
| Hero, takeaway, summary cards, sections, references, themes | ✅ | Use as-is |
| Captioned code blocks | ✅ | Use for annotated diffs |
| Fenced ```` ```diff ```` blocks | ✅ (monochrome) | Color via post-processor |
| `+`/`−` diff line coloring | ❌ | Post-processor injects CSS |
| Tabbed "key changes" | ❌ | Post-processor injects tabs CSS+JS |
| Wireframes / diagrams | ❌ | v1: ASCII-in-code-block; defer richer |
| Raw HTML in `body_md` | ❌ (escaped) | Do not rely on it |

**Post-processor** (`scripts/visual-render.py`, owned by the new skills, ~40–60
LOC, no CDN): takes the JSON content model → calls `generate-presentation.py` to
produce base HTML → injects a `<style>`/`<script>` block before `</head>` that
(a) colors lines in `<code class="lang-diff">` and (b) enables `.tabset`/`.tab`
switching. Because it lives in the new skills' `scripts/`, it is **not**
`/sync`-managed and does not touch `html-presentation`.

DRY note: exactly one copy of `visual-render.py` is shared by both skills
(placement decided in `/plan` — candidate: one skill owns it, the other calls it
by path). No duplication of the injection logic.

## 4. `/visual-plan` — Behavior

**Inputs**
- Path to an existing spec (`specs/<feature>.md`) — required; the skill does not
  re-run planning, it visualizes an existing plan.
- The real codebase (read-only) for file/symbol grounding.

**Gate (skip when trivial)** — do not generate for typo/config/one-line changes
or a single well-specified function. Emit a one-line reason and stop.

**Process**
1. Read the spec + referenced files/symbols (read-only; no source edits).
2. Build a content model (JSON) with these blocks, in order:
   - **Narrative** (1–3 paragraphs, concrete, real product examples).
   - **File map** — annotated list of files to be touched, each with a one-line
     role. Derived from the spec + actual repo paths (must exist or be marked NEW).
   - **Architecture / data-flow** — ASCII/box sketch in a fenced block.
   - **Open questions / decisions** — hard-to-reverse choices (wire format, data
     shapes, ownership) called out explicitly.
   - **Wireframe** (optional) — only if the change has a UI surface; ASCII v1.
3. Render to `specs/<feature>.plan.html` via the post-processor.
4. Print the artifact path; surface it for review. Plan is the approval gate.

**Outputs**
- `specs/<feature>.plan.html` (self-contained).
- No source changes.

## 5. `/visual-recap` — Behavior

**Inputs**
- Git ref range (default: merge-base of the branch vs. default branch → `HEAD`).
- The diff and changed files (read-only).

**Gate (skip when trivial)** — skip for tiny single-file diffs that review faster
as plain `git diff`. Emit reason and stop.

**Process**
1. Compute the diff mechanically (`git diff <base>...HEAD`, `--stat`, name-status).
2. Build the content model, **every structured block true by construction**
   (derived from actual diff lines, never inferred):
   - **Narrative** (1–3 paragraphs): what changed and why, risk notes. Prose is
     the *only* place interpretation is allowed.
   - **file-tree** block: changed files with add/mod/del flags + churn, from
     `--name-status`/`--stat`.
   - **data-model** block: only if schema/migration/model files changed — the
     before/after fields, quoted from the diff.
   - **api-endpoint** block: only if route/handler signatures changed — quoted.
   - **Key changes**: 3–8 tabs, each a focused annotated diff hunk (~≤150 lines,
     ≤70-char title). One tab per meaningful change cluster.
3. Render to `tasks/recaps/<branch-slug>.recap.html` via the post-processor.
4. Print the artifact path.

**Outputs**
- `tasks/recaps/<branch-slug>.recap.html` (self-contained).
- `tasks/recaps/` is gitignored by default (transient); overridable.

## 6. Content Model (shared schema)

Both skills emit the `html-presentation` JSON schema (`title`, `subtitle`,
`takeaway`, `meta`, `summary_cards`, `sections[]`, `references`, `reflection`),
with two conventions the post-processor understands:

- A section whose `body_md` contains a fenced ```` ```diff ```` block → diff
  coloring applied.
- A section tagged (via a sentinel in `id`, e.g. `id: "keychange-*"`) → grouped
  into a `.tabset` by the post-processor.

This keeps the generator's input contract unchanged.

## 7. Authoring & Structure

Each skill authored via `/writing-skills`, standard layout:

```
.claude/skills/visual-plan/SKILL.md
.claude/skills/visual-recap/SKILL.md
.claude/skills/<one-of-them>/scripts/visual-render.py   # shared post-processor
.agents/skills/…                                        # canonical copies (harness-neutral)
```

Both carry: frontmatter (name, description, argument-hint), the gate, the
content-model construction steps, the "true by construction" iron law (recap),
and a call to `generate-presentation.py` + post-processor.

## 8. Acceptance Criteria

- **AC1** `/visual-plan <spec>` on a non-trivial spec produces a self-contained
  `specs/<feature>.plan.html` that opens with no network, in light and dark mode,
  containing narrative + annotated file map + open-questions.
- **AC2** `/visual-plan` on a trivial change emits a skip reason and produces no file.
- **AC3** `/visual-recap` on a multi-file branch produces
  `tasks/recaps/<branch>.recap.html` with a file-tree block whose entries match
  `git diff --name-status` exactly (true by construction).
- **AC4** `/visual-recap` renders 3–8 key-change tabs that switch client-side
  with no external assets.
- **AC5** Diff blocks render with `+` green / `−` red coloring in both themes.
- **AC6** Neither skill edits `generate-presentation.py` or any `/sync`-managed
  file; `visual-render.py` is self-contained and CDN-free (grep: no `http`
  asset refs in output `<head>` beyond inline).
- **AC7** `/visual-recap` structured blocks contain no field/route not present in
  the diff (spot-checkable against the diff).

## 9. Future (out of scope, noted)

- Upstream a one-line opt-in call into the template's `/plan` and
  `/wrap-up-session` so visual artifacts generate automatically.
- Richer diagrams (inline SVG generated by the skill, still self-contained).
- `share-resource` equivalent: commit the HTML + a short index for PR review.

## 10. Risks & Mitigations (from pre-mortem)

| Risk | Mitigation |
|------|-----------|
| HTML artifacts rot / clutter | Opt-in + gate; recaps gitignored by default |
| Backend can't express diffs/tabs (confirmed) | Owned post-processor injects CSS/JS |
| "True by construction" erodes | Iron law in SKILL.md; recap reads `git diff` mechanically |
| `/sync` overwrites work | New skills only; no edits to managed files |
