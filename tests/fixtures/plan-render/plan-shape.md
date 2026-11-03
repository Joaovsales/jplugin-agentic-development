# Spec: Plan-shaped decisions

## Problem

Archive uploads time out for large teams.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| D1 | Compression | gzip | user | Every reader supports it |
| D2 | Upload size cap | open | open | Needs the storage quota first |
| 3 | Retry policy | three tries with backoff | assumed | Matches the client library default |

## Acceptance Criteria

- AC1: Uploads over 1 GB are compressed.
- AC2: A failed upload retries three times.
