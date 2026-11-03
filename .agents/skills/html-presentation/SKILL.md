---
name: html-presentation
description: "Generate a polished, self-contained HTML presentation (report or slide-deck) from structured content. Use when another skill or the user needs to publish a session review, design audit, project summary, or any narrative as a beautiful HTML document with strong visual and information-design quality. Triggers on: 'make an html presentation', 'generate a report', 'turn this into slides', or invocation by another skill (e.g. software-design-expert-learn)."
argument-hint: "[input file or markdown] [--mode report|slides] [-o output.html]"
disable-model-invocation: false
harness: universal
---

# /html-presentation — HTML Presentation Generator

## Overview
Produce a single self-contained HTML file (no build step, no external assets) that communicates a narrative clearly and looks great. The skill is reusable: design reviews, project summaries, post-mortems, weekly reports, etc.

The skill has two concerns:
1. **Visual quality** — typography, color, spacing, motion, responsiveness.
2. **Information disposition** — what goes where, in what order, at what density, so the reader understands fast.

Visual polish without information design produces pretty noise. Information design without polish produces a wall of text. This skill does both.

## The Iron Law

```
NEVER ship an HTML presentation without (a) a clear narrative spine and
(b) a defensible information hierarchy. Aesthetics serve the story — not
the other way around.
```

If you cannot state the single takeaway of the document in one sentence, stop and ask the caller for the message before generating anything.

## The Process

1. **Extract the narrative spine**
   - From the input, identify: the audience, the single key message, the 3–5 supporting points, the call-to-action (or reflection prompt).
   - If the input is a long markdown blob, summarize it into this spine first.

2. **Choose the mode**
   - `report` — long-form, scrollable, sectioned. Default for reviews, audits, post-mortems, summaries with depth.
   - `slides` — one idea per screen, keyboard-navigable, dense visuals. Use for talks or executive summaries (<10 sections).
   - When in doubt, default to `report`. Switch only if the caller asks.

3. **Lay out the information**
   Apply the rules in `references/design-principles.md`:
   - Above-the-fold: title, one-sentence takeaway, meta (date, author/project).
   - Summary cards (3–5) before deep detail — answer the "what" before the "why".
   - Detail sections in dependency order: context → evidence → analysis → action.
   - Group related items; never alternate categories.
   - Cap each section at one screen of prose; collapse the rest.

4. **Generate via script**
   Use the provided generator. It accepts a structured JSON input and emits a self-contained HTML file:

   ```bash
   python3 .agents/skills/html-presentation/scripts/generate-presentation.py \
       --input presentation.json \
       --mode report \
       --output presentation.html
   ```

   Or pipe a markdown file directly (the script will infer sections):

   ```bash
   python3 .agents/skills/html-presentation/scripts/generate-presentation.py \
       --markdown review.md \
       --mode report \
       --title "Session Design Review" \
       --output review.html
   ```

5. **Sanity-check the output**
   - Open the file's structure mentally: is the takeaway visible in the first viewport?
   - Are there fewer than 7 nav items? More than 7 = restructure.
   - Does every section earn its place? Cut filler.
   - Does it work in light and dark mode? (The template handles this — just confirm.)

6. **Report the artifact path**
   Print the absolute path of the generated HTML so the caller can open or attach it.

## Input Schema

The structured JSON input (preferred for callers, including other skills):

```json
{
  "title": "Session Design Review",
  "subtitle": "Project X — 2026-05-24",
  "takeaway": "The new auth module hides DB details behind a deep interface.",
  "meta": { "Project": "acme-api", "Date": "2026-05-24", "Author": "claude" },
  "summary_cards": [
    { "label": "Files changed", "value": "7", "hint": "src/auth/*" },
    { "label": "Red flags", "value": "1", "hint": "Pass-through method" }
  ],
  "sections": [
    {
      "id": "context",
      "title": "Context",
      "icon": "📋",
      "body_md": "Markdown content for this section..."
    }
  ],
  "code_blocks": [
    { "lang": "python", "code": "def foo(): ...", "caption": "Before" }
  ],
  "references": [
    { "title": "APOSD Course", "url": "https://..." }
  ],
  "reflection": "If you had to change X tomorrow, how many files would you touch?"
}
```

All keys except `title` and `sections` are optional.

## Information Design Rules (must-follow)

| Rule | Why |
|------|-----|
| One takeaway, stated in the first 100 px | Readers leave fast; lead with the answer |
| 3–5 summary cards, never more | Miller's number; more = decoration |
| Headers communicate, not just label | "Auth is now deep" beats "Auth Module" |
| Inverted pyramid per section | Conclusion, then evidence, then nuance |
| Code blocks have captions explaining intent | Code without context is shape, not signal |
| Sidebar nav ≤ 7 items | If you need more, you have two documents |
| Consistent vertical rhythm (8 px baseline) | Cognitive cost of irregular spacing is real |
| Dark and light themes both legible | Users have preferences; respect them |
| Mobile readable at 375 px width | Many readers open on phones first |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "More sections = more thorough" | Long docs get skimmed. Cut to 5 sections. |
| "The caller will tell me the takeaway" | No — extract it yourself. If you can't, the input is incomplete. Ask. |
| "Slides look cooler" | Slides without a single-idea-per-screen discipline are worse than a report. Default to report. |
| "I'll embed remote fonts/CDN libs" | No — self-contained. System fonts and inline CSS only. |
| "Code blocks speak for themselves" | They don't. Every block needs a one-line caption. |
| "Decorative animations make it modern" | Motion costs attention. Use only for state changes (hover, expand). |

## Red Flags — STOP

- About to ship without a stated takeaway in the first viewport
- Sidebar has 8+ entries (the structure is too flat)
- A section is >500 words with no sub-headers
- More than 3 fonts, more than 5 accent colors
- Diff/code dump with no surrounding narrative
- Light theme is unreadable (low contrast)

## Integration

- **Called by**: `software-design-expert-learn` (session design reviews). Other narrative-producing skills should call this rather than rolling their own HTML.
- **Pairs with**: any skill that produces structured analysis and wants a polished deliverable (`/verify-evidence`, `/wrap-up-session`, `/prd`).
- **Calls**: none — leaf skill.

## Key Principles

- The HTML is a deliverable, not scaffolding. Treat it like a published document.
- Information design is the 80%. Visual design is the 20% that makes the 80% land.
- Self-contained > clever. One file, no network, no build.
- Default to report; choose slides only when the content is genuinely punchy.
- Cut ruthlessly. A shorter document is almost always a better document.

## References

- `references/design-principles.md` — distilled rules from Tufte, Reynolds, Duarte, and modern web information design.
