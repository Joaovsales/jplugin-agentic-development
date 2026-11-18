#!/usr/bin/env python3
"""slice_outcome.py — the three results `/build` records at Slice Close
(specs/slice-three-outcomes.md).

    slice_outcome.py --agent <true|false|unknown> [-- <verification command...>]

`agent_result` is the sub-agent's claim, as the orchestrator read it from the
dispatch's return. `verification_result` is the exit status of the command
after `--`, which this script runs itself: there is no option that accepts a
verification result, so a sub-agent's quoted test output has no way in.
`slice_result` is derived from the two; only `True` closes a slice.

Each value is True, False or Unknown; Unknown means a check did not run, and
it is never shown as True. After the command's own output the script prints

    slice-outcome: agent_result=<v> verification_result=<v> slice_result=<v> <LABEL>
    slice-outcome: verification: `<command>` exited <n>
                 | not checked: verification — <reason>

The first line, minus its prefix, is the handover's `> Outcome:` line; its
`key=value` field names are the contract later readers parse.

Exit status: 0 SUCCEEDED; 1 VERIFICATION_FAILED or AGENT_FAILED (repair);
3 NOT_VERIFIED or AGENT_UNKNOWN (nothing to repair, re-run once the cause is
gone); 2 usage.
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from typing import List, Optional, Sequence, Tuple

TRUE, FALSE, UNKNOWN = "True", "False", "Unknown"
AGENT_VALUES = {"true": TRUE, "false": FALSE, "unknown": UNKNOWN}
# cached-suite.sh's "nothing ran" status; only its lock-refusal line makes 3 a
# refusal — its other `cached-suite:` notes come from runs that did happen.
REFUSAL_EXIT = 3
REFUSAL_PREFIX = "cached-suite: a suite is already running"
EXIT_FOR = {TRUE: 0, FALSE: 1, UNKNOWN: 3}


def run_verification(command: Sequence[str]) -> Tuple[str, str]:
    """Run the command, passing its output through; return (result, detail line)."""
    if not command:
        return UNKNOWN, "not checked: verification — no verification command was given"
    shown = " ".join(shlex.quote(part) for part in command)
    try:
        proc = subprocess.run(list(command), stderr=subprocess.PIPE, text=True)
    except OSError as exc:
        return FALSE, f"verification: `{shown}` could not start — {exc.strerror or exc}"
    sys.stderr.write(proc.stderr)
    sys.stdout.flush()
    sys.stderr.flush()
    refusal = _refusal_line(proc.stderr) if proc.returncode == REFUSAL_EXIT else None
    if refusal:
        return UNKNOWN, f"not checked: verification — {refusal}"
    result = TRUE if proc.returncode == 0 else FALSE
    return result, f"verification: `{shown}` exited {proc.returncode}"


def _refusal_line(stderr: str) -> Optional[str]:
    for line in stderr.splitlines():
        if line.startswith(REFUSAL_PREFIX):
            return line.strip()
    return None


def derive(agent: str, verification: str) -> Tuple[str, str]:
    """(slice_result, label): a failed run outranks everything, then a missing one."""
    if verification == FALSE:
        return FALSE, "VERIFICATION_FAILED"
    if verification == UNKNOWN:
        return UNKNOWN, "NOT_VERIFIED"
    if agent == FALSE:
        return FALSE, "AGENT_FAILED"
    if agent == UNKNOWN:
        return UNKNOWN, "AGENT_UNKNOWN"
    return TRUE, "SUCCEEDED"


def split_argv(argv: Sequence[str]) -> Tuple[List[str], List[str]]:
    argv = list(argv)
    if "--" in argv:
        cut = argv.index("--")
        return argv[:cut], argv[cut + 1:]
    return argv, []


def main(argv: Optional[Sequence[str]] = None) -> int:
    own, command = split_argv(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(
        prog="slice_outcome.py",
        allow_abbrev=False,
        description="Record a slice's agent, verification and slice results.",
    )
    parser.add_argument("--agent", required=True, choices=sorted(AGENT_VALUES))
    args = parser.parse_args(own)

    agent = AGENT_VALUES[args.agent]
    verification, detail = run_verification(command)
    slice_result, label = derive(agent, verification)
    print(
        f"slice-outcome: agent_result={agent} verification_result={verification} "
        f"slice_result={slice_result} {label}"
    )
    print(f"slice-outcome: {detail}")
    return EXIT_FOR[slice_result]


if __name__ == "__main__":
    sys.exit(main())
