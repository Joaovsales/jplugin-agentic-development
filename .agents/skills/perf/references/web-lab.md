# Web lab trace

A web path is measured twice over: its load time as N runs through
`measure.py`, and a **lab trace** — LCP, INP, CLS, long tasks and the
JavaScript and CSS bytes — recorded in the audit's `lab` block. A lab trace is
one synthetic run on one machine; it is **lab data, never field data**, and
`audit.py validate` refuses a `lab` block whose `data` is anything but `"lab"`.

## Backend order

The same order `/verify-evidence` uses (`.agents/skills/verify-evidence/SKILL.md`
§ *Backend resolution*); first available wins, and a missing backend is never
an error — fall through:

1. **Playwright CLI** — `command -v playwright-cli`. A shell command, so every
   harness drives it the same way; the runbook is `.claude/browsers/playwright-cli.md`.
2. **Chrome DevTools** — the browser MCP tools exposed in the session; a
   DevTools performance trace (start trace, reload, stop trace) reports LCP,
   CLS and long tasks directly. MCP tools cost context on every turn they are
   loaded, so prefer the CLI when both exist.
3. **Lightpanda** is next in `/verify-evidence`'s order but renders no pixels, so it
   cannot produce a vital: skip it here.
4. **none** — the web path is a coverage gap naming the missing backend. Never
   substitute a non-browser number for a vital.

## Recipe with Playwright CLI

Open the page, install the observers, drive one real interaction, then read the
numbers. Repeat the whole recipe N ≥ 5 times and feed each metric's samples to
`measure.py summarize` when you need its spread; the `lab` block records the
median.

```bash
playwright-cli open http://127.0.0.1:8000/
playwright-cli eval "() => { window.__lab = {inp: 0, cls: 0, longTasks: 0}; const o = (type, fn, extra) => new PerformanceObserver(l => l.getEntries().forEach(fn)).observe({type, buffered: true, ...extra}); o('largest-contentful-paint', e => window.__lab.lcp = e.startTime); o('layout-shift', e => { if (!e.hadRecentInput) window.__lab.cls += e.value; }); o('longtask', () => window.__lab.longTasks += 1); o('event', e => { if (e.interactionId) window.__lab.inp = Math.max(window.__lab.inp, e.duration); }, {durationThreshold: 16}); return 'observing'; }"
playwright-cli click '<the page's main control>'
playwright-cli eval "() => { const bytes = performance.getEntriesByType('resource').filter(r => ['script', 'link', 'css'].includes(r.initiatorType)).reduce((n, r) => n + r.encodedBodySize, 0); return JSON.stringify({...window.__lab, bytes}); }"
playwright-cli close
```

- **LCP** is the last `largest-contentful-paint` entry's `startTime`.
- **INP** here is the longest scripted interaction's event duration — a lab
  stand-in for the field metric, which needs real users. Drive the page's main
  control; with no interaction there is no INP, and the path says so.
- **CLS** sums layout shifts without recent input.
- **Long tasks** counts main-thread tasks over 50 ms.
- **Bytes** sums the encoded JavaScript and CSS the page loaded.
- **Load time** — the path's `measurement` — is
  `performance.getEntriesByType('navigation')[0].loadEventEnd`, read in the same
  eval; the N runs' values go to `measure.py summarize --unit ms`.

The `lab` block names the backend and its version (`playwright-cli --version`).
