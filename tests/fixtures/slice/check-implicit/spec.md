---
implementation_paths:
  - src/feature/**
  - tests/test-feature.sh
---

# Fixture: a legacy spec with no Build Order is one implicit slice

## Behavior

Written before § Build Order existed. `check --slice 1` reads its surface from
`implementation_paths`.
