"""registry/globs.py — the shared `implementation_paths` glob matcher.

Extracted from `wrap-up-session/scripts/spec-reconcile.py`, which needed a way
to tell whether a changed path falls inside a spec's declared surface. `/slice`
needs the identical answer for a different question — whether a slice's surface
falls inside the spec's `implementation_paths`, and whether two slices' surfaces
overlap — so the matcher lives here once, and both callers import it rather than
keep two copies that could quietly drift.

Only three tokens are glob syntax: `*`, `?` and `**`. Everything else a pattern
contains is a literal, and anything resembling other glob dialects (`[]`, `{}`,
`!`) is rejected outright rather than silently treated as a literal that matches
nothing and quietly stops being maintained.
"""

from __future__ import annotations

import re
from typing import Iterator, List, Optional, Sequence

from .index import read_text

UNSUPPORTED_GLOB_CHARS = "[]{}!"

FRONTMATTER_KEY = "implementation_paths"


class SpecPathError(Exception):
    """A spec declares a path this program refuses to interpret.

    Always names the spec and the offending value: the whole point of failing
    loudly here is that the author can fix it without re-deriving which of forty
    specs was at fault.
    """


# ------------------------------------------------------- patterns and matching


def validate_pattern(pattern: str, spec: str) -> str:
    """Return `pattern` if this program will interpret it, else raise.

    Every rejection here is a value that would otherwise fail *silently*: an
    unsupported token matches nothing, so the spec is never selected and quietly
    stops being maintained. Refusing loudly is the only way the author finds out.
    """
    value = pattern.strip()
    if not value:
        raise SpecPathError(f"{spec}: empty implementation path")
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        raise SpecPathError(f"{spec}: absolute path not allowed: {value!r}")
    if "\\" in value:
        raise SpecPathError(f"{spec}: use POSIX separators, not backslashes: {value!r}")
    if ".." in value.split("/"):
        raise SpecPathError(f"{spec}: `..` traversal not allowed: {value!r}")
    bad = [c for c in UNSUPPORTED_GLOB_CHARS if c in value]
    if bad:
        raise SpecPathError(
            f"{spec}: unsupported glob syntax {''.join(bad)!r} in {value!r} "
            f"— only *, ? and ** are accepted"
        )
    return value


def _tokens(pattern: str) -> Iterator[str]:
    """Split a pattern into `**`, `*`, `?` and single literal characters."""
    index = 0
    while index < len(pattern):
        if pattern.startswith("**", index):
            yield "**"
            index += 2
        else:
            yield pattern[index]
            index += 1


_REGEX_FOR_TOKEN = {"**": ".*", "*": "[^/]*", "?": "[^/]"}
# `**` becomes two literal segments joined by `/` so it can still cross a
# directory boundary the way a real path would.
_LITERAL_FOR_TOKEN = {"**": "__d__/__d__", "*": "__s__", "?": "__c__"}


def _pattern_to_regex(pattern: str) -> str:
    """Translate the three supported tokens; everything else is a literal.

    Hand-written rather than `fnmatch`, whose `*` happily crosses `/` and whose
    `[seq]` syntax this format does not accept. Borrowing it would silently
    widen every declared surface.
    """
    return "".join(_REGEX_FOR_TOKEN.get(token, re.escape(token)) for token in _tokens(pattern))


def match_path(pattern: str, path: str) -> bool:
    """Case-sensitive whole-path match. A prefix is not a match."""
    return re.fullmatch(_pattern_to_regex(pattern), path) is not None


def _literalize(pattern: str) -> str:
    """Replace each glob token with a placeholder literal.

    Used by `patterns_intersect`: to ask whether pattern `a` overlaps pattern
    `b`, turn `b`'s wildcards into ordinary path characters and test the result
    against `a`'s matcher.
    """
    return "".join(_LITERAL_FOR_TOKEN.get(token, token) for token in _tokens(pattern))


def _segment_globs_intersect(x: str, y: str) -> bool:
    """Whether two single-segment globs (`*`, `?`, literals) share a string."""
    if x.startswith("*"):
        return _segment_globs_intersect(x[1:], y) or (bool(y) and _segment_globs_intersect(x, y[1:]))
    if y.startswith("*"):
        return _segment_globs_intersect(y, x)
    if not x or not y:
        return x == y
    if x[0] == "?" or y[0] == "?" or x[0] == y[0]:
        return _segment_globs_intersect(x[1:], y[1:])
    return False


def _segments_intersect(a: Sequence[str], b: Sequence[str]) -> bool:
    """Walk both segment lists; a `**` segment absorbs zero or more segments."""
    if not a and not b:
        return True
    if a and a[0] == "**":
        return _segments_intersect(a[1:], b) or (bool(b) and _segments_intersect(a, b[1:]))
    if b and b[0] == "**":
        return _segments_intersect(b, a)
    if not a or not b:
        return False
    return _segment_globs_intersect(a[0].replace("**", "*"), b[0].replace("**", "*")) and _segments_intersect(
        a[1:], b[1:]
    )


def patterns_intersect(a: str, b: str) -> bool:
    """Do these two surface patterns share at least one path?

    Decided segment by segment: a `**` segment absorbs any run of segments,
    and within a segment `*` and `?` intersect a literal wherever a string
    could satisfy both. Literalizing one side and matching it against the
    other (the earlier heuristic) missed `src/*/x.py` against `src/one/**`,
    so two colliding slices dispatched in parallel as if disjoint.
    """
    if a == b:
        return True
    return _segments_intersect(a.split("/"), b.split("/"))


def pattern_covered_by(pattern: str, allowed: Sequence[str]) -> bool:
    """Whether every path `pattern` could name also falls inside `allowed`.

    Used by `/slice` to check a slice's declared surface against the spec's
    `implementation_paths`: covered when `pattern` equals one of `allowed`
    outright, or when literalizing `pattern`'s own wildcards produces a path
    that one of `allowed`'s patterns matches.
    """
    if pattern in allowed:
        return True
    literal = _literalize(pattern)
    return any(match_path(candidate, literal) for candidate in allowed)


# ------------------------------------------------------------- spec metadata


def frontmatter_block(text: str, spec: str) -> Optional[List[str]]:
    """Return the frontmatter block's lines, or None when there is no block.

    An opened block that never closes is an error rather than "no frontmatter":
    treating it as absent would drop the spec to a legacy reader, which is the
    silent degradation this whole format exists to end.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return lines[1:index]
    raise SpecPathError(f"{spec}: frontmatter opened with `---` but never closed")


def parse_implementation_paths(block: Sequence[str], spec: str) -> Optional[List[str]]:
    """Read the `implementation_paths` list out of a frontmatter block."""
    entries: List[str] = []
    collecting = False
    for line in block:
        if re.match(rf"^{FRONTMATTER_KEY}\s*:", line):
            remainder = line.split(":", 1)[1].strip()
            if remainder:
                raise SpecPathError(
                    f"{spec}: {FRONTMATTER_KEY} must be a list, got scalar {remainder!r}"
                )
            collecting = True
            continue
        if collecting:
            item = re.match(r"^\s+-\s*(?P<value>.+?)\s*$", line)
            if item:
                entries.append(item.group("value").strip("\"'"))
                continue
            if line.strip():
                break
    if not collecting:
        return None
    if not entries:
        raise SpecPathError(f"{spec}: {FRONTMATTER_KEY} declares no paths")
    return entries


def read_implementation_paths(spec_path: str) -> List[str]:
    """Read and validate `implementation_paths` straight off a spec's frontmatter.

    `slice.py` needs this to check a slice's surface against the spec's declared
    paths; it never falls back to the legacy `## Files Likely Involved` prose
    reader — that fallback belongs to living-spec reconciliation, which tolerates
    an unmigrated spec. A slice plan has no such excuse.
    """
    block = frontmatter_block(read_text(spec_path), spec_path)
    if block is None:
        raise SpecPathError(f"{spec_path}: no frontmatter block found")
    paths = parse_implementation_paths(block, spec_path)
    if paths is None:
        raise SpecPathError(f"{spec_path}: no {FRONTMATTER_KEY} declared")
    return [validate_pattern(path, spec_path) for path in paths]
