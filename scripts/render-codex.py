#!/usr/bin/env python3
"""Render the harness-neutral workflow into Codex user configuration."""

from __future__ import annotations

import argparse
import ast
import json
import os
import tempfile
from pathlib import Path
from typing import NoReturn, Optional

BEGIN = "<!-- coding-agent-workflow:begin -->"
END = "<!-- coding-agent-workflow:end -->"
MANAGED = "# coding-agent-workflow:managed"

# Scout tier is the only tier Codex pins (specs/bulk-read-gate.md). Every other
# agent omits `model`, which on Codex inherits the parent session — the Ceiling
# semantics CLAUDE.md § Model Routing describes. The concrete ID is not written
# here: PI_SETUP.md § Sub-Agent Routing owns it, and install-codex.sh reads it
# from that table and passes it in as --scout-model.
SCOUT_TIER_AGENTS = frozenset({"bulk-reader", "context-document-optimizer"})


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
        "# Shared Coding Agent Workflow\n"
        "> Project-specific instructions belong in the project's AGENTS.md.\n\n"
        f"{body.rstrip()}\n"
        f"{END}\n"
    )
    existing = destination.read_text(encoding="utf-8") if destination.exists() else ""
    if BEGIN in existing and END in existing:
        before = existing.split(BEGIN, 1)[0]
        after = existing.split(END, 1)[1].lstrip("\n")
        result = before + managed + after
    else:
        result = existing.rstrip() + ("\n\n" if existing.strip() else "") + managed
    write_text(destination, result)


def render_agents(source_dir: Path, destination_dir: Path, scout_model: Optional[str]) -> None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    for source in sorted(source_dir.glob("*.md")):
        if source.name == "README.md":
            continue
        name, description, instructions = parse_agent(source)
        destination = destination_dir / f"{source.stem}.toml"
        if destination.exists() and MANAGED not in destination.read_text(encoding="utf-8"):
            print(f"kept personal agent: {destination}")
            continue
        model_line = ""
        if source.stem in SCOUT_TIER_AGENTS:
            if not scout_model:
                fail(f"{source.name} is Scout tier but no --scout-model was given")
            model_line = f"model = {json.dumps(scout_model)}\n"
        content = (
            f"{MANAGED}\n"
            f"name = {json.dumps(name, ensure_ascii=False)}\n"
            f"description = {json.dumps(description, ensure_ascii=False)}\n"
            f"{model_line}"
            f"developer_instructions = {json.dumps(instructions, ensure_ascii=False)}\n"
        )
        write_text(destination, content)


def parse_hook_bindings(pairs: list[str]) -> list[tuple[str, str]]:
    """EVENT=COMMAND pairs, so the binding travels with the argument."""
    bindings: list[tuple[str, str]] = []
    for pair in pairs:
        event, separator, command = pair.partition("=")
        if not separator or not event or not command:
            fail(f"hook binding must be EVENT=COMMAND, got {pair!r}")
        bindings.append((event, command))
    return bindings


def merge_hooks(destination: Path, bindings: list[tuple[str, str]]) -> None:
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
    for event, command in bindings:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            fail(f"{destination}: {event} must be an array")
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
        "--scout-model",
        dest="scout_model",
        metavar="MODEL_ID",
        help="Codex model pinned on Scout-tier agents (read from PI_SETUP.md by install-codex.sh)",
    )
    parser.add_argument(
        "--merge-hooks",
        dest="hooks_args",
        nargs="+",
        metavar=("DEST", "EVENT=COMMAND"),
    )
    args = parser.parse_args()
    selected = [args.global_args, args.agents_args, args.hooks_args]
    if sum(value is not None for value in selected) != 1:
        parser.error("choose exactly one rendering operation")
    if args.global_args:
        render_global(Path(args.global_args[0]), Path(args.global_args[1]))
    elif args.agents_args:
        render_agents(Path(args.agents_args[0]), Path(args.agents_args[1]), args.scout_model)
    else:
        if len(args.hooks_args) < 2:
            parser.error("--merge-hooks needs DEST and at least one EVENT=COMMAND")
        merge_hooks(Path(args.hooks_args[0]), parse_hook_bindings(args.hooks_args[1:]))


if __name__ == "__main__":
    main()
