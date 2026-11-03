---
implementation_paths:
  - src/**
---

# Fixture: a surface with an unsupported glob token

## Build Order

Sizing: 1 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | one | first | `src/[ab]/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
