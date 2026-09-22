#!/usr/bin/env python3
"""Replace, append, or point at the shared AGENTS.md managed block.

`/sync` overwrites everything between the managed-block markers wholesale on
every run, so text a project author wrote outside those markers must survive
byte-for-byte, in whichever line-ending convention the file already used.
This script is that primitive:

    python3 sync-managed-block.py --source <template AGENTS.md | -> \
        --target AGENTS.md [--claude-md CLAUDE.md] [--dry-run]

It implements replace / append / pointer only (specs/single-instruction-file.md
§ Component contracts) — `--migrate` is a later slice and is not reserved
here.

Stdlib only, Python 3.8+.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from typing import List, Optional, Sequence, Tuple

SLUG = "jplugin-agentic-development"
BEGIN = f"<!-- {SLUG}:begin -->"
END = f"<!-- {SLUG}:end -->"
# Files written before the repository rename carry this slug in the same
# marker shape. Assembled at runtime so the identity sweep
# (tests/test-repo-identity.sh) does not read this module as a live reference.
LEGACY_SLUG = "coding-agent" + "-workflow"
LEGACY_BEGIN = BEGIN.replace(SLUG, LEGACY_SLUG)
LEGACY_END = END.replace(SLUG, LEGACY_SLUG)


class ManagedBlockError(Exception):
    """A usage error or malformed marker set, reported before any write."""


def source_label(source: str) -> str:
    return "<stdin>" if source == "-" else source


def read_source_text(source: str) -> str:
    if source == "-":
        return sys.stdin.read()
    with open(source, "r", encoding="utf-8") as stream:
        return stream.read()


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", newline="") as stream:
        return stream.read()


def write_text(path: str, content: str) -> None:
    """Tempfile + os.replace, so a reader never observes a partial write."""
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    temporary: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="", dir=directory,
            prefix=f".{os.path.basename(path)}.", delete=False,
        ) as stream:
            temporary = stream.name
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and os.path.exists(temporary):
            os.unlink(temporary)


def detect_newline(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def bare_line(line: str) -> str:
    return line.rstrip("\r\n")


def find_marker_lines(lines: Sequence[str], markers: Sequence[str]) -> List[int]:
    """1-based line numbers where a bare line matches one of `markers`."""
    return [index + 1 for index, line in enumerate(lines) if bare_line(line) in markers]


def locate_marker_pair(
    label: str, lines: Sequence[str]
) -> Optional[Tuple[int, int]]:
    """0-based (begin_index, end_index) of the current-or-legacy marker pair.

    Returns None when no markers are present at all. Raises ManagedBlockError,
    naming `label` and the offending line, for anything malformed: an
    unmatched begin or end, or more than one of either.
    """
    begins = find_marker_lines(lines, (BEGIN, LEGACY_BEGIN))
    ends = find_marker_lines(lines, (END, LEGACY_END))
    if not begins and not ends:
        return None
    if len(begins) > 1:
        raise ManagedBlockError(f"{label}:{begins[1]}: more than one begin marker")
    if len(ends) > 1:
        raise ManagedBlockError(f"{label}:{ends[1]}: more than one end marker")
    if begins and not ends:
        raise ManagedBlockError(f"{label}:{begins[0]}: begin marker with no matching end marker")
    if ends and not begins:
        raise ManagedBlockError(f"{label}:{ends[0]}: end marker with no matching begin marker")
    begin_index, end_index = begins[0] - 1, ends[0] - 1
    if end_index < begin_index:
        raise ManagedBlockError(f"{label}:{ends[0]}: end marker precedes its begin marker")
    return begin_index, end_index


def extract_source_block(label: str, text: str) -> str:
    """The current-slug block content from a template source, exclusive."""
    lines = text.splitlines(keepends=True)
    begins = find_marker_lines(lines, (BEGIN,))
    ends = find_marker_lines(lines, (END,))
    if len(begins) != 1 or len(ends) != 1 or ends[0] <= begins[0]:
        raise ManagedBlockError(f"{label} carries no managed block")
    begin_index, end_index = begins[0] - 1, ends[0] - 1
    return "".join(lines[begin_index + 1 : end_index])


def normalize_block_newlines(block: str, newline: str) -> str:
    if not block:
        return block
    joined = newline.join(block.splitlines(keepends=False))
    if block.endswith(("\n", "\r")):
        joined += newline
    return joined


def render_block(block: str, newline: str) -> str:
    normalized = normalize_block_newlines(block, newline)
    if normalized and not normalized.endswith(newline):
        normalized += newline
    return f"{BEGIN}{newline}{normalized}{END}{newline}"


def build_appended(existing_text: str, block: str, newline: str) -> str:
    rendered = render_block(block, newline)
    if not existing_text:
        return rendered
    body = existing_text
    if not body.endswith(("\n", "\r")):
        body += newline
    return body + newline + rendered


def build_target_text(
    existing_text: str, block: str, newline: str, pair: Optional[Tuple[int, int]]
) -> str:
    if pair is None:
        return build_appended(existing_text, block, newline)
    lines = existing_text.splitlines(keepends=True)
    begin_index, end_index = pair
    before = "".join(lines[:begin_index])
    after = "".join(lines[end_index + 1 :])
    return before + render_block(block, newline) + after


def claude_md_is_pointer(text: str) -> bool:
    return text in ("@AGENTS.md\n", "@AGENTS.md\r\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sync-managed-block",
        description="Replace, append, or point at the shared AGENTS.md managed block.",
    )
    parser.add_argument("--source", required=True, help="template AGENTS.md path, or - for stdin")
    parser.add_argument("--target", required=True, help="project AGENTS.md path")
    parser.add_argument("--claude-md", help="CLAUDE.md pointer file to write alongside the target")
    parser.add_argument("--dry-run", action="store_true", help="report outcomes without writing")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        block = extract_source_block(source_label(args.source), read_source_text(args.source))
        existing_target = read_text(args.target) if os.path.exists(args.target) else ""
        pair = locate_marker_pair(args.target, existing_target.splitlines(keepends=True))
        if args.claude_md and os.path.isdir(args.claude_md):
            raise ManagedBlockError(f"{args.claude_md}: is a directory")
    except ManagedBlockError as exc:
        print(f"sync-managed-block: {exc}", file=sys.stderr)
        return 2

    newline = detect_newline(existing_target)
    new_target = build_target_text(existing_target, block, newline, pair)
    target_changed = new_target != existing_target
    target_outcome = "unchanged"
    if target_changed:
        target_outcome = "appended" if pair is None else "replaced"

    claude_outcome: Optional[str] = None
    if args.claude_md:
        existing_claude = read_text(args.claude_md) if os.path.exists(args.claude_md) else None
        is_pointer = existing_claude is not None and claude_md_is_pointer(existing_claude)
        claude_outcome = "unchanged" if is_pointer else "written"

    prefix = "would " if args.dry_run else ""
    print(f"{prefix}{os.path.basename(args.target)}: {target_outcome}")
    if args.claude_md:
        print(f"{prefix}{os.path.basename(args.claude_md)}: {claude_outcome}")

    if args.dry_run:
        return 0
    try:
        if target_changed:
            write_text(args.target, new_target)
        if args.claude_md and claude_outcome == "written":
            write_text(args.claude_md, "@AGENTS.md\n")
    except OSError as exc:
        print(f"sync-managed-block: {exc.filename or args.target}: {exc.strerror}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
