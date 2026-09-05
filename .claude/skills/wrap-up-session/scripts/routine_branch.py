#!/usr/bin/env python3
"""routine_branch.py — the branch name is the routine's only channel to wrap-up.

A routine selects an issue, does the work, and ends at a pull request that
`/wrap-up-session` opens. Wrap-up runs in a later context and cannot know which
issue the session addressed, so the routine encodes both facts where every
harness preserves them: the branch name, under a reserved namespace.

    routine/<name>/<issue-number>-<slug>

The `routine/` namespace is load-bearing. Anchoring on bare routine names looks
tempting and is wrong: `feature/2024-refactor` correctly fails to match, but
`fix/2024-refactor` *matches* and yields issue 2024 — a human branch that never
opted in, silently linked to an unrelated issue. No human branch starts with
`routine/`.

Reader and writer ship together. A serialization with only a parser in-tree has
no round-trip test, and the failure it hides is invisible: a routine emitting
`routine/plan/90_slug` parses to None, wrap-up opens a ready PR where the
contract requires a draft, and nothing anywhere errors.

The parser is general over the routine name on purpose, so the deferred `build`
routine (specs/category-routines.md, issue #98) round-trips today and arrives
later as a contract change rather than a regex change.

Standard library only, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Optional, Sequence, Tuple

#: Anchored on the namespace, general over the name. The trailing `.` is what
#: makes the slug mandatory: `routine/fix/90` must not parse, because a branch
#: with no slug is indistinguishable from a truncated one.
ROUTINE_BRANCH_RE = re.compile(r"^routine/([a-z][a-z-]*)/(\d+)-.")

#: The routine names the contract defines, including the deferred `build`
#: (specs/category-routines.md, issue #98). The formatter checks MEMBERSHIP
#: against this, not merely shape: `format_routine_branch("plna", ...)` passes any
#: plausible regex and yields `routine/plna/90-x`, a branch that parses perfectly,
#: that no scheduler owns, and that wrap-up reads as "not plan" — so a plan
#: proposal opens as a READY pull request. Shape cannot catch a typo; a list can.
#: Callers adding a routine pass `known=` rather than editing this.
CONTRACT_ROUTINES: Tuple[str, ...] = ("plan", "fix", "improve", "build")

#: Git imposes no practical branch-length limit, but tooling and terminals do.
#: Truncating here keeps the formatter total over any title a tracker can hold.
MAX_BRANCH_LENGTH = 100

#: Used when a title has no ASCII alphanumerics to slugify. The issue number
#: is what identifies the branch; the slug is for humans reading `git branch`.
FALLBACK_SLUG = "work"
#: `parse` exit code for "this branch is outside the routine/ namespace".
#: Deliberately not 1: that is also an uncaught exception, and the two must
#: not be indistinguishable to a shell caller.
NOT_A_ROUTINE_BRANCH = 3


def parse_routine_branch(branch: str) -> Optional[Tuple[str, int]]:
    """`(routine, issue)` for a routine branch, or None for anything else.

    None is the ordinary answer, not an error. Any branch outside the namespace
    means "this session is not a routine", and wrap-up behaves exactly as it
    always has — which is what makes the convention opt-in by shape.
    """
    match = ROUTINE_BRANCH_RE.match(branch or "")
    if match is None:
        return None
    return match.group(1), int(match.group(2))


def format_routine_branch(
    routine: str, issue: int, slug: str, known: Sequence[str] = CONTRACT_ROUTINES
) -> str:
    """The branch a routine creates, guaranteed to parse back to its inputs.

    Exactly two things can go wrong, and only one of them is worth an exception:

    * **A name no routine owns** — `"plna"` — cannot be caught downstream. The
      branch parses, so nothing errors; wrap-up simply sees a routine that is not
      `plan` and opens a ready PR where the contract requires a draft. Raising is
      the only place this is visible, so it raises.
    * **A slug that normalizes to nothing** — a CJK or emoji-only issue title —
      is cosmetic. The issue number is what identifies the branch, and halting a
      routine at step 3 over decoration would be a worse failure than a dull
      name, so this is defined out of existence with a fallback.

    The final round-trip assertion is the actual contract, checked rather than
    argued: whatever this returns, `parse_routine_branch` reads back as the
    inputs it was given.
    """
    if routine not in known:
        raise ValueError(
            f"routine name {routine!r} is not one of the contract's routines "
            f"({', '.join(known)}) — the branch would parse but no routine owns it"
        )
    if issue < 1:
        raise ValueError(f"issue number {issue!r} is not a positive integer")
    prefix = f"routine/{routine}/{issue}-"
    slugged = _slugify(slug) or FALLBACK_SLUG
    branch = prefix + slugged[: max(1, MAX_BRANCH_LENGTH - len(prefix))].rstrip("-")
    if parse_routine_branch(branch) != (routine, issue):
        raise ValueError(f"refusing to emit {branch!r} — it does not parse back to its inputs")
    return branch


def _slugify(text: str) -> str:
    """Lowercase, hyphen-joined, ASCII-alphanumeric. Anything else is a separator."""
    return re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    parse_cmd = sub.add_parser("parse", help="print '<routine> <issue>' for a routine branch")
    parse_cmd.add_argument("branch")

    format_cmd = sub.add_parser("format", help="print the branch name for a routine and issue")
    format_cmd.add_argument("routine")
    format_cmd.add_argument("issue", type=int)
    format_cmd.add_argument("slug")

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "parse":
        parsed = parse_routine_branch(args.branch)
        if parsed is None:
            # Silent, and a code of its own. "Not a routine branch" is the common,
            # ordinary case -- but 1 is also what Python returns for an uncaught
            # exception, so a caller that read 1 as "outside the namespace" would
            # read a crashed interpreter the same way and silently open a PR with
            # no `Closes #N`. 3 cannot be produced by a traceback.
            return NOT_A_ROUTINE_BRANCH
        print(f"{parsed[0]} {parsed[1]}")
        return 0
    try:
        print(format_routine_branch(args.routine, args.issue, args.slug))
    except ValueError as exc:
        print(f"routine_branch: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
