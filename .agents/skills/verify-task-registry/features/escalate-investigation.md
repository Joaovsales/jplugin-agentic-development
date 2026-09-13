# Escalate an investigation

Users preview or apply an investigation hold when a routine cannot safely finish,
then confirm that later routine selection excludes the held parent.

## Sub-features

- `escalation-preview`: report the intended stages without writing.
- `escalation-apply`: add the configured hold and record the outcome.
- `escalation-readback`: reopen the task through the public CLI.
- `escalation-exclusion`: omit the held parent from later selection.

## How to get to it (user POV)

CLI entry: `escalate verify.sample` with a reason, reproduction state, timestamp,
command, observation, and either evidence references or an unavailable reason.
Omit `--apply` to preview. An applied escalation deliberately exits 1 so an
unattended fix routine cannot continue to a pull request.

## Driving it with script PTY

Preconditions: Doctor and record-task passed; verify.sample carries the bug label.

```bash
ESCALATION_ARGS=(
  escalate verify.sample
  --reason inconclusive
  --reproduction-state not-reproduced
  --run-at 2026-09-12T20:00:00-03:00
  --repro-command 'python3 -m pytest tests/missing.py'
  --observed 'The available checkout did not contain the reported test.'
  --evidence-unavailable 'The referenced fixture was absent from this checkout.'
)
drive escalation-before show verify.sample
drive escalation-preview "${ESCALATION_ARGS[@]}"
drive escalation-preview-readback show verify.sample
if rg -F 'needs-investigation' "$VERIFY_EVIDENCE/escalation-preview-readback.pty.txt"; then
  printf 'FAIL: escalation preview changed the task\n' >&2
  exit 1
fi
if drive escalation-apply "${ESCALATION_ARGS[@]}" --apply; then
  printf 'FAIL: applied escalation must terminate the routine non-zero\n' >&2
  exit 1
fi
test "$(cat "$VERIFY_EVIDENCE/escalation-apply.exit.txt")" -eq 1
rg -F 'hold: confirmed' "$VERIFY_EVIDENCE/escalation-apply.pty.txt"
drive escalation-held show verify.sample
rg -F 'needs-investigation' "$VERIFY_EVIDENCE/escalation-held.pty.txt"
drive escalation-select select --routine fix
rg -F 'candidate:     none' "$VERIFY_EVIDENCE/escalation-select.pty.txt"
```

Preserve every command/output/exit triple. The before/preview readback proves the
preview did not mutate task state; the applied readback and selection prove the
hold persisted and affects the next public CLI request.

## Gotchas

- Exit 1 is the successful terminal outcome for an applied escalation.
- This local recipe proves CLI persistence and selection behavior. It does not
  prove GitHub delivery, an agent skill choosing escalation, or PR suppression.
- Run this recipe before `routine-claim`, or use a fresh baseline task.
