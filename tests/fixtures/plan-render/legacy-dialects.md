# Spec: Older spec dialects

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|---|---|---|---|---|---|
| D1 | Archive format | zip, tar | tar | A Windows consumer appears | settled (operator pick) |

## Acceptance Criteria

### AC-1 — the archive exists
- [ ] AC-1.1: The archive is written.
- [ ] AC-1.2: The archive is readable.
- AC-2 — The archive is signed.

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Archive | Writer and signer | `src/**` | — | 1–2 | `make test` | 2 files |
