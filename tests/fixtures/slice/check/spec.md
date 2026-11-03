---
implementation_paths:
  - src/feature/**
  - tests/test-feature.sh
---

# Fixture: check a slice's diff against its declared surface

## Build Order

Sizing: 1 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | feature | the feature | `src/feature/**`, `tests/test-feature.sh` | — | 1 | `bash tests/test-feature.sh` | 2 files · 1 system · 1 AC |
