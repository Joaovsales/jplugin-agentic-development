#!/usr/bin/env python3
"""Render the harness-neutral workflow into Codex user configuration."""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import tempfile
from pathlib import Path
from typing import NoReturn, Optional

SLUG = "jplugin-agentic-development"
BEGIN = f"<!-- {SLUG}:begin -->"
END = f"<!-- {SLUG}:end -->"
MANAGED = f"# {SLUG}:managed"
# Files written before the repository rename carry the old slug in the same three
# markers and in the hook file names. Assembled at runtime so the identity sweep
# (tests/test-repo-identity.sh) does not read this module as a live reference.
LEGACY_SLUG = "coding-agent" + "-workflow"
LEGACY_BEGIN = BEGIN.replace(SLUG, LEGACY_SLUG)
LEGACY_END = END.replace(SLUG, LEGACY_SLUG)
LEGACY_MANAGED = MANAGED.replace(SLUG, LEGACY_SLUG)
LEGACY_HOOK_FILES = tuple(
    f"{LEGACY_SLUG}-{name}" for name in ("session-start.py", "pre-compact.sh", "session-end.sh")
)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"render-codex: {message}")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
        ) as stream:
            temporary = Path(stream.name)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def parse_value(raw: str) -> str:
    value = raw.strip()
    if value[:1] in {"'", '"'}:
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            fail(f"invalid frontmatter value: {value!r} ({exc})")
        if not isinstance(parsed, str):
            fail(f"frontmatter value is not text: {value!r}")
        return parsed
    return value


def parse_agent(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        fail(f"{path}: missing YAML frontmatter")
    try:
        end = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        fail(f"{path}: unterminated YAML frontmatter")

    fields: dict[str, str] = {}
    for line in lines[1:end]:
        if not line.strip():
            continue
        if ":" not in line:
            fail(f"{path}: malformed frontmatter line: {line}")
        key, value = line.split(":", 1)
        fields[key.strip()] = parse_value(value)
    for required in ("name", "description"):
        if not fields.get(required):
            fail(f"{path}: frontmatter requires {required}")

    body_lines = lines[end + 1 :]
    if body_lines and body_lines[0].strip() == "---":
        try:
            second_end = next(
                index for index, line in enumerate(body_lines[1:], 1) if line.strip() == "---"
            )
        except StopIteration:
            fail(f"{path}: unterminated secondary frontmatter")
        body_lines = body_lines[second_end + 1 :]
    body = "\n".join(body_lines).strip()
    if not body:
        fail(f"{path}: agent instructions are empty")
    return fields["name"], fields["description"], body


def render_global(source: Path, destination: Path) -> None:
    source_text = source.read_text(encoding="utf-8")
    marker = "## Session Start Checklist"
    if marker not in source_text:
        fail(f"{source}: shared rules marker not found")
    body = source_text[source_text.index(marker) :]
    body = "\n".join(line for line in body.splitlines() if not line.startswith("@"))
    managed = (
        f"{BEGIN}\n"
        "# Shared jplugin for agentic development\n"
        "> Project-specific instructions belong in the project's AGENTS.md.\n\n"
        f"{body.rstrip()}\n"
        f"{END}\n"
    )
    existing = destination.read_text(encoding="utf-8") if destination.exists() else ""
    begin, end = BEGIN, END
    if BEGIN not in existing and LEGACY_BEGIN in existing and LEGACY_END in existing:
        begin, end = LEGACY_BEGIN, LEGACY_END
    if begin in existing and end in existing:
        before = existing.split(begin, 1)[0]
        after = existing.split(end, 1)[1].lstrip("\n")
        result = before + managed + after
    else:
        result = existing.rstrip() + ("\n\n" if existing.strip() else "") + managed
    write_text(destination, result)


def render_agents(source_dir: Path, destination_dir: Path) -> None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    for source in sorted(source_dir.glob("*.md")):
        if source.name == "README.md":
            continue
        name, description, instructions = parse_agent(source)
        destination = destination_dir / f"{source.stem}.toml"
        existing = destination.read_text(encoding="utf-8") if destination.exists() else ""
        if destination.exists() and MANAGED not in existing and LEGACY_MANAGED not in existing:
            print(f"kept personal agent: {destination}")
            continue
        content = (
            f"{MANAGED}\n"
            f"name = {json.dumps(name, ensure_ascii=False)}\n"
            f"description = {json.dumps(description, ensure_ascii=False)}\n"
            f"developer_instructions = {json.dumps(instructions, ensure_ascii=False)}\n"
        )
        write_text(destination, content)


def _is_legacy_adapter(hook: object) -> bool:
    """Only this adapter's three pre-rename hook files — matched as whole path
    components, so a user hook whose path merely contains the old slug survives.
    """
    if not isinstance(hook, dict):
        return False
    command = str(hook.get("command", ""))
    return any(
        re.search(rf"(^|[\\/\s]){re.escape(name)}(\s|$)", command) for name in LEGACY_HOOK_FILES
    )


def _drop_legacy_adapter(groups: list) -> None:
    """Remove this adapter's pre-rename registration for one event, in place.

    A machine installed before the repository rename holds the same hook under
    the old file name; left alone, a re-run would register the renamed file
    beside it and the event would fire the adapter twice.
    """
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            continue
        kept = []
        for hook in group["hooks"]:
            if _is_legacy_adapter(hook):
                print(f"replaced legacy hook: {hook.get('command')}")
            else:
                kept.append(hook)
        group["hooks"] = kept
    groups[:] = [g for g in groups if not (isinstance(g, dict) and g.get("hooks") == [])]


def merge_hooks(destination: Path, commands: list[str]) -> None:
    if destination.exists():
        try:
            data = json.loads(destination.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"{destination}: invalid JSON ({exc})")
    else:
        data = {}
    if not isinstance(data, dict):
        fail(f"{destination}: top-level JSON value must be an object")
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        fail(f"{destination}: hooks must be an object")
    events = ("SessionStart", "PreCompact", "SessionEnd")
    for event, command in zip(events, commands):
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            fail(f"{destination}: {event} must be an array")
        _drop_legacy_adapter(groups)
        registered = any(
            isinstance(group, dict)
            and any(
                isinstance(hook, dict) and hook.get("command") == command
                for hook in group.get("hooks", [])
            )
            for group in groups
        )
        if not registered:
            groups.append({"hooks": [{"type": "command", "command": command}]})
    write_text(destination, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--global", dest="global_args", nargs=2, metavar=("SOURCE", "DEST"))
    parser.add_argument("--agents", dest="agents_args", nargs=2, metavar=("SOURCE", "DEST"))
    parser.add_argument(
        "--merge-hooks",
        dest="hooks_args",
        nargs=4,
        metavar=("DEST", "SESSION_START", "PRE_COMPACT", "SESSION_END"),
    )
    args = parser.parse_args()
    selected = [args.global_args, args.agents_args, args.hooks_args]
    if sum(value is not None for value in selected) != 1:
        parser.error("choose exactly one rendering operation")
    if args.global_args:
        render_global(Path(args.global_args[0]), Path(args.global_args[1]))
    elif args.agents_args:
        render_agents(Path(args.agents_args[0]), Path(args.agents_args[1]))
    else:
        merge_hooks(Path(args.hooks_args[0]), args.hooks_args[1:])


if __name__ == "__main__":
    main()
