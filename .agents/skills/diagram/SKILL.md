---
name: diagram
description: "Draw a checked, explorable standalone HTML diagram of a system, flow, schema or history through the installed Archify tool — architecture, workflow, sequence, dataflow, lifecycle, ERD, class, tree, timeline or waterfall. Use when the user asks to diagram, draw, visualize, map or sketch an architecture, a request flow, a pipeline, a module tree or a data model, or says 'archify this'. A diagram of a real codebase cites source at the pinned HEAD; `--refresh <path>` re-authors a committed one. Not for narrative pages, reports or slides (html-presentation), rendered plans (visual-plan) or branch recaps (visual-recap)."
argument-hint: "<what to draw> | --refresh <candidate.json | diagram.html>"
disable-model-invocation: false
harness: universal
---

# /diagram — Archify as an installed diagram tool

## Overview

`/diagram <what>` turns a system, flow, schema or history into a standalone
HTML diagram that Archify has validated, delivered and checked. Archify is
[tt-a1i/archify](https://github.com/tt-a1i/archify), installed once in user
scope as a **pinned tool** under `$ARCHIFY_HOME` (default
`~/.local/share/jplugin/archify`) — never as a skill the harness can route to
and never as a copy in this repository, so `/diagram` is the only diagram
entry point and the drawing instructions stay upstream's. This page adds what
jplugin needs around them: the tool and Node check, the browser, and the
conventions below.

The homegrown `flow` / `sequence` fences inside specs are unchanged: the
visual-plan renderer draws those inline. Archify draws the standalone
diagrams.

## Step 1 — Resolve the tool

```bash
eval "$(bash .agents/skills/diagram/scripts/archify.sh resolve)"
```

The resolver prints `export` lines for `ARCHIFY_HOME`, `ARCHIFY_BIN` (the CLI
entry point) and `ARCHIFY_SKILL` (upstream's `SKILL.md`), and `ARCHIFY_CHROME`
when a browser was found: an existing `ARCHIFY_CHROME` first, then a Chrome or
Chromium on `PATH`, then the Chromium `playwright-cli` installed. Its notes go
to stderr.

A non-zero exit **stops the skill**. Relay the note as printed — the one-line
install command when the tool is absent, the `Node >= 18` requirement when
`node` is missing or too old — and produce nothing: no DSL fallback, no
html-presentation fallback, silent or otherwise. Node is the hard requirement;
a browser is not. When the resolver reports that no browser was found, the
run continues on Archify's non-browser gates (`validate`, `deliver`, `check`)
and the reply **must** carry the marker it prints:
*automated checks passed without browser evidence*.

## Output

Follow Archify's output contract from `$ARCHIFY_SKILL` § Output: lead with a
clickable Markdown link to the HTML, add one or two sentences of takeaway
when the subject is a real codebase, and state anything that changes how the
diagram should be read. Never claim visual review that did not happen; when
the browser gate did not run, say so with the marker above.

## Edge cases

| Situation | Behaviour |
|---|---|
| tool absent under `$ARCHIFY_HOME` | the install command is printed and `/diagram` stops; no fallback renderer |
| `node` absent or older than 18 | stated with the `Node >= 18` requirement and stopped |
| no Chrome, Chromium or playwright-cli browser | non-browser gates run; the reply says *automated checks passed without browser evidence*; the diagram is still delivered |
| `finalize` exits non-zero | never success: follow upstream's repair contract and report the failing gate when repair is exhausted |
| "a page", "an explainer", "a report" | not `/diagram` — route to `/html-presentation`; Archify's explainer mode is not exposed (D5) |

## Integration

- **Installed by**: `install.sh` step 6c when Node >= 18 is present; otherwise
  the resolver's printed command is the only install path (Pi and Codex
  sessions never ran `install.sh`).
- **Pinned by**: `.github/upstreams.json` (`kind: installed`, tag `v3.2.0`),
  reported by the weekly drift job and `/tidy`'s `tools` check.
- **Offered by**: `/how` after every explanation and `/plan` after a
  multi-component spec; **produced by** `/system-design-planning` beside its
  architecture spec.
