# Spec: Risk value outside H/M/L

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | Store is slow | M | H | Cache reads | 1 |
| R2 | Disk fills | Often | H | Rotate files | 1 |
