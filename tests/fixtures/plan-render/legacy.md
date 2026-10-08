---
implementation_paths:
  - src/report/**
---

# Spec: Weekly report export

> Issue: none — written before visual plans had typed sections.

## Problem

Teams copy the weekly report by hand into a spreadsheet every Monday, and the copy drifts from the source within a week.

A second paragraph that the summary fallback must not pick.

## Behavior

The exporter reads the report store and writes one CSV per team.

```text
+-----------+      +-----------+      +---------+
| scheduler | ---> | exporter  | ---> | storage |
+-----------+      +-----------+      +---------+
```

```text
plain text that is not a diagram
```

1. Read the store.
2. Write the file.
   - Nested detail with `inline code` and **bold** and *italic*.

## Limits

| Setting | Default | Maximum | Notes | Owner | Review cadence | Applies to | Enforced by |
|---|---|---|---|---|---|---|---|
| rows per file | 10000 | 50000 | split beyond the maximum | data team | quarterly | every export | exporter |
| retention days | 30 | 365 | older files are deleted | platform | yearly | storage | lifecycle rule |

## Decisions

| Question | Decision | Why |
|---|---|---|
| File format | CSV | Every spreadsheet opens it |
| Schedule | Monday 06:00 UTC | Before the first stand-up |

## Acceptance Criteria

- The export writes one CSV per team.
- A file over 50000 rows is split into parts.

## References

- [Report store notes](docs/report-store.md)
