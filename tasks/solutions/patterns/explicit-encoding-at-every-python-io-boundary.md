---
title: "Pin an explicit encoding at every Python IO boundary, not only the reported one"
date: 2026-08-18
problem_type: pattern
module: ".agents/skills/html-presentation, .agents/skills/visual-recap, codex/hooks"
tags: [encoding, windows, cp1252, python, stdio, silent-failure]
applies_when: "Fixing or writing any Python script that reads stdin, writes stdout, or opens a file -- especially one that runs on Windows, or whose stream is piped or captured by a parent process"
---

## The pattern

Python's text layer picks its codec from the platform locale, not from UTF-8.
On Windows that is cp1252. Every place a script touches text without saying
`encoding=` is a separate instance of the same defect, and fixing the one that
was reported leaves the rest.

A single-site report is therefore a *class* report. Sweep every boundary in the
file and its immediate callers before calling the class closed.

## The five boundaries found in one sweep

One reported defect (stdin on the generator) turned out to be five. Four were
fixed here; the fifth was fixed independently and better in #66, which landed
on master while this work was in review:

| Site | Shape | Failure |
|------|-------|---------|
| `generate-presentation.py` stdin read | `sys.stdin.read()` | loud -- `UnicodeDecodeError`, or mojibake |
| same, both markdown branches | `decode("utf-8")` / `encoding="utf-8"` | **silent** -- a BOM defeats the H1 match, so title and every section vanish at exit 0 |
| `generate-presentation.py` path report | `print(os.path.abspath(...))` | loud or mojibaked -- *after* the artifact was written correctly |
| `visual-render.py` subprocess capture | `subprocess.run(..., text=True)` | **silent** -- the decode error is swallowed in subprocess's reader thread and `result.stderr` becomes `None`, exactly when the child's message is what you need |
| `codex/hooks/session_start.py` stdout (fixed in #66) | `print(json.dumps(...))` | loud, read as silent -- raises, so the hook emits nothing and the caller sees an empty envelope |

Two of the five fail **silently**, which is worse than the loud mojibake that
prompted the fix. Prefer `utf-8-sig` when decoding documents whose first
character is load-bearing: it is byte-identical to `utf-8` on BOM-free input, so
it costs nothing and defines the BOM failure out of existence.

## Reading vs writing

`sys.stdin.buffer` / `sys.stdout.buffer` are the raw layers and ignore the
locale. `sys.stdout.reconfigure(encoding="utf-8")` in `main()` is the smaller
diff when a script already uses `print()` in several places, and it keeps the
call sites readable.

## Testing the class

`PYTHONIOENCODING=cp1252` forces the hostile default on **every** platform, so a
regression pin works on Linux CI and not only on the Windows machine where the
bug was found. It reaches `sys.stdin` / `sys.stdout` (the `TextIOWrapper`s) and
**not** `sys.*.buffer`, which is precisely the asymmetry a byte-level fix relies
on.

Two traps, both hit while building the pin:

- **Assert that the variable took effect.** A pin whose hostile encoding stops
  being honoured passes against the broken code. One assertion on
  `sys.stdin.encoding` keeps the whole file from going vacuous.
- **Choose the fixture for the failure you claim to pin.** A box-drawing rule
  contains byte `0x90`, which is *undefined* in cp1252, so the broken code
  **aborts** rather than mangling -- a mojibake assertion built on that fixture
  can never fire. Exercising the mangling path needs input whose every byte is
  cp1252-decodable (`C3 AA`, `C3 A0`, `E2 80 94`).

`PYTHONIOENCODING` also has a wider blast radius than the stream under test: it
governs stdout too, so a script that prints a non-ASCII path can fail the test
for a reason unrelated to the fix.

## Related

- [[codex-session-start-hook-emits-nothing]] -- one instance, whose root cause
  stayed unestablished for four days because the symptom (empty stdout) is
  shared by an unrelated guard defect. Both are now fixed (#66, #68).
- [[ppid-is-1-on-windows-so-a-ppid-keyed-guard-collapses]] -- the guard half of
  that shared symptom, and a caution for this pattern: an encoding bug and a
  non-encoding bug can present identically as "the process emitted nothing", so
  confirming one does not clear the other. Fixing the encoding half alone left
  the test red.
- `../process/baseline-must-precede-tree-edits.md` -- the same sweep also showed
  that piping `tests/run.sh` into `tail` reports `tail`'s exit status, so a red
  suite reads as green. Read the `RESULT:` line, or run it unpiped.

## Recurrence — 2026-09-22

`slice.py ready` printed `intersects: a ↔ b` and died with `UnicodeEncodeError`
under `tests/run.sh`, which does not export `PYTHONUTF8`; the same command passed
from a shell that did. Fixed by `stream.reconfigure(encoding="utf-8")` on stdout
and stderr at entry (`.agents/skills/slice/scripts/slice.py`, `__main__`). A new
script that prints anything outside cp1252 must pin its stdio encoding itself
rather than rely on the caller's environment.
