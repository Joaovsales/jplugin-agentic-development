# Spec: Build Order cycle

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Exporter | CSV writer | `src/a/**` | 2 | 1 | `make test` | 2 files |
| 2 | Splitter | Part files | `src/b/**` | 1 | 2 | `make test` | 2 files |
