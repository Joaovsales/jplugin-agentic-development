---
implementation_paths:
  - src/one/**
  - src/two/**
  - src/three/**
  - src/four/**
---

# Fixture: ready set with a blocked slice, a direct and a transitive dependent, and an independent slice

## Build Order

Sizing: 4 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/one/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second | `src/two/**` | 1 | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 3 | three | third | `src/three/**` | 2 | 3 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 4 | four | fourth | `src/four/**` | — | 4 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
