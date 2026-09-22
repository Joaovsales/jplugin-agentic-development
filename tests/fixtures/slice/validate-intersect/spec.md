---
implementation_paths:
  - src/api/**
---

# Fixture: intersecting surfaces with no blocker

## Build Order

Sizing: 2 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | handlers | the handlers | `src/api/handlers/**` | — | 1 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
| 2 | routes | the router | `src/api/**` | — | 2 | `bash tests/test-x.sh` | 1 files · 1 system · 1 AC |
