# Gate integrity in /build

A slice must not pass by weakening the checks that judge it
(contract: `specs/gate-integrity.md`). `/build` runs
`.agents/skills/quality-gate/scripts/gate-integrity.py` twice per slice: once
before dispatch to record what the checks looked like, once at Slice Close to
compare against that record.

## Before dispatch — the gate base

Before each dispatch (once per parallel batch), record the **gate base** tree id:

```bash
python3 .agents/skills/quality-gate/scripts/gate-integrity.py --snapshot
```

Slice Close judges against it, never an earlier slice's edits — an earlier
slice's Surface-declared change to a protected file is already in the gate base,
so the next slice is not blamed for it. If `--snapshot` fails, record
`gate integrity: not checked — <reason>` and resolve it before dispatching.

## At Slice Close

```bash
python3 .agents/skills/quality-gate/scripts/gate-integrity.py --base <gate-base> --spec <spec> --slice <n>
```

It hashes every protected file against the dispatch gate base, never the session
base SHA. A parallel batch is checked after central integration against its gate
base and the union of its Surfaces, passing `--slice` once per slice.

| Exit | Meaning | What /build does |
|------|---------|------------------|
| 0 | clean, or only `GATE_CHANGED` / weakening findings | record the finding lines on the `> Surface:` line |
| 1 | `GATE_TAMPERED` — a protected file changed outside the Surface | stop the slice: the header stays `[ ]`, the handover records `unfinished: GATE_TAMPERED <paths>` |
| 3 | the check could not run in full | `gate integrity: not checked — <reason>` on the `> Surface:` line, never as clean |

The finding lines it prints on any exit go on the `> Surface:` line too.

The cumulative check over the whole change is `/quality-gate` Phase 0 against
the merge-base.
