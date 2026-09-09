# Preserve external references across fallback

This feature covers an upsert that retains a published tracker reference while
an approval-gated external write is kept locally, then reuses that reference
when approval is available.

## Sub-features

- `fallback-preserves-reference`: local-pending persistence keeps the existing external link in the compact index.
- `approved-reuses-reference`: a later approved upsert resolves that link before provider metadata matching.

## How to get to it (user POV)

Run `upsert <task-id> --apply` against a configured external provider that
requires approval, then repeat with `--apply --approve`. The local verifier
cannot authenticate to or mutate an external tracker, so both paths require a
live provider driver or the focused mocked-provider regression.

## Driving it with the local verifier

The local provider recipe cannot prove this feature. Record both entry points as
`BLOCKED` unless a live external-provider driver is available. The supplemental
regression in `tests/test-task-registry.sh` proves the state transition with a
provider whose metadata listing is empty: the first write retains `github:42`,
and the approved second write fetches and updates that reference without a
create.

## Gotchas

- A local detail-file link is not evidence that an external task is absent.
- The index reference must be resolved before metadata-based provider matching;
  otherwise a task without registry metadata can be duplicated.
- The local provider cannot prove GitHub authorization, tracker concurrency, or
  live create/update behavior.
