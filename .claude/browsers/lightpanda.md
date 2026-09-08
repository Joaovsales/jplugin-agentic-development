---
name: lightpanda
display_name: Lightpanda
fidelity: dom
detect_command: "command -v lightpanda"
mcp_command: "lightpanda mcp"
platforms: [linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64]
license: AGPL-3.0
pinned_release: "0.3.6"
---

# Lightpanda — DOM-tier e2e browser

> Adapter runbook for `/verify --scope e2e`. The frontmatter above is the
> machine-readable contract; this body is the human-readable operating notes.
> Optional: if lightpanda is absent, `/verify` falls through to the next tier and
> that is **not** an error.

[Lightpanda](https://github.com/lightpanda-io/browser) is a headless browser
written from scratch in Zig — libcurl for transport, html5ever for parsing, V8
for JavaScript, plus a CDP server and an MCP server. It exists to be driven by
agents rather than watched by people: roughly 9x faster and 16x lighter than
headless Chrome on the same pages.

This workflow uses it for exactly one job: **executing DOM-functional acceptance
criteria in unattended runs where no desktop Chrome exists** — `/yolo`,
unattended routine runs, cloud containers, CI. It is the third tier in `/verify --scope e2e`'s
resolution order, behind Chrome MCP and Playwright MCP.

---

## The capability ceiling — read this before trusting a PASS

Lightpanda has **no rendering path**. It builds a DOM and runs scripts against
it; it never lays the result out or paints it. Concretely, it does not support:

| Missing | Consequence |
|---|---|
| **screenshot** / PDF export | No visual artefact can be captured, so no visual regression check is possible |
| **Canvas** / WebGL | Charts, maps, drawn output, and anything on a canvas are invisible to it |
| Complete CSS layout — **Flexbox**/Grid are partial | An element can be reported present while being positioned wrongly or overlapping |
| **Service Worker**, Web Worker, WebRTC | Offline behaviour, background sync, and peer connections cannot be exercised |
| Full **WebSocket** support | Realtime and streaming features may behave differently or not connect |

The failure mode this creates is specific and worth naming: **a page with
completely broken layout can still expose a correct DOM.** An assertion that
"the submit button exists and has the right text" passes on a page where that
button is rendered off-screen, behind a modal, or invisible. Lightpanda cannot
tell those apart, and neither can a reviewer reading a bare PASS.

### Geometry is stubbed, not absent — this is the dangerous part

`getBoundingClientRect()` and `offsetWidth`/`offsetHeight` **exist and return
confident, plausible-looking numbers that are fiction.** Measured against 0.3.6
on a fixture whose button is styled `position:absolute; left:-9999px`:

```
submit-btn=[110,110,5,5]  total=[130,130,5,5]  checkout=[80,80,5,5]  h1=[65,65,5,5]
```

Every element reports `5x5`, and `x` always equals `y`. An `<h1>` and a
`<button>` are not both 5x5 pixels; the CSS offset is ignored entirely. The
values are synthetic.

A missing API throws, and a caller notices. A **stubbed** API silently returns
the wrong answer, so the defensive visual assertion a careful engineer would
write —

```js
const r = el.getBoundingClientRect();
if (r.width > 0 && r.x >= 0) { /* "it's visible" */ }
```

— **passes here for an element 9999px off the left edge.** That is why VISUAL
criteria are refused rather than attempted-and-checked: there is no runtime
signal to check against. The classifier has to decide before it runs, which is
why it fails closed.

That is why `/verify --scope e2e` classifies every AC before choosing a tier and
**fails closed** — an AC whose wording is ambiguous is treated as VISUAL and
refuses to run here. See `.agents/skills/verify/SKILL.md` § `--scope e2e`.

It is also why every `tasks/e2e-log.md` entry records the backend and its
fidelity. A PASS produced here is a narrower claim than a PASS from Chrome, and
the log has to say which one it was.

---

## Install

Upstream publishes binaries for Linux and macOS only. Pinned release: **0.3.6**.

```bash
brew install lightpanda-io/browser/lightpanda     # macOS / Linuxbrew
```

```bash
yay -S lightpanda-nightly-bin                     # Arch (AUR)
```

```bash
docker run --rm -p 9222:9222 lightpanda/browser:0.3.6
```

Direct download — substitute your architecture:

```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/0.3.6/lightpanda-x86_64-linux && chmod +x lightpanda
```

**Pin the release; do not track `nightly`.** Lightpanda is beta and moves fast.
An unattended run that silently changes browser behaviour between one night and
the next produces failures nobody can attribute. Bumping `pinned_release` in the
frontmatter above is a deliberate edit with a deliberate re-verification.

### Windows

**There is no Windows build.** Release 0.3.6 ships
`{aarch64,x86_64}-{linux,macos}` and two `.deb` packages — nothing else. On
Windows, run it under **WSL2** or **Docker** Desktop, or accept that
`/verify --scope e2e` will resolve to a different tier on that machine.

This is a real portability seam, not a rough edge: a repository whose sessions
alternate between a Windows box and a Linux box will take different verification
paths on each. The fidelity line in `tasks/e2e-log.md` is what makes that visible
after the fact.

---

## Registration

`install.sh` deliberately does **not** wire this up — it has never mutated MCP
configuration, and the right scope (user vs project) is the operator's call, not
the installer's. Register it yourself:

```bash
claude mcp add lightpanda -- lightpanda mcp
```

The server speaks MCP JSON-RPC 2.0 over stdio. For several agents against one
browser, run it over HTTP instead — each connection gets its own page, cookies,
and memory:

```bash
lightpanda mcp --port 9223
```

A CDP endpoint is also available (`lightpanda serve --host 127.0.0.1 --port
9222`) for Puppeteer/Playwright scripts, but this workflow does not use it. One
integration path is enough; two would mean two ways for the tier to be
misconfigured.

---

## Licensing

Lightpanda is **AGPL-3.0**. Use the **unmodified upstream** binary or Docker
image. Do not vendor it into this template, patch it, or redistribute a modified
build — the AGPL's network-use clause makes that a question for whoever ships the
result, and nothing here needs a fork to work.

---

## Troubleshooting

**`/verify` never selects lightpanda.** Resolution is ordered: Chrome MCP, then
Playwright MCP, then lightpanda. If a full-fidelity backend is present it wins,
by design — lightpanda is a fallback for environments without one, not a
preference.

**Every AC comes back BLOCKED.** The classifier decided they are all VISUAL. Read
the AC wording: layout, appearance, colour, responsiveness, screenshots, hover,
animation, and drag-and-drop all route to a full-fidelity browser. This is
working correctly; it is telling you these criteria need a real browser.

**A walkthrough fails on an unimplemented Web API.** Treat it as a step failure
and record which API in the evidence. Do not re-classify the AC as passing — the
gap is real, it is listed in the ceiling table above, and the feature genuinely
was not verified.

**The page loads but is empty.** Lightpanda respects `robots.txt` by default. Use
`--no-obey-robots` for a local dev server if the app serves a restrictive one.

**Upstream capability status.** Coverage improves steadily; the ceiling table
above reflects release 0.3.6. Track
[issue #1799](https://github.com/lightpanda-io/browser/issues/1799) for the
current missing-features list, and update this runbook in the same commit as any
`pinned_release` bump.
