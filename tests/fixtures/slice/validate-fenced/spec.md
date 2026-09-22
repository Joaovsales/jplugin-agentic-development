---
implementation_paths:
  - src/one/**
  - src/two/**
  - tests/test-x.sh
---

# Fixture: a fenced example precedes the real Build Order

The spec's prose shows the grammar it asks for. The fenced block below is a
decoy: it carries the heading and a table whose surface is outside
`implementation_paths`, so a parser that reads the first `## Build Order` it
sees refuses a clean plan.

```markdown
## Build Order

Sizing: 1 slice. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | decoy | never read | `path/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
```

## Build Order

Sizing: 2 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first half | `src/one/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second half | `src/two/**`, `tests/test-x.sh` | — | 2 | `bash tests/test-x.sh` | 2 files · 1 system · 1 AC |
