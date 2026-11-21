---
title: Print authoritative outcomes after every output producer
date: 2026-11-19
problem_type: bug
module: .agents/skills/build/scripts/slice_outcome.py
tags: [three-outcomes, stderr, argv, output-boundary]
symptoms: The last-summary parser chose a fake success from a multiline command argument or found no summary after partial stderr
root_cause: The diagnostic printed after the summary could contain literal newlines and the boundary guard observed stdout alone
resolution: Print the diagnostic before the final summary and append a newline after both replayed streams while preserving raw stderr bytes
---

PR #448's scoped re-review found two producers the first boundary repair
missed: `shlex.quote` preserves newlines in displayed arguments, and replayed
stderr may end without a newline. The child exit status stayed correct while
the recorded outcome became wrong or disappeared.

The final summary now follows the diagnostic
(`.agents/skills/build/scripts/slice_outcome.py:130`), and the newline follows
stderr replay and flush (`.agents/skills/build/scripts/slice_outcome.py:82`). Raw stderr remains unchanged;
the separator is written to stdout, which also works with merged streams.

Prevention: exercise the documented line-prefix parser on the complete captured
output, including diagnostic arguments and both streams.
`tests/test-slice-outcome.sh:103` covers multiline argv, partial text stderr
and byte 0xff; the six new failure assertions were red before the repair.
