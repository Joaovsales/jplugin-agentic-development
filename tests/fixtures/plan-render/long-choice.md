# Spec: Long chosen option

## Summary

A decision whose chosen option is a long sentence full of inline code must wrap inside its card on a phone.

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|---|---|---|---|---|---|
| D1 | Key store | `vault`, `kms` | Registered as `store-dev` under `tenant-0000` with `client-1111`, scope `Records.ReadWrite`, claims `email` and `upn`, group `sec-store-dev`, record in `docs/store-registration.md` | A second environment needs shared consent | settled |

## Acceptance Criteria

- AC1: The chosen option wraps at 390 px without page overflow.
