---
implementation_paths:
  - src/one/**
  - src/two/**
  - tests/**
---

# Fixture: a TDD row whose test file is outside its slice's surface

## Build Order

Sizing: 2 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/one/**` | — | 1 | `bash tests/test-one.sh` | 1 files · 1 system · 1 AC |
| 2 | two | second | `src/two/**`, `tests/test-two.sh` | 1 | 2 | `bash tests/test-two.sh` | 2 files · 1 system · 1 AC |
