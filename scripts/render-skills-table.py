#!/usr/bin/env python3
"""Render the README skills table from the skill frontmatter (template repository only).

    python3 scripts/render-skills-table.py [--check] [--repo DIR]

Every `.agents/skills/*/SKILL.md` contributes one row — `name` and `description`
from its frontmatter, plus its `harness` when that is anything but `universal` —
sorted by directory name, written between `<!-- skills-table:begin -->` and
`<!-- skills-table:end -->` in README.md. Without `--check` the table is rewritten
(exit 0). With `--check` nothing is written: exit 0 when README.md already carries
the rendered table, exit 1 with a unified diff when it does not. Exit 2 names the
problem when a SKILL.md lacks `name` or `description`, or README.md lacks exactly
one marker pair — nothing is written then either.

`/tidy`'s `inventory` check runs this as its Tier 0 fix; tests/test-skills-table.sh
runs `--check` as the drift test.
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path
from typing import Dict, List, NoReturn

BEGIN = "<!-- skills-table:begin -->"
END = "<!-- skills-table:end -->"
HEADER = ("| Skill | What It Does | Harness |", "|-------|-------------|---------|")


def fail(message: str) -> NoReturn:
    print(f"render-skills-table: {message}", file=sys.stderr)
    sys.exit(2)


def unquote(value: str) -> str:
    if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
        return value[1:-1]
    return value


def frontmatter(path: Path) -> Dict[str, str]:
    """The `key: value` pairs between the opening and closing `---`.

    Tolerates what the skill tree contains: `#` comment lines, and folded or
    indented continuation lines, which append to the previous key.
    """
    label = path.parent.name
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError as exc:
        fail(f"{label}: SKILL.md is not UTF-8 ({exc.reason} at byte {exc.start})")
    if not lines or lines[0].strip() != "---":
        fail(f"{label}: SKILL.md has no frontmatter")
    fields: Dict[str, str] = {}
    key = ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[:1] in " \t" and key:
            fields[key] = f"{fields[key]} {line.strip()}".strip()
            continue
        if ":" not in line:
            fail(f"{label}: malformed frontmatter line: {line}")
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        fields[key] = "" if value in (">", "|", ">-", "|-") else unquote(value)
    else:
        fail(f"{label}: unterminated frontmatter")
    return fields


def rows(skills_dir: Path) -> List[str]:
    out: List[str] = []
    for directory in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        skill = directory / "SKILL.md"
        if not skill.is_file():
            continue
        fields = frontmatter(skill)
        for required in ("name", "description"):
            if not fields.get(required):
                fail(f"{directory.name}: SKILL.md frontmatter has no {required}")
        harness = fields.get("harness", "universal")
        cell = "" if harness == "universal" else harness
        description = fields["description"].replace("|", "\\|")
        out.append(f"| `/{fields['name']}` | {description} | {cell} |")
    return out


def render(skills_dir: Path) -> str:
    return "\n".join([*HEADER, *rows(skills_dir)]) + "\n"


def splice(readme: str, table: str) -> str:
    if readme.count(BEGIN) != 1 or readme.count(END) != 1 or readme.index(END) < readme.index(BEGIN):
        fail(f"README.md: the marker pair {BEGIN} / {END} must appear exactly once, in that order")
    before, rest = readme.split(BEGIN, 1)
    _, after = rest.split(END, 1)
    return f"{before}{BEGIN}\n{table}{END}{after}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 with a diff instead of writing")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: the checkout this script lives in)")
    args = parser.parse_args()
    readme_path = args.repo / "README.md"
    skills_dir = args.repo / ".agents" / "skills"
    if not skills_dir.is_dir():
        fail(f"{skills_dir}: not a directory")
    if not readme_path.is_file():
        fail(f"{readme_path}: not a file")
    with open(readme_path, encoding="utf-8", newline="") as handle:
        raw = handle.read()
    newline = "\r\n" if "\r\n" in raw else "\n"
    current = raw.replace("\r\n", "\n")
    expected = splice(current, render(skills_dir))
    if expected == current:
        return
    if args.check:
        sys.stdout.writelines(difflib.unified_diff(
            current.splitlines(keepends=True), expected.splitlines(keepends=True),
            fromfile="README.md", tofile="README.md (rendered from .agents/skills/*/SKILL.md)",
        ))
        sys.exit(1)
    with open(readme_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(expected.replace("\n", newline))
    print("README.md: skills table rewritten")


if __name__ == "__main__":
    main()
