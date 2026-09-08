# Read task detail

Users open a task by stable ID or local Markdown reference and see its stored detail.

## Sub-features

- `read-id`: resolve a stable task ID.
- `read-path`: resolve a local task file reference.
- `read-missing`: report an unknown task explicitly.

## How to get to it (user POV)

Run `show verify.sample` or `show tasks/details/verify.sample.md` with the public
CLI. GitHub issue shorthand and URL entry points require the GitHub provider and
are BLOCKED in this isolated local run.

## Driving it with script PTY

Preconditions: Doctor and the record-task minimum walkthrough passed.

```bash
drive read-id show verify.sample
drive read-path show tasks/details/verify.sample.md
rg -F 'Updated through the CLI' "$VERIFY_EVIDENCE/read-id.pty.txt"
rg -F 'Updated through the CLI' "$VERIFY_EVIDENCE/read-path.pty.txt"
if drive read-missing show verify.absent; then
  printf 'FAIL: missing task unexpectedly succeeded\n' >&2
  exit 1
fi
test "$(cat "$VERIFY_EVIDENCE/read-missing.exit.txt")" -eq 1
```

Inspect read-missing.pty.txt: it must name the missing reference and explain that
it cannot be resolved, rather than crashing. Each `show` is a new process reading
persisted state, not a cached view from the create command.

## Gotchas

- An unrelated malformed index row may appear as a diagnostic; do not hide it.
- A missing record and unavailable external provider are different outcomes.
