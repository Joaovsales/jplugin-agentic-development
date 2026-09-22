#!/usr/bin/env python3
"""Replace, append, or point at the shared AGENTS.md managed block; migrate .claude/project.md once.

`/sync` overwrites everything between the managed-block markers wholesale on
every run, so text a project author wrote outside those markers must survive
byte-for-byte, in whichever line-ending convention the file already used.
This script is that primitive:

    python3 sync-managed-block.py --source <template AGENTS.md | -> \
        --target AGENTS.md [--claude-md CLAUDE.md] [--migrate .claude/project.md] [--dry-run]

`--migrate` moves the project's pre-single-file `.claude/project.md` content
below the end marker once and deletes the file (specs/single-instruction-file.md
§ Component contracts, D15): everything after the file's own header goes,
except the four generic sections the block now owns and the `### Task Tracking`
prose that explained where the pointer lived — the pointer line itself is moved,
and written first so the registry finds it in `AGENTS.md`.

Write order is fixed so an interrupted run duplicates and never loses:
`AGENTS.md` first (block and migrated text), then `CLAUDE.md`, then the
`project.md` delete last.

Stdlib only, Python 3.8+.
"""

from __future__ import annotations

import argparse
import os
import re
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

# The sections the managed block owns now; a copy in project.md is the
# template's old text, not the team's, and is dropped rather than moved.
GENERIC_HEADINGS = (
    "### Code Economy",
    "### Surgical Changes",
    "### Ambiguity Protocol",
    "### Large-Artifact Handoff",
)
TASK_TRACKING_HEADING = "### Task Tracking"
PROJECT_RULES_HEADING = "## Project-Specific Rules"
TARGETS_RE = re.compile(r"^## Deployment Targets[ \t]*$")
# Must agree with registry.config.POINTER_RE: the same line has to be found
# after the move by the reader that resolved it before.
POINTER_RE = re.compile(r"Task tracking instructions:\s*([^\s`<>]+)", re.IGNORECASE)


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


# --- migration ------------------------------------------------------------------


def unfenced_bare_lines(text: str) -> List[str]:
    """Bare lines outside ``` fences — a heading quoted in a code block is text."""
    result: List[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            result.append(line)
    return result


def outside_block_lines(text: str) -> List[str]:
    """Bare, unfenced lines of a target outside its managed block."""
    lines = text.splitlines(keepends=True)
    pair = locate_marker_pair("target", lines)
    if pair is None:
        return unfenced_bare_lines(text)
    begin_index, end_index = pair
    outside = "".join(lines[:begin_index]) + "".join(lines[end_index + 1 :])
    return unfenced_bare_lines(outside)


def strip_header(lines: List[str]) -> List[str]:
    """Drop project.md's own header: the `# ` title, the `> ` blockquote that
    describes the file, and the first `---` that closes it."""
    index = 0
    if index < len(lines) and lines[index].startswith("# "):
        index += 1
    while index < len(lines) and (lines[index].strip() == "" or lines[index].startswith(">")):
        index += 1
    if index < len(lines) and lines[index].strip() == "---":
        index += 1
    return lines[index:]


def is_heading(line: str) -> bool:
    return line.startswith("## ") or line.startswith("### ")


def split_sections(lines: List[str]) -> List[List[str]]:
    """Segments split at every `## `/`### ` heading outside a code fence; the
    first segment is the preamble and may be empty."""
    segments: List[List[str]] = [[]]
    in_fence = False
    for line in lines:
        if line.startswith("```"):
            in_fence = not in_fence
        elif not in_fence and is_heading(line):
            segments.append([])
        segments[-1].append(line)
    return segments


def trim_segment(lines: List[str]) -> List[str]:
    """Leading and trailing blank lines and `---` separators are layout between
    sections, not section text."""
    start, end = 0, len(lines)
    while start < end and lines[start].strip() in ("", "---"):
        start += 1
    while end > start and lines[end - 1].strip() in ("", "---"):
        end -= 1
    return lines[start:end]


def plan_migration(
    project_label: str, project_text: str, target_label: str, target_text: str
) -> List[List[str]]:
    """The chunks to append below the end marker, in order — the pointer line
    first, then each moved section. Raises ManagedBlockError when the move would
    put `## Deployment Targets` in two places."""
    target_lines = outside_block_lines(target_text)
    rules_heading_present = PROJECT_RULES_HEADING in target_lines
    targets_present = any(TARGETS_RE.match(line) for line in target_lines)

    body = strip_header([bare_line(line) for line in project_text.splitlines(keepends=True)])
    pointer: Optional[str] = None
    chunks: List[List[str]] = []
    for segment in split_sections(body):
        heading = segment[0] if segment and is_heading(segment[0]) else None
        if heading in GENERIC_HEADINGS:
            continue
        if heading == PROJECT_RULES_HEADING and rules_heading_present:
            continue
        if heading is not None and TARGETS_RE.match(heading) and targets_present:
            raise ManagedBlockError(
                f"{project_label}: '## Deployment Targets' is also below the end marker of "
                f"{target_label}; nothing moved — merge the two tables by hand, then re-run"
            )
        kept: List[str] = []
        for line in segment:
            if pointer is None and POINTER_RE.search(line):
                pointer = line.strip()
                continue
            kept.append(line)
        if heading == TASK_TRACKING_HEADING:
            continue  # the block documents the pointer's placement now
        kept = trim_segment(kept)
        if kept:
            chunks.append(kept)
    if pointer is not None:
        chunks.insert(0, [pointer])
    return chunks


def append_chunks(target_text: str, chunks: List[List[str]], newline: str) -> str:
    if not chunks:
        return target_text
    body = target_text
    if body and not body.endswith(("\n", "\r")):
        body += newline
    rendered = (newline + newline).join(newline.join(chunk) for chunk in chunks)
    return body + newline + rendered + newline


# --- CLI ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sync-managed-block",
        description="Replace, append, or point at the shared AGENTS.md managed block; migrate .claude/project.md once.",
    )
    parser.add_argument("--source", required=True, help="template AGENTS.md path, or - for stdin")
    parser.add_argument("--target", required=True, help="project AGENTS.md path")
    parser.add_argument("--claude-md", help="CLAUDE.md pointer file to write alongside the target")
    parser.add_argument("--migrate", metavar="PROJECT_MD",
                        help="pre-single-file project rules file to move below the end marker and delete")
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
        newline = detect_newline(existing_target)
        block_text = build_target_text(existing_target, block, newline, pair)
        new_target = block_text
        migrate_file = args.migrate if args.migrate and os.path.isfile(args.migrate) else None
        chunks: List[List[str]] = []
        if migrate_file is not None:
            chunks = plan_migration(migrate_file, read_text(migrate_file), args.target, block_text)
            new_target = append_chunks(block_text, chunks, newline)
    except ManagedBlockError as exc:
        print(f"sync-managed-block: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"sync-managed-block: {exc.filename}: {exc.strerror}", file=sys.stderr)
        return 2

    target_changed = new_target != existing_target
    block_changed = block_text != existing_target
    target_outcome = "unchanged"
    if block_changed:
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
    if args.migrate:
        if migrate_file is None:
            print(f"{prefix}migration: nothing to move")
        else:
            print(f"{prefix}migration: moved {len(chunks)} section(s), {args.migrate} deleted")

    if args.dry_run:
        return 0
    try:
        if target_changed:
            write_text(args.target, new_target)
        if args.claude_md and claude_outcome == "written":
            write_text(args.claude_md, "@AGENTS.md\n")
        if migrate_file is not None:
            os.remove(migrate_file)
    except OSError as exc:
        print(f"sync-managed-block: {exc.filename or args.target}: {exc.strerror}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
