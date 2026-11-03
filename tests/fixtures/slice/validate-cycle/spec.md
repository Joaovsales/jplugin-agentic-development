---
implementation_paths:
  - src/**
---

# Fixture: a cycle in Blocked by

## Build Order

Sizing: 3 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | a | a | `src/a/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | b | b | `src/b/**` | 3 | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 3 | c | c | `src/c/**` | 2 | 3 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
