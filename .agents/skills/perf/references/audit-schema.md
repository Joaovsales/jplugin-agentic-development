# Audit schema — `perf-audit/1`

One JSON file per audit, `tasks/perf/<YYYY-MM-DD>-<slug>.json`.
`scripts/audit.py validate` enforces every rule below; `render` and `file` run
it first, so a report or a task never comes from an audit that fails it.

```json
{
  "schema": "perf-audit/1",
  "target": "<app or flow>", "date": "YYYY-MM-DD", "sha": "<short sha>",
  "inventory_source": "<verify skill | route table | README | none found>",
  "paths": [{
    "id": "<slug>", "name": "<human name>",
    "kind": "startup | flow | endpoint | job | web",
    "measurement": { "...": "measure.py output" },
    "expected": {"value": 5.0, "unit": "ms", "basis": "<one sentence>"},
    "source": "<likely source of the gap>",
    "lab": {"data": "lab", "backend": "<backend and version>",
            "lcp_ms": 0, "inp_ms": 0, "cls": 0.0, "long_tasks": 0, "bundle_bytes": 0}
  }],
  "findings": [{
    "title": "...", "path": "<path id>", "file": "<repo path>", "line": 1,
    "pattern": "<n-plus-one | sequential-await | await-waterfall | other>",
    "evidence": "<verbatim line>", "fix": "<suggested fix>",
    "impact": 1, "confidence": 75, "effort": 1
  }],
  "unverified": [{"file": "...", "line": 1, "reason": "..."}],
  "coverage_gaps": ["<path not measured, and what would reach it>"]
}
```

## Rules

- `schema` is `perf-audit/1`; `target`, `date` and `sha` are required.
- `paths` holds at least one critical path with a unique `id`, a `name` and a
  `kind` from `startup`, `flow`, `endpoint`, `job`, `web`.
- `measurement` is `measure.py run` or `summarize` output, unedited: at least
  5 samples, `runs` equal to their count, and `min`, `median`, `max` and
  `spread` matching them. A typed number is refused.
- `expected` has a positive `value` in the measurement's `unit` and a
  one-sentence `basis` (`references/estimate.md`).
- A `web` path has a `lab` block with `"data": "lab"`, numeric `lcp_ms`,
  `inp_ms` and `cls`, and the `backend` that produced them
  (`references/web-lab.md`).
- Each finding names an existing path, a `file` and positive `line` (checked
  against the tree with `--repo`), its verbatim `evidence`, a suggested `fix`,
  `impact` and `effort` on 1–3, and `confidence` 75 or 100. A candidate below
  75 belongs under `unverified` with its reason.
- `coverage_gaps` lists each path not measured and what would reach it.

## Derived values

- **gap** = measured median ÷ expected value.
- **score** = impact × confidence ÷ 100 ÷ effort; findings rank by score, then
  by their path's gap, then by `file:line`.
