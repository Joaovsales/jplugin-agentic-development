# Search notes

Search lets a user find notes by title or body text, inspect a matching note,
and distinguish no matches from an unavailable search.

## Sub-features

- `search-open` opens search from each supported browser entry point.
- `search-match` returns title and body matches without changing note data.
- `search-open-result` opens a result in the note editor.
- `search-empty` shows a complete empty state for a query with no matches.
- `search-clear` removes the query and restores the recent-notes view.
- `search-cli` returns the same matching notes from the terminal.

## How to get to it (user POV)

- Choose the `Search` button in the browser toolbar.
- Press `/` in the browser while focus is outside an editable field.
- Run `notes search <query>` in a terminal.

## Driving it with control-notes

Preconditions:

- Notes is healthy at `http://127.0.0.1:4173`.
- The disposable data directory contains `Quarterly plan` with body `Draft budget`.
- `control-notes doctor` reports the expected URL and data directory.

- **Toolbar entry.** Choose `Search`. A dialog named `Search notes` appears with focus in its searchbox.
- **Keyboard entry.** Close the dialog, focus the page, and press `/`. The same dialog appears without inserting a slash.
- **Title match.** Enter `quarterly`. Results contain `Quarterly plan` but not `Grocery list`.
- **Body match.** Replace the query with `budget`. `Quarterly plan` remains with a body-match excerpt.
- **Open result.** Choose `Quarterly plan`. The dialog closes and the editor heading matches.
- **Empty state.** Search for `volcano`. A status named `No matching notes` appears after completion.
- **Clear query.** Choose `Clear search`. The query empties and `Recent notes` replaces results.
- **CLI match.** Run `control-notes cli -- notes search "quarterly" --format json`. Exit code `0` and stdout contain one matching object.
- **CLI miss.** Run the same command with `volcano`. Exit code `0` and stdout are `[]`.
- **Proof.** Capture `artifacts/search/results.aria.txt` and `artifacts/search/results.png`; both identify Notes, the query, and `Quarterly plan`.

## Gotchas

- Pressing `/` while an editor or searchbox has focus inserts text.
- Results update after a debounce. Wait for results or empty status, not a fixed sleep.
- Archived notes require `Include archived`.
- Use `--format json` for stable CLI assertions.
- Opening a result changes browser state; reopen search before proving another query.
