#!/usr/bin/env python3
"""gate-integrity.py — did this change edit the checks that judge it?

A slice can pass by weakening its own gate: one line in the expected-failures
list makes a failing suite pass. This script compares every protected file —
test runners, the expected-failures list, CI workflows, lint and test configs —
against its blob at a base commit by content hash (`git hash-object` of the
working-tree bytes against the blob id `git ls-tree` records). No diff output
is read, so an `assume-unchanged` bit, an edit committed after the base and a
`diff.mnemonicPrefix` setting all leave the answer unchanged
(specs/gate-integrity.md).

    gate-integrity.py --base <rev> [--spec <spec> [--slice <n>]] [--repo <dir>]

Exit 1 when a protected file changed outside the Surface (GATE_TAMPERED);
otherwise 3 when the check could not run in full (not checked); otherwise 0,
findings or not. 2 is bad usage.
"""

from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

_SCRIPTS = os.path.dirname(os.path.abspath(__file__))
for _relative in (("..", "..", "task-registry", "scripts"), ("..", "..", "slice", "scripts")):
    _path = os.path.normpath(os.path.join(_SCRIPTS, *_relative))
    if _path not in sys.path:
        sys.path.insert(0, _path)

import slice as slice_py  # noqa: E402  (path must be set up first)
from registry.globs import SpecPathError, match_path, pattern_covered_by, validate_pattern  # noqa: E402

END_MARKER = "<!-- jplugin-agentic-development:end -->"
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
class Gates:
    """The protected patterns and the expected-failures file, if one is declared."""

    patterns: Tuple[str, ...]
    expected_failures: Optional[str]


# ------------------------------------------------------------------- git


def _git(repo: str, *args: str, stdin: Optional[str] = None) -> str:
    result = subprocess.run(
        ("git", "-C", repo, *args), input=stdin, capture_output=True,
        text=True, encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        raise NotChecked(f"git {' '.join(args[:2])} failed: {result.stderr.strip() or result.returncode}")
    return result.stdout


def _base_blobs(repo: str, base: str) -> Dict[str, str]:
    """Path → blob id for every file in the base tree."""
    blobs = {}
    for line in _git(repo, "ls-tree", "-r", "-z", base).split("\0"):
        if not line:
            continue
        meta, path = line.split("\t", 1)
        mode, kind, blob = meta.split()
        if kind == "blob":
            blobs[path] = blob
    return blobs


def _working_paths(repo: str) -> List[str]:
    """Tracked and untracked, non-ignored paths of the working tree."""
    out = _git(repo, "ls-files", "-z", "-c", "-o", "--exclude-standard")
    return sorted({path for path in out.split("\0") if path})


def _working_blobs(repo: str, paths: Sequence[str]) -> Dict[str, object]:
    """Path → the blob id its working-tree bytes hash to, None when absent, or the NotChecked that stopped it.

    One `hash-object --stdin-paths` for every present path; when that batch
    fails, each path is hashed alone so only the unreadable one is lost.
    """
    present = [path for path in paths if os.path.lexists(os.path.join(repo, path))]
    blobs: Dict[str, object] = {path: None for path in paths}
    try:
        hashed = _git(repo, "hash-object", "--stdin-paths", stdin="".join(f"{path}\n" for path in present)).split()
        blobs.update(zip(present, hashed))
    except NotChecked:
        for path in present:
            try:
                blobs[path] = _git(repo, "hash-object", "--", path).strip()
            except NotChecked as exc:
                blobs[path] = exc
    return blobs


def _base_lines(repo: str, blob: Optional[str]) -> List[str]:
    return _git(repo, "cat-file", "blob", blob).splitlines() if blob else []


def _working_lines(repo: str, path: str) -> List[str]:
    full = os.path.join(repo, path)
    if not os.path.lexists(full):
        return []
    with open(full, encoding="utf-8", errors="replace") as handle:
        return handle.read().splitlines()


# --------------------------------------------------------------- the gates


def read_gates(repo: str) -> Gates:
    """Defaults plus the `Protected paths:` and `Expected failures:` lines below the AGENTS.md end marker."""
    patterns = list(DEFAULT_PROTECTED)
    expected = None
    agents = os.path.join(repo, "AGENTS.md")
    if os.path.exists(agents):
        with open(agents, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        below = text.split(END_MARKER, 1)[1] if END_MARKER in text else ""
        for line in below.splitlines():
            stripped = line.strip()
            if stripped.startswith(PROTECTED_KEY):
                patterns.extend(_declared_globs(stripped[len(PROTECTED_KEY):]))
            elif stripped.startswith(EXPECTED_FAILURES_KEY):
                values = _declared_globs(stripped[len(EXPECTED_FAILURES_KEY):])
                expected = values[0] if values else None
    if expected:
        patterns.append(expected)
    return Gates(patterns=tuple(dict.fromkeys(patterns)), expected_failures=expected)


def _declared_globs(value: str) -> List[str]:
    globs = []
    for token in value.split():
        glob = token.strip("`")
        try:
            globs.append(validate_pattern(glob, "AGENTS.md"))
        except SpecPathError as exc:
            raise NotChecked(f"invalid protected path: {exc}")
    return globs


def read_surface(spec: Optional[str], slice_number: Optional[int]) -> Tuple[str, ...]:
    """The slice's Surface, the union of every slice's with no number, or nothing with no spec."""
    if spec is None:
        return ()
    implicit = os.path.splitext(os.path.basename(spec))[0]
    slices = slice_py.resolve_slices(spec, implicit)
    if slice_number is None:
        return tuple(dict.fromkeys(entry for row in slices.values() for entry in row.surface))
    if slice_number not in slices:
        raise slice_py.SliceError(f"no slice {slice_number} in {spec}")
    return slices[slice_number].surface


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
    _git(repo, "rev-parse", "--is-inside-work-tree")
    try:
        return _git(repo, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}").strip()
    except NotChecked:
        raise NotChecked(f"base {base} does not resolve to a commit")


@dataclass
class _Run:
    """One check's fixed inputs: what the base held, what is protected, what the Surface declares."""

    repo: str
    base_commit: str
    base_blobs: Dict[str, str]
    gates: Gates
    surface: Sequence[str]

    def protected(self, path: str) -> bool:
        return any(match_path(pattern, path) for pattern in self.gates.patterns)

    def existing_test(self, path: str) -> bool:
        return path in self.base_blobs and path != self.gates.expected_failures and is_test_file(path)

    def report_change(self, report: Report, path: str) -> None:
        if self.protected(path):
            declared = _declares(self.surface, self.gates.patterns, path)
            kind, how = ("GATE_CHANGED", "declared in") if declared else ("GATE_TAMPERED", "not declared in")
            report.add(kind, f"{path} — changed since {self.base_commit[:8]}, {how} the surface")
        if path == self.gates.expected_failures:
            for row in added_expected_failures(self._base(path), _working_lines(self.repo, path)):
                report.add("EXPECTED_FAILURE_ADDED", f"{path} — {row}")
        if self.existing_test(path):
            for kind, line, text in weakened_test(self._base(path), _working_lines(self.repo, path)):
                report.add(kind, f"{path}:{line} — {text}")

    def _base(self, path: str) -> List[str]:
        return _base_lines(self.repo, self.base_blobs.get(path))


def check(repo: str, base: str, surface: Sequence[str]) -> Report:
    """Every changed protected file, added expected-failure row and weakened existing test, against `base`."""
    base_commit = _resolve_base(repo, base)
    run = _Run(repo, base_commit, _base_blobs(repo, base_commit), read_gates(repo), surface)
    candidates = [
        path for path in sorted(set(run.base_blobs) | set(_working_paths(repo)))
        if run.protected(path) or run.existing_test(path)
    ]
    report = Report(lines=[])
    for path, current in _working_blobs(repo, candidates).items():
        if current == run.base_blobs.get(path):
            continue
        try:
            if isinstance(current, NotChecked):
                raise current
            run.report_change(report, path)
        except (NotChecked, OSError) as exc:
            report.add("NOT_CHECKED", f"{path} — {exc}")
    return report


# --------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gate-integrity", description="Compare protected gate files against their blobs at a base commit.")
    parser.add_argument("--base", required=True, help="base revision the gates are compared against")
    parser.add_argument("--spec", help="spec whose § Build Order Surface may declare protected paths")
    parser.add_argument("--slice", type=int, help="slice number; omitted, every slice's Surface counts")
    parser.add_argument("--repo", default=".", help="repository to check (default: cwd)")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.slice is not None and args.spec is None:
        parser.error("--slice needs --spec")
    try:
        surface = read_surface(args.spec, args.slice)
    except (SpecPathError, slice_py.SliceError, OSError) as exc:
        print(f"gate-integrity: {exc}", file=sys.stderr)
        return 2
    try:
        report = check(args.repo, args.base, surface)
    except NotChecked as exc:
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
