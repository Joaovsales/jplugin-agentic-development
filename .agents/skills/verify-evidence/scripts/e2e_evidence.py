#!/usr/bin/env python3
"""e2e_evidence.py — a VISUAL PASS without its PNG on disk is not a PASS.

A VISUAL acceptance criterion is about what a person sees. `/verify-evidence
--scope e2e` saves a screenshot once the walkthrough reaches the state the AC
describes, and the `tasks/e2e-log.md` entry names it on a `Screenshot:` line.
`check` reads the log and refuses every VISUAL PASS whose line or file is
missing, so an unevidenced visual claim cannot reach a PR as a green one.

DOM-FUNCTIONAL entries pass on text assertions and BLOCKED entries were never
attempted, so neither owes a screenshot. `/wrap-up-session` § *E2E coverage*
runs this and treats a failing entry as an AC with no walkthrough.

Success is silent (exit 0). Each offending entry is one line on stderr (exit 1);
a missing log exits 2. Standard library only.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional, Sequence

DEFAULT_LOG = "tasks/e2e-log.md"

#: The trailing short-sha of a `## ` walkthrough heading.
SHA_RE = re.compile(r"\b([0-9a-f]{7,40})\s*$")
#: `### AC-2: text` names its AC; any other `### ` heading is its own label.
AC_RE = re.compile(r"^###\s+(AC-[\w.-]+)")
#: The first word of a result, with the bold markup the log sometimes carries.
RESULT_RE = re.compile(r"^\**\s*([A-Z]+)")


@dataclass
class Criterion:
    """One `### ` section of a walkthrough entry."""

    entry: str
    sha: Optional[str]
    label: str
    line: int
    lines: List[str] = field(default_factory=list)

    def value(self, key: str) -> Optional[str]:
        prefix = key + ":"
        found = [text[len(prefix):].strip() for text in self.lines if text.startswith(prefix)]
        return found[0] if found else None

    def is_visual_pass(self) -> bool:
        tier = self.value("Tier") or ""
        result = RESULT_RE.match(self.value("Result") or "")
        return tier.startswith("VISUAL") and bool(result) and result.group(1) == "PASS"


def criteria(text: str) -> Iterator[Criterion]:
    """Every `### ` section, tagged with the `## ` entry it sits under."""
    entry, sha, current = "", None, None
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if raw.startswith(("## ", "### ")) and current:
            yield current
            current = None
        if raw.startswith("## "):
            entry = raw[3:].strip()
            match = SHA_RE.search(entry)
            sha = match.group(1) if match else None
        elif raw.startswith("### "):
            match = AC_RE.match(raw)
            label = match.group(1) if match else raw[4:].strip()
            current = Criterion(entry, sha, label, number)
        elif current:
            current.lines.append(line)
    if current:
        yield current


def problem(criterion: Criterion, root: Path) -> Optional[str]:
    """Why this criterion's PASS is unevidenced, or None when it is not."""
    if not criterion.is_visual_pass():
        return None
    screenshot = criterion.value("Screenshot")
    if not screenshot:
        return "VISUAL PASS with no Screenshot: line"
    if not (root / screenshot).is_file():
        return f"screenshot {screenshot} is not on disk"
    return None


def check(log: Path, shas: Sequence[str], root: Path) -> int:
    if not log.is_file():
        print(f"e2e_evidence: {log} not found", file=sys.stderr)
        return 2
    failures = 0
    for criterion in criteria(log.read_text(encoding="utf-8")):
        if shas and criterion.sha not in shas:
            continue
        reason = problem(criterion, root)
        if reason:
            failures += 1
            print(f"{log}:{criterion.line}: {criterion.entry} — {criterion.label}: {reason}",
                  file=sys.stderr)
    return 1 if failures else 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("check", help="every VISUAL PASS has its PNG on disk")
    run.add_argument("--log", default=DEFAULT_LOG, help=f"the e2e log (default: {DEFAULT_LOG})")
    run.add_argument("--sha", action="append", default=[],
                     help="check only entries headed with this short-sha (repeatable)")
    args = parser.parse_args(argv)
    return check(Path(args.log), args.sha, Path.cwd())


if __name__ == "__main__":
    sys.exit(main())
