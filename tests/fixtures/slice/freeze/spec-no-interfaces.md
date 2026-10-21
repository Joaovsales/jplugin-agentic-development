---
implementation_paths:
  - src/one/**
  - tests/one/**
  - tasks/**
---

# Fixture: the test freeze check

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/one/**`, `tests/one/**`, `tasks/**` | — | 1 | `bash tests/test-x.sh` | 2 files · 1 system · 1 AC |
