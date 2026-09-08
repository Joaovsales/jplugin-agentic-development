# Choose routine work

Users inspect the selector vocabulary, find work for a routine, identify a task's
workflow, and claim it so it is excluded from subsequent selection.

## Sub-features

- `routine-selectors`: inspect configured selectors.
- `routine-select`: find a candidate for `fix`.
- `routine-workflow`: describe the selected task's skill chain.
- `routine-claim`: label a task in progress and exclude it from selection.

## How to get to it (user POV)

CLI entries: `selectors`, `select --routine fix`, `workflow verify.sample`, and
`claim verify.sample --routine fix` (preview, or `--apply` to persist).
Producer routines `janitor` and `architect` do not consume a selected issue.
The scheduled routine and agent skill chain are separate entry points requiring
an actual harness session; invoking `workflow` does not execute that chain.

## Driving it with script PTY

Preconditions: Doctor and record-task passed; verify.sample carries the bug label.

```bash
drive selectors selectors
drive select select --routine fix
rg -F 'verify.sample' "$VERIFY_EVIDENCE/select.pty.txt"
drive workflow workflow verify.sample
if drive claim-preview claim verify.sample --routine fix; then
  printf 'FAIL: local claim preview behavior changed; reconcile the map\n' >&2
  exit 1
fi
test "$(cat "$VERIFY_EVIDENCE/claim-preview.exit.txt")" -eq 1
rg -F 'dry-run is the default, pass --apply' "$VERIFY_EVIDENCE/claim-preview.pty.txt"
drive before-claim show verify.sample
drive claim claim verify.sample --routine fix --apply
drive claimed show verify.sample
rg -F 'in-progress' "$VERIFY_EVIDENCE/claimed.pty.txt"
drive select-after select --routine fix
rg -F 'candidate:     none' "$VERIFY_EVIDENCE/select-after.pty.txt"
```

Inspect selectors for `fix` / `bug`; workflow must identify `fix` and its skill
chain. Confirm before-claim has no in-progress label, proving preview did not
persist it. Preserve each command/output/exit triple. A local claim demonstrates
stored selection state, not cross-process atomicity or GitHub race prevention.

## Gotchas

- Selection depends on labels, not title wording; keep bug on the update command.
- Local claim preview currently refuses with exit 1; capture that outcome separately.
- Missing selectors, partial provider reads, and an empty pool are distinct results.
- Do not interpret successful workflow output as proof that build, review, or PR creation ran.
