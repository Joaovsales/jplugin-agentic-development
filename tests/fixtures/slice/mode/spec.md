---
implementation_paths:
  - src/one/**
  - src/two/**
---

# Fixture: mode derived from § Interfaces

## Interfaces

### `one` module

- **Path:** `src/one/mod.py`
- **Hides:** a detail.
- **Interface:** `one()`.
- **Alternative considered:** none.
- **Depth:** deep.

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/one/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second | `src/two/**` | — | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
