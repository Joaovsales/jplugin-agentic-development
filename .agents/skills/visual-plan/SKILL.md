---
name: visual-plan
description: Render an existing text spec into a self-contained HTML visual plan — typed cards for decisions, criteria, risks, open questions and slices, real diagrams, a blockers panel, the build prompt and a review export — for approval before implementation. Use after /plan has already written specs/<feature>.md.
argument-hint: "[path/to/spec.md]"
disable-model-invocation: false
---

# /visual-plan — Visual Plan Renderer

## Overview

`/plan` writes a text spec. `/visual-plan` does not re-plan: it runs one
renderer over a spec that already exists and writes `specs/<feature>.plan.html`
beside it. The page is rendered from the spec markdown alone, so it can never
disagree with it, and no content model or agent-written summary sits between
the two. It never runs planning itself and never edits source.

The visual plan is the **approval gate**: reviewers read the rendered page, not
the raw markdown, before implementation starts.

## When to Use / When Not

- **Use** after `/plan` has produced `specs/<feature>.md`, for any change
  non-trivial enough that typed decisions, a slice graph or a blockers panel
  would help a reviewer catch a bad assumption early.
- **Don't use** for a typo fix, a config tweak, a one-line change, or a
  single well-specified function — see the skip gate below.
- **Don't use** to write or revise the spec itself — that's `/plan`'s job.
  This skill only renders a spec that's already on disk.

## Skip when trivial (gate)

Before rendering, check the change's actual size and risk against the spec:

- Typo / config value / one-line change / a single well-specified function →
  **skip**. Emit one line: `Skipping visual-plan: <reason>` and stop. Produce
  no file.
- Otherwise, proceed to the process below.

## Inputs

- **Required**: a path to an existing spec, `specs/<feature>.md`. If the
  argument is missing, ask for it — do not guess a spec to render.

## Read-Only Rule

This skill is read-only toward the spec and the source tree: the renderer reads
the spec and writes only the HTML. If the review surfaces changes, they go back
through `/plan` — usually as the page's review export — not through direct
edits from this skill.

## Process

1. **Render** the spec:

   ```bash
   python3 .agents/skills/visual-plan/scripts/plan_render.py specs/<feature>.md -o specs/<feature>.plan.html
   ```

   Known sections become typed components — Summary, Decisions, Acceptance
   Criteria, Risks, Open questions, Constraints, Component contracts, Data
   models, Build Order — and every other `##` section renders as plain
   markdown. Fenced `flow` and `sequence` blocks become SVG diagrams; a `text`
   fence that looks like an ASCII diagram sits in a collapsed text-diagram
   disclosure.

2. **On a refusal**, the renderer prints `<spec>:<line>: <reason>` and exits 1
   without writing the page: a known section is malformed (a ragged table row,
   a duplicate ID, an unknown status, a diagram line the DSL does not accept).
   Report that line and stop — the fix belongs in the spec, through `/plan`.

3. **Print the artifact path** — the renderer's `✓ Visual written: <path>` —
   and stop. That file is what the reviewer opens; do not paste a summary of it
   inline as a substitute.

## Outputs

- `specs/<feature>.plan.html` — one self-contained page: the jplugin plan theme
  inlined, no network requests, legible in light and dark mode and at 390 px.
  Its header names the source spec with a relative link and its SHA-256 prefix;
  the page embeds no copy of the markdown.
- No source changes. No edits to the spec that was read.

## Key Principles

- **Visualize, don't re-plan.** The spec is the input; this skill never
  originates requirements.
- **One source.** The page is rendered from the spec file every time; a stale
  page is re-rendered, never edited.
- **Malformed is loud.** A known section the renderer cannot read fails with
  `file:line`; it is never dropped from the page silently.
- **Skip readily.** A visual plan for a one-line change is noise, not rigor.
- **The HTML is the gate.** Reviewers approve the rendered plan, and send their
  marks back through the review export that `/plan` applies.

## Integration

- **Calls**: `.agents/skills/visual-plan/scripts/plan_render.py` (shared with
  `/system-design-planning` Step 6).
- **Follows**: `/plan` (consumes its `specs/<feature>.md` output).
- **Precedes**: implementation (`/build`) — the visual plan is the approval
  checkpoint before code is written. A review export goes back to `/plan`.
