# Spec: Question blocks an unknown slice

## Open questions

| ID | Question | Blocks | Needed from |
|---|---|---|---|
| Q1 | Which region hosts the bucket? | 9 | platform team |

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Exporter | CSV writer | `src/**` | — | 1 | `make test` | 2 files |
