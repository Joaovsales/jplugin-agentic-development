#!/usr/bin/env python3
"""pr_linkage.py — a closing keyword binds to the ONE issue reference after it.

GitHub links a closing keyword (close/closes/closed, fix/fixes/fixed,
resolve/resolves/resolved) to the single issue reference that immediately
follows it, not to every reference in the list that trails it. A body of
`Closes #99, #100, #101` closes only #99 on merge; #100 and #101 stay open
and nothing reports it. The working form repeats the keyword per issue:
`Closes #99, closes #100, closes #101`.

`/wrap-up-session` runs this on the PR body before `gh pr create` and on the
body of an already-open PR during re-sync, so a keyword that reaches only the
first reference is caught before the merge rather than discovered after it.

Standard library only, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import List, Optional, Sequence

#: The keywords GitHub recognizes as closing keywords (matched case-insensitively).
CLOSING_KEYWORDS: Sequence[str] = (
    "close", "closes", "closed",
    "fix", "fixes", "fixed",
    "resolve", "resolves", "resolved",
)

#: Every reference form GitHub binds a keyword to: `#N`, `owner/repo#N`,
#: `GH-N`, or a full issue URL.
REF_PATTERN = (
    r"(?:https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/\d+"
    r"|(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#\d+"
    r"|GH-\d+)"
)

#: What may sit between two chained references without ending the list:
#: punctuation, whitespace (including a line break onto a bullet), and the
#: conjunctions people write in lists. Any other word ends the clause — prose
#: between two references makes the second one a sentence of its own.
_SEPARATOR = r"(?:[\s,;&/|+*-]|\band\b|\balso\b)+"

#: One clause: a keyword (an optional colon is tolerated), the reference bound
#: to it, and every reference chained afterward with no keyword of its own.
#: The trailing group is a single capture around a repeated non-capturing
#: alternation, so it holds the whole chained run rather than its last repetition.
CLOSING_CLAUSE_RE = re.compile(
    r"\b(?:" + "|".join(CLOSING_KEYWORDS) + r")\b\s*:?\s*" + REF_PATTERN
    + r"((?:" + _SEPARATOR + REF_PATTERN + r")*)",
    re.IGNORECASE,
)

#: Pulls individual references back out of a clause's chained tail.
REFERENCE_RE = re.compile(REF_PATTERN, re.IGNORECASE)

#: GitHub does not autolink inside code, so a quoted example such as
#: `` `Closes #A, #B` `` is not a linkage and must not read as one.
CODE_RE = re.compile(r"```.*?```|`[^`\n]*`", re.DOTALL)

#: `check` exit code when the body has references a closing keyword does not
#: reach. Deliberately not 1 (an uncaught exception) and not 2 (argparse's
#: usage error), so a caller reading the exit code cannot mistake a crash or a
#: typo'd flag for a finding — the same reasoning as routine_branch.py's
#: NOT_A_ROUTINE_BRANCH=3.
ORPHANED_REFERENCES = 3


def orphaned_references(body: str) -> List[str]:
    """References a closing keyword's clause chains to, but never binds.

    GitHub binds each closing keyword to the reference immediately after it.
    Every later reference in the same list is a plain mention unless it
    carries its own keyword, so it is returned here in the order it appears.
    """
    orphans: List[str] = []
    for match in CLOSING_CLAUSE_RE.finditer(CODE_RE.sub(" ", body)):
        orphans.extend(REFERENCE_RE.findall(match.group(1)))
    return orphans


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    check_cmd = sub.add_parser(
        "check", help="print every orphaned reference in a PR body, one per line"
    )
    check_cmd.add_argument(
        "--body-file",
        help="read the PR body from this path instead of stdin",
    )

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.body_file:
        with open(args.body_file, "r", encoding="utf-8") as handle:
            body = handle.read()
    else:
        body = sys.stdin.read()

    orphans = orphaned_references(body)
    for reference in orphans:
        print(reference)
    return ORPHANED_REFERENCES if orphans else 0


if __name__ == "__main__":
    sys.exit(main())
