# Record a task

Users preview a new task, save it, and update the same stable identity without
creating a second task.

## Sub-features

- `record-preview`: default dry run creates no task.
- `record-create`: save title, summary, kind, label, and acceptance criterion.
- `record-update`: same ID updates persisted detail.
- `record-derived`: derive an ID from a source path.

## How to get to it (user POV)

Run the task-registry CLI `upsert` with a stable ID, or `--derive-id` and `--source`
(or `--spec`). Add `--apply` to save; omit it to preview. The `/task-registry`
agent invocation is a separate secondary entry point, not proved by direct CLI use.

## Driving it with script PTY

Preconditions: Launch and Doctor succeeded; scratch repository has no tasks.
Run in the same Bash session:

```bash
drive preview upsert verify.sample --title 'Verification task' --kind bug
 test ! -e "$VERIFY_REPO/tasks/details/verify.sample.md"
drive create upsert verify.sample --apply --title 'Verification task' --kind bug --label bug --summary 'Created through the CLI' --criterion 'Read back the saved task'
drive reopen show verify.sample
rg -F 'Created through the CLI' "$VERIFY_EVIDENCE/reopen.pty.txt"
rg -F 'Read back the saved task' "$VERIFY_EVIDENCE/reopen.pty.txt"
drive update upsert verify.sample --apply --title 'Verification task updated' --kind bug --label bug --summary 'Updated through the CLI'
drive updated show verify.sample
rg -F 'Verification task updated' "$VERIFY_EVIDENCE/updated.pty.txt"
rg -F 'Updated through the CLI' "$VERIFY_EVIDENCE/updated.pty.txt"
test "$(find "$VERIFY_REPO/tasks/details" -name '*.md' | wc -l)" -eq 1
```

For the separate derived-source and derived-spec entry points, run:

```bash
drive derived upsert --derive-id verify --source README.md --title 'Source follow-up' --kind task --apply
drive derived-read show verify.readme-md
rg -F 'task: verify.readme-md' "$VERIFY_EVIDENCE/derived-read.pty.txt"
rg -F 'Source follow-up' "$VERIFY_EVIDENCE/derived-read.pty.txt"
drive derived-spec upsert --derive-id verify --spec specs/check.md --title 'Spec follow-up' --kind task --apply
drive derived-spec-read show verify.specs-check-md
rg -F 'task: verify.specs-check-md' "$VERIFY_EVIDENCE/derived-spec-read.pty.txt"
rg -F 'Spec follow-up' "$VERIFY_EVIDENCE/derived-spec-read.pty.txt"
rg -F 'specs/check.md' "$VERIFY_EVIDENCE/derived-spec-read.pty.txt"
```

`show` exposes the derived ID and title, and the spec path for the spec variant.
It does not expose the task's source path; source-field read-back is outside this
CLI view's proof capability. Each alternative is NOT RUN unless its own commands
and read-back checks execute.

## Gotchas

- Run the one-record count before derived-ID recipes create extra records.
- `--dry-run` overrides `--apply`; neither preview output nor an index row proves persistence.
- Updates replace the supplied content; pass labels again when they must remain.
- Local `--apply` requires no external approval; this proves no GitHub write policy.
