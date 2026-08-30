# Create a note

Create note lets a user save a titled note from the browser or CLI, cancel an
unfinished draft, and confirm the saved note from a second user-facing view.

## Sub-features

- `create-open` opens a blank editor from each browser entry point.
- `create-save` persists a title and body.
- `create-cancel` discards an unfinished browser draft.
- `create-cli` creates the same note shape from the terminal.

## How to get to it (user POV)

- Choose the `New note` button in the browser toolbar.
- Press `n` in the browser while focus is outside an editable field.
- Run `notes create --title <title> --body <body>` in a terminal.

## Driving it with control-notes

Preconditions:

- Notes is healthy at `http://127.0.0.1:4173`.
- No note is titled `Release checklist`.
- `control-notes doctor` reports the expected URL and disposable data directory.

- **Open editor.** Run `control-notes browser click --role button --name "New note"`. A form named `Note editor` appears with focus in `Title`.
- **Enter content.** Fill `Title` with `Release checklist` and `Body` with `Tag and publish`. The `Save note` button becomes enabled.
- **Save note.** Choose `Save note`. A status named `Note saved` appears and the heading reads `Release checklist`.
- **Confirm persistence.** Return to `All notes` and reopen `Release checklist`. Both saved values appear.
- **Cancel draft.** Open a new note, enter `Discard me`, and choose `Cancel`. The list has no `Discard me` link.
- **CLI entry.** Run `control-notes cli -- notes create --title "CLI note" --body "Created from terminal" --format json`. Exit code `0` and stdout contain the new ID and title.
- **Proof.** Run `control-notes browser snapshot --aria --path artifacts/create-note/list.aria.txt` and `control-notes browser screenshot --path artifacts/create-note/list.png`. Both saved notes appear.

## Gotchas

- Pressing `n` while a textbox has focus types the character instead of opening an editor.
- Titles are trimmed on save. Assert the rendered title, not the draft value.
- A save status alone is insufficient proof. Reopen the note from the list.
- Remove created notes during fixture cleanup, but retain proof artifacts.
