#!/usr/bin/env python3
"""spec-reconcile.py — the deterministic half of living-spec reconciliation.

`/wrap-up-session` keeps `specs/` describing what the code actually does. That
job splits cleanly in two, and only one half belongs in a script:

  * **Discovery** — which specs *might* be affected? That is change-set
    collection, glob matching, and metadata validation: mechanical, and wrong in
    a way nobody notices if left to an agent's judgement. It lives here.
  * **Reconciliation** — did the behavior a candidate describes actually change?
    That is reading the diff, the callers, and the tests. No script can do it,
    and a keyword heuristic pretending to would quietly rewrite correct specs.
    It lives in `SKILL.md`.

So this program answers exactly one question — "which specs must a human or an
agent now look at, and why?" — and deliberately refuses to answer whether any of
them should change.

Standard library only, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

# Only these three tokens are glob syntax. Everything else a pattern contains is
# a literal, and anything resembling other glob dialects is rejected outright
# rather than silently treated as a literal -- a spec claiming `src/[ab]/**`
# would otherwise match nothing and go quietly unmaintained forever.
UNSUPPORTED_GLOB_CHARS = "[]{}!"

FRONTMATTER_KEY = "implementation_paths"
LEGACY_HEADING = "## Files Likely Involved"


class SpecPathError(Exception):
    """A spec declares a path this program refuses to interpret.

    Always names the spec and the offending value: the whole point of failing
    loudly here is that the author can fix it without re-deriving which of forty
    specs was at fault.
    """


@dataclass(frozen=True)
class Change:
    """One changed path, as git reported it.

    `old_path` is set only for a rename or a copy. Both endpoints matter: the
    spec that documents the *old* location is the one most in need of
    reconciliation, and it is the one a new-path-only change set would miss.
    """

    status: str
    path: str
    old_path: Optional[str] = None
    origin: str = ""

    def match_targets(self) -> Tuple[str, ...]:
        """Every path this change should be matched against."""
        if self.old_path:
            return (self.path, self.old_path)
        return (self.path,)


@dataclass(frozen=True)
class Candidate:
    """A spec the change set selected, with every reason it was selected."""

    spec: str
    reasons: Tuple[str, ...]
    source: str


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


def _pattern_to_regex(pattern: str) -> str:
    """Translate the three supported tokens; everything else is a literal.

    Hand-written rather than `fnmatch`, whose `*` happily crosses `/` and whose
    `[seq]` syntax this format does not accept. Borrowing it would silently
    widen every declared surface.
    """
    out: List[str] = []
    index = 0
    while index < len(pattern):
        if pattern.startswith("**", index):
            out.append(".*")
            index += 2
        elif pattern[index] == "*":
            out.append("[^/]*")
            index += 1
        elif pattern[index] == "?":
            out.append("[^/]")
            index += 1
        else:
            out.append(re.escape(pattern[index]))
            index += 1
    return "".join(out)


def match_path(pattern: str, path: str) -> bool:
    """Case-sensitive whole-path match. A prefix is not a match."""
    return re.fullmatch(_pattern_to_regex(pattern), path) is not None


# ------------------------------------------------------------- spec metadata


def _read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def _frontmatter_lines(text: str, spec: str) -> Optional[List[str]]:
    """Return the frontmatter block's lines, or None when there is no block.

    An opened block that never closes is an error rather than "no frontmatter":
    treating it as absent would drop the spec to the legacy reader, which is the
    silent degradation this whole format exists to end.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return lines[1:index]
    raise SpecPathError(f"{spec}: frontmatter opened with `---` but never closed")


def _parse_implementation_paths(block: Sequence[str], spec: str) -> Optional[List[str]]:
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


def _legacy_paths(text: str) -> List[str]:
    """Parse repository-relative paths out of `## Files Likely Involved`.

    Compatibility only, and deliberately lenient where the metadata reader is
    strict. This section is **prose**: it backticks type names and identifiers
    alongside paths, and `Dict[str, int]` is not a malformed path — it was never
    a path. Validating every backticked token the way declared metadata is
    validated would hard-fail wrap-up on legacy specs that are perfectly fine.

    So a token is kept only if it *is* a usable pattern, and anything else is
    passed over. Nothing is swallowed: this is a heuristic reading unstructured
    prose, and "not a path" is its answer, not a suppressed error. A spec that
    wants a guarantee declares `implementation_paths`, where a bad value is loud.
    """
    section = re.search(
        rf"^{re.escape(LEGACY_HEADING)}\s*$(?P<body>.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not section:
        return []
    kept: List[str] = []
    for match in re.finditer(r"`([^`]+)`", section.group("body")):
        token = match.group(1).strip()
        # Prose names a directory as `src/`, but matching is a whole-path
        # `fullmatch`, and no file path ends in a slash -- so the token would be
        # kept, look like a declaration, and select nothing. Reading it as "this
        # directory's contents" is what the prose meant.
        if token.endswith("/"):
            token += "**"
        try:
            kept.append(validate_pattern(token, ""))
        except SpecPathError:
            continue
    return kept


def spec_patterns(spec_file: str, spec_path: str) -> Tuple[List[str], str]:
    """Return this spec's declared paths and which reader supplied them.

    Explicit metadata wins outright. A spec carrying both is mid-migration, and
    consulting the legacy section as well would resurrect the stale half of it.
    """
    text = _read(spec_file)
    block = _frontmatter_lines(text, spec_path)
    declared = _parse_implementation_paths(block, spec_path) if block is not None else None
    if declared is not None:
        return [validate_pattern(p, spec_path) for p in declared], "frontmatter"
    legacy = _legacy_paths(text)
    if legacy:
        return legacy, "legacy"
    return [], "none"


# --------------------------------------------------------------------- git I/O


def _git(repo: str, *args: str) -> str:
    """Run git in `repo` and return stdout, or raise with git's own message."""
    result = subprocess.run(
        ("git", "-C", repo) + args,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise SpecPathError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def parse_name_status(stream: str, origin: str) -> List[Change]:
    """Parse git's NUL-delimited `--name-status -z` output.

    `-z` rather than the default because git quotes any path holding a space or
    a non-ASCII byte, and a quoted path matches no pattern -- so the spec
    documenting that file would never be selected, silently.
    """
    fields = [f for f in stream.split("\0") if f != ""]
    changes: List[Change] = []
    index = 0
    while index < len(fields):
        status = fields[index]
        letter = status[0]
        # R and C carry a similarity score (`R100`) and two paths; the rest have one.
        wanted = 2 if letter in ("R", "C") else 1
        if index + wanted >= len(fields):
            # A truncated stream used to fall through to the single-path branch,
            # which read a rename's OLD path as its new one -- a wrong change set
            # that looks exactly like a right one. There is no correct reading of
            # a half-record, so say so instead of inventing one.
            raise SpecPathError(
                f"git --name-status -z ({origin}) ended mid-record: {status!r} needs "
                f"{wanted} path(s), {len(fields) - index - 1} remain"
            )
        if wanted == 2:
            changes.append(Change(letter, fields[index + 2], fields[index + 1], origin))
        else:
            changes.append(Change(letter, fields[index + 1], None, origin))
        index += wanted + 1
    return changes


def collect_changeset(repo: str, base: str) -> List[Change]:
    """Capture committed, staged, and unstaged changes as one snapshot.

    Taken once, before reconciliation writes anything. A change set re-derived
    afterwards would contain wrap-up's own spec edits, and the step could then
    select itself.
    """
    if base.startswith("-"):
        # `{base}...HEAD` is one argv element, but git reads a leading `-` as an
        # option regardless of position. Rejecting it here keeps a revision name
        # from turning into a flag on the way to the subprocess.
        raise SpecPathError(f"--base must name a revision, got option-like {base!r}")
    sources = (
        ("committed", ("diff", "--name-status", "-z", "-M", "-C", f"{base}...HEAD")),
        ("staged", ("diff", "--name-status", "-z", "-M", "-C", "--cached")),
        ("unstaged", ("diff", "--name-status", "-z", "-M", "-C")),
    )
    changes: List[Change] = []
    for origin, args in sources:
        # quotePath=false keeps unicode paths raw; -z already removes the rest.
        changes.extend(parse_name_status(_git(repo, "-c", "core.quotePath=false", *args), origin))
    return _dedupe_changes(changes)


def _dedupe_changes(changes: Sequence[Change]) -> List[Change]:
    """One entry per (status, path, old_path); the earliest origin wins."""
    seen: Dict[Tuple[str, str, Optional[str]], Change] = {}
    for change in changes:
        seen.setdefault((change.status, change.path, change.old_path), change)
    return list(seen.values())


# ------------------------------------------------------------------- discovery


#: A spec carrying one of these in its `status:` frontmatter key is no longer a
#: contract for current behaviour, and reconciling it would reintroduce as
#: "current" a description the project already retired.
RETIRED_STATUSES = ("superseded", "completed", "archived", "withdrawn")
SUPERSEDED_RE = re.compile(r"^>\s*Superseded by:", re.MULTILINE)


def is_retired(text: str) -> bool:
    """Whether this spec has been withdrawn as a description of current behaviour.

    Two markers, because two conventions already exist in the wild: a `status:`
    frontmatter key, and a `> Superseded by:` admonition at the top of the body.
    Either one is a statement that the document no longer describes what the code
    does, and a step whose whole premise is "specs describe current behaviour"
    must not be updating one of them to match today's diff.

    Read leniently on purpose: this decides whether to *skip* work, so a spec that
    says nothing is treated as live.
    """
    if SUPERSEDED_RE.search(text):
        return True
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return False
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip().strip("\"'").lower() in RETIRED_STATUSES
    return False


def _spec_files(repo: str, spec_dir: str) -> List[str]:
    """Every spec in the tree, repository-relative, README excluded."""
    root = os.path.join(repo, spec_dir)
    found: List[str] = []
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if not filename.endswith(".md") or filename == "README.md":
                continue
            absolute = os.path.join(directory, filename)
            found.append(os.path.relpath(absolute, repo).replace(os.sep, "/"))
    return sorted(found)


def session_spec(repo: str, spec_dir: str) -> Optional[str]:
    """The spec named by the newest `## Plan:` block's `> Spec:` line.

    Exact parse, never inference. A plan block carrying no association yields
    None, and wrap-up then discovers by path alone — guessing a spec from a
    similar filename is the one shortcut this association exists to remove.
    """
    todo = os.path.join(repo, "tasks", "todo.md")
    if not os.path.isfile(todo):
        return None
    text = _read(todo)
    # Anchored on the heading rather than split on "\n## Plan:", which misses a
    # block starting at line 1 -- and a missed block returns the same None as a
    # plan that genuinely named no spec.
    starts = [m.start() for m in re.finditer(r"^## Plan:", text, re.MULTILINE)]
    if not starts:
        return None
    match = re.search(rf"^>\s*Spec:\s*(?P<path>{re.escape(spec_dir)}/\S+\.md)\s*$",
                      text[starts[-1]:], re.MULTILINE)
    if match is None:
        return None
    named = match.group("path")
    if not os.path.isfile(os.path.join(repo, named)):
        # The plan block asserts this spec is the session's contract. Returning
        # None here would be indistinguishable from a plan that named nothing,
        # so the spec most certain to need reconciling is the one silently
        # dropped -- typically right after a rename, when it is least accurate.
        raise SpecPathError(
            f"tasks/todo.md: plan block names `{named}`, which does not exist. "
            "Fix the `> Spec:` line or restore the file."
        )
    return named


def _match_reasons(change: Change, patterns: Sequence[str]) -> List[str]:
    """Why this change selected a spec — one reason per matching endpoint."""
    reasons = []
    for target in change.match_targets():
        if any(match_path(pattern, target) for pattern in patterns):
            moved = f" from {change.old_path}" if change.old_path else ""
            reasons.append(f"{target} ({change.status}{moved}, {change.origin})")
    return reasons


def discover(repo: str, base: str, spec_dir: str) -> Tuple[List[Change], List[Candidate]]:
    """Select every spec the change set touches, in deterministic order.

    Paths inside the spec directory are excluded from matching. Reconciliation
    writes specs, so letting spec files select specs would let the step select
    its own output and never settle.
    """
    changes = collect_changeset(repo, base)
    relevant = [c for c in changes if not c.path.startswith(f"{spec_dir}/")]
    named = session_spec(repo, spec_dir)
    candidates: List[Candidate] = []
    for spec in _spec_files(repo, spec_dir):
        if spec != named and is_retired(_read(os.path.join(repo, spec))):
            continue
        patterns, source = spec_patterns(os.path.join(repo, spec), spec)
        reasons = [r for change in relevant for r in _match_reasons(change, patterns)]
        if spec == named:
            reasons.insert(0, "session-spec (named by the completed plan block)")
            source = source if patterns else "session-spec"
        if reasons:
            candidates.append(Candidate(spec, tuple(dict.fromkeys(reasons)), source))
    return changes, candidates


# ------------------------------------------------------------------- rendering


def _changeset_payload(changes: Sequence[Change]) -> List[Dict[str, Optional[str]]]:
    return [
        {
            "status": c.status,
            "path": c.path,
            "old_path": c.old_path,
            "origin": c.origin,
        }
        for c in changes
    ]


def _render_changeset(changes: Sequence[Change]) -> str:
    if not changes:
        return "Change set: empty — nothing changed this session."
    lines = [f"Change set: {len(changes)} paths"]
    for change in sorted(changes, key=lambda c: c.path):
        moved = f" (from {change.old_path})" if change.old_path else ""
        lines.append(f"  {change.status} {change.path}{moved} [{change.origin}]")
    return "\n".join(lines)


def _render_candidates(changes: Sequence[Change], candidates: Sequence[Candidate]) -> str:
    """Bounded by construction: one line per candidate plus its reasons.

    No candidates is a success and stays one line — an internal-only session is
    the common case, and a step that shouts on the quiet path gets ignored on the
    loud one.
    """
    header = f"Spec reconciliation: {len(candidates)} candidates from {len(changes)} changed paths"
    lines = [header]
    for candidate in candidates:
        lines.append(f"  {candidate.spec} [{candidate.source}]")
        lines.extend(f"    - {reason}" for reason in candidate.reasons)
    return "\n".join(lines)


def _candidate_payload(candidates: Sequence[Candidate]) -> List[Dict[str, object]]:
    """Include ready-to-use `selected-by:` lines, not just raw reasons.

    A deferred candidate becomes a `--evidence` argument to `task-registry
    upsert`, and the string's shape is owned here. Emitting only the raw reason
    would leave `SKILL.md` instructing an agent to retype a format this module
    defines — so a change here would silently desynchronize prose nothing tests.
    """
    return [
        {
            "spec": c.spec,
            "source": c.source,
            "reasons": list(c.reasons),
            "evidence": [f"selected-by: {reason}" for reason in c.reasons],
        }
        for c in candidates
    ]


# --------------------------------------------------------------------- the CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="spec-reconcile",
        description="Deterministic candidate discovery for living-spec reconciliation.",
    )
    parser.add_argument("command", choices=("changeset", "discover"))
    parser.add_argument("--repo", default=".", help="project root (default: cwd)")
    parser.add_argument("--base", required=True, help="base branch to diff against")
    parser.add_argument("--spec-dir", default="specs", help="spec directory (default: specs)")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    repo = os.path.abspath(args.repo)
    if not os.path.isdir(repo):
        print(f"spec-reconcile: no such directory: {args.repo}", file=sys.stderr)
        return 2
    try:
        if args.command == "changeset":
            changes = collect_changeset(repo, args.base)
            payload = {"changeset": _changeset_payload(changes)}
            text = _render_changeset(changes)
        else:
            changes, candidates = discover(repo, args.base, args.spec_dir.rstrip("/"))
            payload = {
                "changeset": _changeset_payload(changes),
                "candidates": _candidate_payload(candidates),
            }
            text = _render_candidates(changes, candidates)
    except SpecPathError as exc:
        print(f"spec-reconcile: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(payload, indent=2) if args.json else text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
