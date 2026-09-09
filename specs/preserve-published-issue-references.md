# Preserve published issue references across local-pending upserts

## Behavior

When an upsert cannot publish to the configured external tracker because approval is required, it writes the task locally while retaining any external reference already recorded for that task. A later approved upsert uses that preserved reference to update the existing external task.

## Inputs

- A task index row with a stable task ID and an existing GitHub issue reference.
- An approval-gated external provider.
- One local-pending upsert followed by an approved upsert.

## Outputs

- The local detail file contains the task content.
- The compact index continues to render the original GitHub issue reference.
- The approved upsert updates the original issue instead of creating a duplicate.

## Edge Cases

- A task without a prior external reference receives the local detail-file reference.
- Local provider reads and writes continue to report local detail-file references when no external reference is being preserved.
- The preserved reference must survive both local create and local update operations.

## Acceptance Criteria

- A local-pending update of a GitHub-linked task keeps the original GitHub issue reference in the compact index.
- A later approved upsert updates the original issue instead of creating a second issue.
- Regression tests cover approval-gated fallback followed by approved publication.
