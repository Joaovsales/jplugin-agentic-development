#!/usr/bin/env python3
"""gate-integrity.py — did this change edit the checks that judge it?

A slice can pass by weakening its own gate: one line in the expected-failures
list makes a failing suite pass. This script compares every protected file —
test runners, the expected-failures list, CI workflows, lint and test configs —
against its blob at a base commit or tree by content hash: the git blob id of
the raw working-tree bytes, computed here, against the blob id `git ls-tree`
records. No diff output is read and no git filter runs, so an
`assume-unchanged` bit, an edit committed after the base, a
`diff.mnemonicPrefix` setting and a clean filter all leave the answer
unchanged (specs/gate-integrity.md).

    gate-integrity.py --base <rev> [--spec <spec> [--slice <n>]...] [--repo <dir>]
    gate-integrity.py --snapshot [--repo <dir>]

`--snapshot` prints the tree id of the working tree as it stands, so a caller
can judge one slice against the state it started from.

Exit 1 when a protected file changed outside the Surface (GATE_TAMPERED);
otherwise 3 when the check could not run in full (not checked); otherwise 0,
findings or not. 2 is bad usage.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import os
import re
import stat
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Dict, FrozenSet, List, Optional, Sequence, Tuple, Union

_SCRIPTS = os.path.dirname(os.path.abspath(__file__))
for _relative in (("..", "..", "task-registry", "scripts"), ("..", "..", "slice", "scripts")):
    _path = os.path.normpath(os.path.join(_SCRIPTS, *_relative))
    if _path not in sys.path:
        sys.path.insert(0, _path)

import slice as slice_py  # noqa: E402  (path must be set up first)
from registry.globs import SpecPathError, match_path, pattern_covered_by, validate_pattern  # noqa: E402

END_MARKER = "<!-- jplugin-agentic-development:end -->"
AGENTS = "AGENTS.md"
LINK_MODE = "120000"
GITLINK_MODE = "160000"
MAX_LINK_HOPS = 40
PROTECTED_KEY = "Protected paths:"
EXPECTED_FAILURES_KEY = "Expected failures:"

DEFAULT_PROTECTED = (
    ".github/workflows/**", ".gitlab-ci.yml", ".circleci/**", ".pre-commit-config.yaml",
    ".eslintrc*", "eslint.config.*", ".prettierrc*", "pyproject.toml", "setup.cfg",
    "tox.ini", "pytest.ini", ".flake8", "ruff.toml", ".ruff.toml", "mypy.ini",
    ".golangci.yml", ".golangci.yaml", "jest.config.*", "vitest.config.*",
)


# A skip or focus marker on an added line of an existing test: `.skip`, `.only`,
# pytest/unittest skip and xfail, JUnit @Disabled/@Ignore, Rust #[ignore],
# jasmine/mocha x- and f- prefixes, Go t.Skip, and tests/lib.sh's `skip`.
SKIP_RE = re.compile(
    r"\.(?:skip|only)\b|@(?:pytest\.mark\.)?(?:skip|skipif|xfail)\b|\bunittest\.skip"
    r"|\bpytest\.(?:skip|xfail)\(|@Disabled\b|@Ignore\b|#\[ignore\]"
    r"|\b(?:xit|xdescribe|xtest|fit|fdescribe)\s*\(|\bt\.Skip(?:Now|f)?\(|^\s*skip\s"
)
ASSERT_RE = re.compile(r"\bassert|\bexpect\s*\(|\bt\.(?:Error|Fatal)f?\(|\brequire\.\w|\bshould\b")
TEST_DIRS = {"test", "tests", "spec", "__tests__"}
TEST_NAME_RE = re.compile(r"^test[_-]|_test\.|\.test\.|\.spec\.|Test\.")


class NotChecked(Exception):
    """The check cannot run; the message is the reason printed after `not checked —`."""


@dataclass(frozen=True)
class Policy:
    """What one AGENTS.md declares below its end marker."""

    protected: Tuple[str, ...] = ()
    expected_failures: Optional[str] = None


@dataclass(frozen=True)
class Gates:
    """The protected patterns and expected-failures files: the defaults plus the base's and the current declarations."""

    patterns: Tuple[str, ...]
    expected_failures: FrozenSet[str]
    baseline_patterns: Tuple[str, ...]


# ------------------------------------------------------------------- git


def _git(repo: str, *args: str, stdin: Optional[Union[str, bytes]] = None,
         env: Optional[Dict[str, str]] = None) -> str:
    data = stdin.encode("utf-8", errors="surrogateescape") if isinstance(stdin, str) else stdin
    result = subprocess.run(
        ("git", "-C", repo, *args), input=data, capture_output=True, env=env,
    )
    if result.returncode != 0:
        error = result.stderr.decode("utf-8", errors="replace").strip()
        raise NotChecked(f"git {' '.join(args[:2])} failed: {error or result.returncode}")
    return result.stdout.decode("utf-8", errors="replace")


def _base_entries(repo: str, base: str) -> Dict[str, Tuple[str, str]]:
    """Path → (mode, blob id) for every file in the base tree."""
    entries = {}
    for line in _git(repo, "ls-tree", "-r", "-z", base).split("\0"):
        if not line:
            continue
        meta, path = line.split("\t", 1)
        mode, kind, blob = meta.split()
        if kind == "blob":
            entries[path] = (mode, blob)
    return entries


def _working_paths(repo: str) -> List[str]:
    """Tracked and untracked, non-ignored paths of the working tree."""
    out = _git(repo, "ls-files", "-z", "-c", "-o", "--exclude-standard")
    return sorted({path for path in out.split("\0") if path})


def _blob_ids(algorithm: str, data: bytes) -> FrozenSet[str]:
    """The git blob ids `data` may stand for: its raw bytes, and the same bytes with CRLF read as LF.

    Hashed here rather than by `git hash-object`, which runs the clean filter
    the current `.gitattributes` names — a filter can launder any change. The
    one normalization accepted is a CRLF checkout of an LF blob.
    """
    variants = {data, data.replace(b"\r\n", b"\n")}
    return frozenset(hashlib.new(algorithm, b"blob %d\0" % len(item) + item).hexdigest() for item in variants)


def _blob_text(repo: str, blob: Optional[str]) -> str:
    return _git(repo, "cat-file", "blob", blob) if blob else ""


def _base_lines(repo: str, blob: Optional[str]) -> List[str]:
    return _blob_text(repo, blob).splitlines()


def _link_step(path: str, target: str) -> str:
    """The repository path a link at `path` pointing at `target` names; NotChecked when it leaves the repository."""
    resolved = os.path.normpath(os.path.join(os.path.dirname(path), target)).replace(os.sep, "/")
    if os.path.isabs(target) or resolved == ".." or resolved.startswith("../"):
        raise NotChecked(f"symlink to {target} points outside the repository")
    return resolved


def _working_lines(repo: str, path: Optional[str]) -> List[str]:
    full = os.path.join(repo, path) if path else ""
    if not path or not os.path.exists(full):
        return []
    with open(full, encoding="utf-8", errors="replace") as handle:
        return handle.read().splitlines()


# --------------------------------------------------------------- the gates


def read_policy(text: str) -> Policy:
    """The `Protected paths:` and `Expected failures:` lines below the AGENTS.md end marker."""
    protected: List[str] = []
    expected = None
    below = text.split(END_MARKER, 1)[1] if END_MARKER in text else ""
    for line in below.splitlines():
        stripped = line.strip()
        if stripped.startswith(PROTECTED_KEY):
            protected.extend(_declared_globs(stripped[len(PROTECTED_KEY):]))
        elif stripped.startswith(EXPECTED_FAILURES_KEY):
            values = _declared_globs(stripped[len(EXPECTED_FAILURES_KEY):])
            expected = values[0] if values else None
    return Policy(tuple(dict.fromkeys(protected)), expected)


def _current_policy(contents: _Contents) -> Policy:
    try:
        state = contents.current(AGENTS)
        if state.identity and state.effective_path is None:
            raise NotChecked("symlink referent is missing")
        return read_policy("\n".join(_working_lines(contents.repo, state.effective_path)))
    except (NotChecked, OSError) as exc:
        raise NotChecked(f"{AGENTS} unreadable: {exc}")


def merge_gates(base: Policy, current: Policy) -> Gates:
    """The defaults plus both policies: a declaration removed since the base still protects."""
    expected = frozenset(path for path in (base.expected_failures, current.expected_failures) if path)
    baseline = (*DEFAULT_PROTECTED, *base.protected)
    if base.expected_failures:
        baseline += (base.expected_failures,)
    patterns = (*baseline, *current.protected, *sorted(expected))
    return Gates(patterns=tuple(dict.fromkeys(patterns)), expected_failures=expected,
                 baseline_patterns=tuple(dict.fromkeys(baseline)))


def policy_removals(base: Policy, current: Policy) -> List[Tuple[str, str]]:
    """(declaration, what became of it) per base declaration the current AGENTS.md dropped or retargeted."""
    removals = [(f"{PROTECTED_KEY} {glob}", "removed") for glob in base.protected if glob not in current.protected]
    if base.expected_failures and base.expected_failures != current.expected_failures:
        removals.append((f"{EXPECTED_FAILURES_KEY} {base.expected_failures}", f"now {current.expected_failures or 'none'}"))
    return removals


def _declared_globs(value: str) -> List[str]:
    globs = []
    for token in value.split():
        glob = token.strip("`")
        try:
            globs.append(validate_pattern(glob, "AGENTS.md"))
        except SpecPathError as exc:
            raise NotChecked(f"invalid protected path: {exc}")
    return globs


def read_surface(spec: Optional[str], slice_numbers: Sequence[int]) -> Tuple[str, ...]:
    """The union of the named slices' Surfaces — every slice's with none named — or nothing with no spec."""
    if spec is None:
        return ()
    implicit = os.path.splitext(os.path.basename(spec))[0]
    slices = slice_py.resolve_slices(spec, implicit)
    for number in slice_numbers:
        if number not in slices:
            raise slice_py.SliceError(f"no slice {number} in {spec}")
    chosen = [slices[number] for number in slice_numbers] if slice_numbers else list(slices.values())
    return tuple(dict.fromkeys(entry for row in chosen for entry in row.surface))


def _declares(surface: Sequence[str], gates: Sequence[str], path: str) -> bool:
    """A Surface entry names `path` when it matches it and lies wholly inside a protected pattern."""
    return any(match_path(entry, path) and pattern_covered_by(entry, gates) for entry in surface)


# --------------------------------------------------------------- weakening


def is_test_file(path: str) -> bool:
    parts = path.split("/")
    return bool(TEST_DIRS.intersection(parts[:-1])) or bool(TEST_NAME_RE.search(parts[-1]))


def _rows(lines: Sequence[str]) -> List[str]:
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def added_expected_failures(base: Sequence[str], current: Sequence[str]) -> List[str]:
    """Rows of the expected-failures file new since the base; a reordered row is not new."""
    surplus = Counter(_rows(current)) - Counter(_rows(base))
    added = []
    for row in _rows(current):
        if surplus[row]:
            surplus[row] -= 1
            added.append(row)
    return added


def weakened_test(base: Sequence[str], current: Sequence[str]) -> List[Tuple[str, int, str]]:
    """(kind, line, text) for each skip marker added and each assertion removed and not re-added.

    Added lines carry their line in the current file, removed lines their line
    at the base. A removed assertion whose identical line appears elsewhere in
    the file moved, and is not reported.
    """
    found = []
    lost = Counter(line.strip() for line in base) - Counter(line.strip() for line in current)
    matcher = difflib.SequenceMatcher(None, base, current, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag in ("insert", "replace"):
            found.extend(("SKIP_ADDED", n + 1, current[n].strip()) for n in range(j1, j2) if SKIP_RE.search(current[n]))
        if tag in ("delete", "replace"):
            found.extend(
                ("ASSERTION_DELETED", n + 1, base[n].strip())
                for n in range(i1, i2)
                if ASSERT_RE.search(base[n]) and lost[base[n].strip()]
            )
    return found


# ------------------------------------------------------------------ report


@dataclass
class Report:
    lines: List[str]
    tampered: int = 0
    findings: int = 0
    not_checked: int = 0

    def add(self, kind: str, text: str) -> None:
        self.lines.append(f"{kind} {text}")
        if kind == "GATE_TAMPERED":
            self.tampered += 1
        elif kind == "NOT_CHECKED":
            self.not_checked += 1
        else:
            self.findings += 1

    def summary(self) -> Tuple[str, int]:
        if self.tampered:
            return f"gate-integrity: GATE_TAMPERED ({self.tampered})", 1
        if self.not_checked:
            return f"gate-integrity: not checked — {self.not_checked} file(s) unreadable", 3
        if self.findings:
            return f"gate-integrity: findings ({self.findings})", 0
        return "gate-integrity: clean", 0


def _resolve_base(repo: str, base: str) -> str:
    """The commit `base` names, or the tree when it names a tree (a `--snapshot`)."""
    _git(repo, "rev-parse", "--is-inside-work-tree")
    for kind in ("commit", "tree"):
        try:
            if not base.startswith("-"):
                return _git(repo, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{base}^{{{kind}}}").strip()
        except NotChecked:
            continue
    raise NotChecked(f"base {base} does not resolve to a commit or tree")


@dataclass(frozen=True)
class _State:
    """One path as it stands: the ids its own entry may hash to, the ids its effective content may hash to, and where that content lives."""

    identity: FrozenSet[str]
    effective: FrozenSet[str]
    effective_path: Optional[str]


@dataclass
class _Contents:
    """Resolve historical and working contents under the same bounded, repository-contained link rules."""

    repo: str
    base_entries: Dict[str, Tuple[str, str]]
    algorithm: str

    def base_effective(self, path: str) -> Optional[str]:
        """The blob id of what `path` holds at the base, a symlink followed through the base tree."""
        for _ in range(MAX_LINK_HOPS):
            for parent in PurePosixPath(path).parents:
                if self.base_entries.get(str(parent), ("", ""))[0] == LINK_MODE:
                    raise NotChecked(f"symlink directory {parent} is unsupported")
            if path not in self.base_entries:
                return None
            mode, blob = self.base_entries[path]
            if mode != LINK_MODE:
                return blob
            path = _link_step(path, _blob_text(self.repo, blob))
        raise NotChecked(f"more than {MAX_LINK_HOPS} symlinks deep")

    def current(self, path: str) -> _State:
        """`path` in the working tree, a symlink followed through the working tree.

        A link checked out as a plain file (`core.symlinks=false`) holds its
        target as text; when that text is the base link's blob, it is followed
        the same way.
        """
        identity: Optional[FrozenSet[str]] = None
        for _ in range(MAX_LINK_HOPS):
            for parent in PurePosixPath(path).parents:
                if os.path.islink(os.path.join(self.repo, str(parent))):
                    raise NotChecked(f"symlink directory {parent} is unsupported")
            full = os.path.join(self.repo, path)
            if not os.path.lexists(full):
                return _State(identity or frozenset(), frozenset(), None)
            if os.path.islink(full):
                target = os.readlink(full)
                ids = _blob_ids(self.algorithm, os.fsencode(target))
            else:
                with open(full, "rb") as handle:
                    data = handle.read()
                ids = _blob_ids(self.algorithm, data)
                entry = self.base_entries.get(path)
                if not (entry and entry[0] == LINK_MODE and entry[1] in ids):
                    return _State(identity or ids, ids, path)
                target = data.decode("utf-8", errors="replace")
            identity = identity or ids
            path = _link_step(path, target)
        raise NotChecked(f"more than {MAX_LINK_HOPS} symlinks deep")


@dataclass
class _Run:
    """One check's fixed inputs: content, baseline identity, protection and Surface authorization."""

    contents: _Contents
    base_id: str
    gates: Gates
    surface: Sequence[str]

    def protected(self, path: str) -> bool:
        return any(match_path(pattern, path) for pattern in self.gates.patterns)

    def existing_test(self, path: str) -> bool:
        return path in self.contents.base_entries and path not in self.gates.expected_failures and is_test_file(path)

    def changed(self, path: str, state: _State) -> bool:
        identity = self.contents.base_entries.get(path, ("", None))[1]
        effective = self.contents.base_effective(path)
        same_identity = identity in state.identity if identity else not state.identity
        same_effective = effective in state.effective if effective else not state.effective
        return not (same_identity and same_effective)

    def report_change(self, report: Report, path: str, state: _State) -> None:
        if self.protected(path):
            boundary = self.gates.baseline_patterns
            if not any(match_path(pattern, path) for pattern in boundary):
                boundary = self.gates.patterns
            declared = _declares(self.surface, boundary, path)
            kind, how = ("GATE_CHANGED", "declared in") if declared else ("GATE_TAMPERED", "not declared in")
            report.add(kind, f"{path} — changed since {self.base_id[:8]}, {how} the surface")
        current_lines = _working_lines(self.contents.repo, state.effective_path)
        if path in self.gates.expected_failures:
            for row in added_expected_failures(self._base(path), current_lines):
                report.add("EXPECTED_FAILURE_ADDED", f"{path} — {row}")
        if self.existing_test(path):
            for kind, line, text in weakened_test(self._base(path), current_lines):
                report.add(kind, f"{path}:{line} — {text}")

    def _base(self, path: str) -> List[str]:
        return _base_lines(self.contents.repo, self.contents.base_effective(path))


def _base_policy(contents: _Contents) -> Policy:
    blob = contents.base_effective(AGENTS)
    if blob is None and AGENTS in contents.base_entries:
        raise NotChecked(f"{AGENTS} historical symlink referent is missing")
    return read_policy(_blob_text(contents.repo, blob))


def check(repo: str, base: str, surface: Sequence[str]) -> Report:
    """Every changed protected file, added expected-failure row, weakened existing test and dropped declaration, against `base`."""
    base_id = _resolve_base(repo, base)
    entries = _base_entries(repo, base_id)
    algorithm = _git(repo, "rev-parse", "--show-object-format").strip()
    contents = _Contents(repo, entries, algorithm)
    base_policy, current_policy = _base_policy(contents), _current_policy(contents)
    run = _Run(contents, base_id, merge_gates(base_policy, current_policy), surface)
    report = Report(lines=[])
    for declaration, outcome in policy_removals(base_policy, current_policy):
        report.add("GATE_TAMPERED", f"{AGENTS} — {declaration} declared at {base_id[:8]}, {outcome}")
    candidates = [
        path for path in sorted(set(entries) | set(_working_paths(repo)))
        if run.protected(path) or run.existing_test(path)
    ]
    for path in candidates:
        try:
            state = contents.current(path)
            if run.changed(path, state):
                run.report_change(report, path, state)
        except (NotChecked, OSError) as exc:
            report.add("NOT_CHECKED", f"{path} — {exc}")
    return report


def snapshot(repo: str) -> str:
    """A raw-byte working-tree snapshot, using an empty scratch index and never running clean filters."""
    regular = []
    entries = []
    gitlinks = {}
    for record in _git(repo, "ls-files", "--stage", "-z").split("\0"):
        if not record:
            continue
        meta, path = record.split("\t", 1)
        mode, oid, stage = meta.split()
        if mode == GITLINK_MODE:
            if stage != "0":
                raise NotChecked(f"cannot snapshot unmerged gitlink {path}")
            gitlinks[path] = oid
    for path in _working_paths(repo):
        if path in gitlinks:
            entries.append(f"{GITLINK_MODE} {gitlinks[path]}\t{path}\0")
            continue
        full = os.path.join(repo, path)
        if not os.path.lexists(full):
            continue
        mode = os.lstat(full).st_mode
        if stat.S_ISLNK(mode):
            blob = _git(repo, "hash-object", "-w", "--stdin", stdin=os.fsencode(os.readlink(full))).strip()
            entries.append(f"{LINK_MODE} {blob}\t{path}\0")
        elif stat.S_ISREG(mode):
            regular.append((path, "100755" if mode & stat.S_IXUSR else "100644"))
        else:
            raise NotChecked(f"cannot snapshot non-file {path}")
    for offset in range(0, len(regular), 256):
        batch = regular[offset:offset + 256]
        blobs = _git(repo, "hash-object", "--no-filters", "-w", "--", *(path for path, _ in batch)).splitlines()
        entries.extend(f"{mode} {blob}\t{path}\0" for (path, mode), blob in zip(batch, blobs))
    with tempfile.TemporaryDirectory(prefix="gate-snapshot-") as scratch:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(scratch, "index"))
        _git(repo, "update-index", "-z", "--index-info", stdin="".join(entries), env=env)
        return _git(repo, "write-tree", env=env).strip()


# --------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gate-integrity", description="Compare protected gate files against their blobs at a base commit.")
    parser.add_argument("--base", help="base commit or tree the gates are compared against")
    parser.add_argument("--snapshot", action="store_true", help="print the working tree's tree id and exit")
    parser.add_argument("--spec", help="spec whose § Build Order Surface may declare protected paths")
    parser.add_argument("--slice", type=int, action="append", default=[],
                        help="slice number, repeatable for a parallel batch; omitted, every slice's Surface counts")
    parser.add_argument("--repo", default=".", help="repository to check (default: cwd)")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.snapshot:
        try:
            print(snapshot(args.repo))
        except (NotChecked, OSError) as exc:
            print(f"gate-integrity: not checked — {exc}")
            return 3
        return 0
    if args.base is None:
        parser.error("--base is required")
    if args.slice and args.spec is None:
        parser.error("--slice needs --spec")
    try:
        surface = read_surface(args.spec, args.slice)
    except (SpecPathError, slice_py.SliceError, OSError) as exc:
        print(f"gate-integrity: {exc}", file=sys.stderr)
        return 2
    try:
        report = check(args.repo, args.base, surface)
    except (NotChecked, OSError) as exc:
        print(f"gate-integrity: not checked — {exc}")
        return 3
    for line in report.lines:
        print(line)
    summary, status = report.summary()
    print(summary)
    return status


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    sys.exit(main())
