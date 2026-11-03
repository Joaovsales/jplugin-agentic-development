---
implementation_paths:
  - src/one/**
  - src/two/**
---

# Fixture: ready set with an intersecting pair

## Build Order

Sizing: 3 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/one/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second | `src/two/**` | 1 | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 3 | three | third | `src/one/sub/**` | — | 3 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
