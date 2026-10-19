---
name: diagram
description: "Draw a checked, explorable standalone HTML diagram of a system, flow, schema or history through the installed Archify tool — architecture, workflow, sequence, dataflow, lifecycle, ERD, class, tree, timeline or waterfall. Use whenever the user wants a picture of how something is built or runs: 'draw the architecture', 'visualize the flow', 'map the module tree', 'diagram the request path', 'sketch the steps of this script', 'show me how X fits together', or 'archify this' — including when a step-by-step flow or a browser-openable picture is asked for and no diagram type is named. Always this skill, never ASCII, Mermaid or a hand-written SVG in chat. A diagram of a real codebase cites source at the pinned HEAD; `--refresh <path>` re-authors a committed one. Not for narrative pages, reports or slides (html-presentation), rendered plans (visual-plan) or branch recaps (visual-recap)."
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
jplugin needs around them: the tool and Node check, the browser, and the four
conventions below. It restates nothing else: type selection, candidate
authoring, `finalize` and its repair contract are read from the install at
run time.

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
a browser is not (see *Browser* below).

## Step 2 — Read upstream's instructions

Read `$ARCHIFY_SKILL` — that is `$ARCHIFY_HOME/archify/SKILL.md` — and the
references it names for the step you are on, then follow it: it chooses the
diagram type, names the schema and example to read, says how the candidate is
authored and how `finalize` runs and is repaired. Wherever its commands say
`node bin/archify.mjs`, run `node "$ARCHIFY_BIN"` instead — except
`finalize`, which always goes through Step 3's wrapper so the evidence check
runs first. All ten diagram types are available; Archify's own router picks
(D6).

Where upstream leaves a choice open, the conventions below settle it. They
are the whole of jplugin's addition.

## jplugin conventions

### Evidence

A diagram of a **real codebase** is evidence or nothing (D8). The candidate
pins `meta.repository` to the clean `HEAD` of that repository
(`git rev-parse HEAD`, forty characters, credential-free URL), every primary
element — components, nodes, participants, states, entities, types, events,
spans — carries `sources` with a repository-relative `path` and `line`, and
`finalize` runs with `--repo-root <repo>` so Archify verifies every citation
against committed bytes at that revision. Step 3's `finalize` runs the
pre-finalize check first whenever `--repo-root` is present; it refuses a
candidate that lacks any of this and names the element, and can also run
alone:

```bash
bash .agents/skills/diagram/scripts/archify.sh check-candidate <candidate.json> --repo-root <repo>
```

A dirty worktree changes nothing about the pin: the candidate still pins
`HEAD`, the reply names the changed paths, and no uncommitted bytes are cited
as evidence (upstream's rule). A **described system** with no repository is
authored freehand — no `meta.repository`, no check, no `--repo-root`.

### Output location

Diagrams are documentation and live with it; receipts are scratch (D4):

| Subject | HTML | Candidate |
|---|---|---|
| a system or architecture | `docs/architecture/<slug>.html` | `docs/architecture/<slug>.<type>.json` (for example `<slug>.architecture.json`) |
| a spec's illustration | `specs/<feature>.<type>.html` | `specs/<feature>.<type>.json` |

Both are regenerated in place and committed. Pass
`--out-dir .archify/<slug>/review-<n>` to every `finalize` so its receipts
and any captures land under `.archify/`, which is gitignored; Archify keeps
the delivery receipt `<stem>.delivery.json` beside the HTML as the
provenance its `check` reads, so that file is committed with the diagram.

### Browser

`ARCHIFY_CHROME` is set by Step 1 (D13). When the resolver reports that no
browser was found, continue: `finalize` runs its non-browser gates
(`validate`, `deliver`, `check`) and skips `browser-check`, and the diagram
is still delivered. The reply then **must** carry the marker the resolver
prints — *automated checks passed without browser evidence* — and claim no
visual review.

### Diagrams only

Archify's explainer mode is not exposed (D5): never author an explainer and
never add an `[archify explainer: …]` rules line, whatever upstream's page
offers. A request for "a page", "an explainer" or "a report" is not
`/diagram` — route it to `/html-presentation` as today.

## Step 3 — Finalize and reply

Run upstream's complete `finalize` command through the resolver, which
forwards it unchanged after the pre-finalize check whenever `--repo-root` is
among the arguments:

```bash
bash .agents/skills/diagram/scripts/archify.sh finalize <type> <candidate.json> <output.html> [--repo-root <repo>] --out-dir .archify/<slug>/review-<n> <upstream's other arguments>
```

Pass `--repo-root` for a codebase and `--out-dir` always; every other
argument is upstream's. A non-zero exit is never success: follow upstream's
repair contract — edit the connected neighbourhood, re-run with a fresh
`--out-dir` — and when repair is exhausted, report the failing gate instead
of the diagram.

Reply per `$ARCHIFY_SKILL` § Output: lead with a clickable Markdown link to
the HTML, add one or two sentences of takeaway when the subject is a real
codebase, and state anything that changes how the diagram should be read —
including the browser marker above when it applies. Never claim visual review
that did not happen.

## Refresh — `/diagram --refresh <candidate.json | diagram.html>`

Re-authors an existing committed candidate against the current `HEAD`. An
HTML path resolves to its sibling candidate (`<stem>.<type>.json`). Re-read
every cited source range at `HEAD`, update the components, their citations
and `meta.repository.revision`; a component whose cited source no longer
exists is removed or re-anchored from a fresh read of the source, and the
reply names what was dropped or merged. Then run Step 3's `finalize` again
with a fresh `--out-dir`.

This is the only regeneration path (D19): staleness is detected only here,
and `/wrap-up-session` leaves diagrams alone — regenerating committed
documents at wrap-up would rewrite them unasked.

## Edge cases

| Situation | Behaviour |
|---|---|
| tool absent under `$ARCHIFY_HOME` | the install command is printed and `/diagram` stops; no fallback renderer |
| `node` absent or older than 18 | stated with the `Node >= 18` requirement and stopped |
| no Chrome, Chromium or playwright-cli browser | non-browser gates run; the reply says *automated checks passed without browser evidence*; the diagram is still delivered |
| `finalize` exits non-zero | never success: upstream's repair contract, then the failing gate reported when repair is exhausted |
| dirty worktree on a codebase subject | the candidate pins `HEAD`; the reply names the changed paths; no uncommitted bytes are cited |
| `--refresh` and a cited component no longer exists | removed or re-anchored from a fresh read; the reply names what was dropped or merged |
| "a page", "an explainer", "a report" | not `/diagram` — route to `/html-presentation`; the explainer mode is not exposed (D5) |

## Integration

- **Installed by**: `install.sh` step 6c when Node >= 18 is present; otherwise
  the resolver's printed command is the only install path (Pi and Codex
  sessions never ran `install.sh`).
- **Pinned by**: the `archify` entry of `.github/upstreams.json`
  (`kind: installed`), reported by the weekly drift job and `/tidy`'s `tools`
  check; the resolver prints the install command for the same tag.
- **Offered by**: `/how` after every explanation and `/plan` after a
  multi-component spec; **produced by** `/system-design-planning` beside its
  architecture spec.
