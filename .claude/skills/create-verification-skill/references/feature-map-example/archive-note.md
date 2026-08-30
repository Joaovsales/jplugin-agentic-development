# Archive a note

Archive lets a user remove a note from the active list without deleting it and
restore the same note later from the archive.

## Sub-features

- `archive-browser` archives an open note from the browser.
- `archive-cli` archives a note by ID from the terminal.
- `archive-restore` restores an archived note to the active list.

## How to get to it (user POV)

- Open a note and choose `Archive` from its actions menu.
- Run `notes archive <id>` in a terminal.
- Open `Archived notes` and choose `Restore` for an archived note.

## Driving it with control-notes

Preconditions:

- Notes is healthy at `http://127.0.0.1:4173`.
- The disposable data directory contains `Quarterly plan` in the active list.
- `control-notes doctor` reports the expected URL and data directory.

- **Browser archive.** Open `Quarterly plan`, choose `Note actions`, then `Archive`. The active list no longer contains the note.
- **Confirm archive.** Open `Archived notes`. `Quarterly plan` is present with an `Archived` status.
- **Restore.** Choose `Restore`. The archive no longer contains the note and the active list does.
- **CLI entry.** Run `control-notes cli -- notes archive <id> --format json`. Exit code `0` and stdout identify the archived note.
- **Proof.** Capture `artifacts/archive/archive.aria.txt` and `artifacts/archive/active.aria.txt`; together they show the note moving between views.

## Gotchas

- Archive is reversible and must not be described or tested as deletion.
- A missing active-list row is insufficient proof; confirm the archived view.
- Restore the seeded note during fixture cleanup, but retain proof artifacts.
