# Build prompt template

`/slice` closes § Build Order with this fenced block, verbatim — the
planning session's last message, and the message a human pastes into a
fresh session to start `/build`. The template here and in `SKILL.md` must
stay byte-for-byte identical.

Everything in it is read off the spec and the plan block; nothing is asked.
The instruction lines are fixed text; `Constraints:` is the one free slot.

Build prompt:

```
Invoke `/build` for `specs/<feature>.md`.
Plan: `## Plan: <feature>` in `tasks/todo.md`, <N> slices, ready set <1, 2>.
Files: <implementation_paths, comma-separated>.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/<feature>.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: <one line per § Decisions row the builder must keep; omit the field when none>
```

`Files:` is `implementation_paths` verbatim, comma-separated. `ready set`
names the slices with no blocker, from § Build Order's `Blocked by` column.
`Constraints:` names, one line each, the § Decisions rows the builder must
keep that are not already implied by the plan block — omit the field
entirely when there are none.
