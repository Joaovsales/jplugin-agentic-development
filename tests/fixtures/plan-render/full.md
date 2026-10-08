---
implementation_paths:
  - src/export/**
  - src/split/**
  - tests/**
---

# Spec: Team report export

> Issue: generic fixture — every visual plan component appears once.

## Summary

The exporter turns the weekly report store into one CSV per team every Monday at 06:00 UTC. Files over 50000 rows are split so spreadsheets can open them. Nothing is exported for a team with no rows.

```flow
caption: Weekly export path
Scheduler -> Exporter (new) : Monday 06:00
Exporter -> Store : read rows
Exporter -> Splitter (changed) : over 50000 rows
Splitter --> Bucket : part files
```

## Behavior

The exporter reads every team's rows, writes `team-<id>.csv`, and hands files over 50000 rows to the splitter.

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|---|---|---|---|---|---|
| D1 | File format | CSV, JSON lines | CSV | A consumer needs nested fields | settled |
| D2 | Split threshold | 50000 rows, 100 MB | 50000 rows | Rows grow past 2 KB each | open |
| D3 | Empty teams | skip, write a header-only file | skip | An auditor needs proof of an empty week | settled |

## Acceptance Criteria

- AC1: The exporter writes one CSV per team with a header row.
- AC2: A file over 50000 rows is split into parts of at most 50000 rows.
- AC3: A team with no rows produces no file.
- AC4: Export failures name the team and exit non-zero.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | The store times out under the Monday load | M | H | Read in pages of 5000 rows | 1 |
| R2 | The bucket quota is exceeded | L | H |  | 2 |
| R3 | A column rename breaks old readers | H | M | Pin the header order in a test | 1 |
| R4 | Clock skew delays the run | L | L | Schedule from UTC only | 1 |

## Open questions

| ID | Question | Blocks | Needed from |
|---|---|---|---|
| Q1 | Which bucket region holds part files? | 2 | platform team |
| Q2 | Should the CSV carry a BOM for older spreadsheets? | none | data team |

## Constraints

| Constraint | Value | Source |
|---|---|---|
| Maximum rows per file | 50000 | user |
| Export window | 06:00–06:30 UTC | inferred |

## System design

```sequence
caption: Export of one team
participant Scheduler
Scheduler -> Exporter : run(team)
Exporter -> Store : rows(team)
alt rows over 50000
Exporter -> Splitter : split(rows)
Splitter --> Exporter : parts
else rows within 50000
Exporter -> Bucket : put(file)
end
Exporter --> Scheduler : done
```

```text
+-----------+     +----------+
| scheduler | --> | exporter |
+-----------+     +----------+
```

## Component contracts

### Exporter (NEW)

```text
export(team_id: str, rows: Iterable[Row]) -> list[Path]
```

Raises `ExportError(team_id)` on any write failure.

### Splitter (changed)

```text
split(rows: Iterable[Row], limit: int = 50000) -> list[Part]
```

## Data models

### Row

| Field | Type | Notes |
|---|---|---|
| team_id | str | stable team key |
| week | date | ISO week start |
| value | decimal | two decimal places |

## Build Order

Sizing: 3 slices. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Exporter | One CSV per team with a header row | `src/export/**`, `tests/test_export.py` | — | 1, 4 | `pytest tests/test_export.py` | 3 files · 1 system · 2 ACs |
| 2 | Splitter | Part files for large teams | `src/split/**`, `tests/test_split.py` | 1 | 2 | `pytest tests/test_split.py` | 2 files · 1 system · 1 AC |
| 3 | Scheduling | Monday 06:00 UTC trigger | `src/export/schedule.py` | 1 | — | `pytest tests/test_schedule.py` | 1 file · 1 system · 0 ACs |

Build prompt:

```
Invoke `/build` for `specs/full.md`.
Plan: `## Plan: full` in `tasks/todo.md`, 3 slices, ready set 1.
Constraints: CSV only; split at 50000 rows; quote "values" & <escape> them.
```

## References

- [Store notes](docs/store.md)
- [Bucket policy](https://example.com/bucket-policy)
