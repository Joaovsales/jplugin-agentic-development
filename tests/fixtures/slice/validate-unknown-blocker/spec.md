---
implementation_paths:
  - src/one/**
  - src/two/**
---

# Fixture: a Blocked by number that names no slice

## Build Order

Sizing: 2 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first half | `src/one/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second half | `src/two/**` | 9 | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
