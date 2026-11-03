"""Preview and apply Codex agent/config changes without adopting personal files."""

from __future__ import annotations

import os
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PlanItem:
    path: Path
    state: str
    desired: bytes
    original: bytes | None
    backup: Path | None = None
    note: str = ""


def _read(path: Path) -> bytes | None:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"refusing non-regular Codex file: {path}")
    return path.read_bytes() if path.exists() else None


def _backup_path(path: Path) -> Path:
    candidate = path.with_name(path.name + ".bak")
    suffix = 1
    while candidate.exists():
        candidate = path.with_name(path.name + f".bak.{suffix}")
        suffix += 1
    return candidate


def _parse(content: bytes) -> dict | None:
    try:
        return tomllib.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError):
        return None


def _managed_agent(path: Path, target: bytes, original: bytes, parsed: dict) -> PlanItem:
    expected = _parse(target)
    known = {"name", "description", "developer_instructions", "model",
             "model_reasoning_effort", "sandbox_mode"}
    if (parsed.get("name") != expected["name"] or not
            all(isinstance(parsed.get(key), str) for key in ("name", "description", "developer_instructions"))
            or not set(parsed) <= known):
        return PlanItem(path, "personal_conflict", target, original,
                        note="managed marker has unexpected agent identity or fields")
    state = "match" if original == target else "managed_drift"
    return PlanItem(path, state, target, original)


def plan_agent(path: Path, desired: str, legacy: str | None,
               markers: tuple[str, ...]) -> PlanItem:
    target = desired.encode("utf-8")
    if path.is_symlink() or (path.exists() and not path.is_file()):
        return PlanItem(path, "invalid", target, None, note="non-regular file")
    original = _read(path)
    if original is None:
        return PlanItem(path, "missing", target, None)
    parsed = _parse(original)
    if parsed is None:
        return PlanItem(path, "invalid", target, original)
    if any(original.startswith((marker + "\n").encode()) for marker in markers):
        return _managed_agent(path, target, original, parsed)
    if legacy is not None and original == legacy.encode("utf-8"):
        return PlanItem(path, "legacy_candidate", target, original, _backup_path(path))
    return PlanItem(path, "personal_conflict", target, original)


def _with_cap(content: str, cap: int) -> str:
    lines = content.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.strip().split("#", 1)[0].strip() == "[agents]":
            lines.insert(index + 1, f"max_concurrent_threads_per_session = {cap}\n")
            return "".join(lines)
    separator = "" if not content or content.endswith("\n") else "\n"
    return content + separator + f"[agents]\nmax_concurrent_threads_per_session = {cap}\n"


def _configured_cap(path: Path, original: bytes, agents: dict, cap: int) -> PlanItem | None:
    defaults = ("default_subagent_model", "default_subagent_reasoning_effort")
    configured_default = next((key for key in defaults if key in agents), None)
    if configured_default:
        return PlanItem(path, "personal_conflict", original, original,
                        note=f"agents.{configured_default} would cap Ceiling")
    native = agents.get("max_concurrent_threads_per_session")
    legacy = agents.get("max_threads")
    configured = native if native is not None else legacy
    if configured is None:
        return None
    if type(configured) is not int or configured <= 0:
        return PlanItem(path, "invalid", original, original, note="invalid child cap")
    alias = "legacy max_threads alias; " if native is None else ""
    note = alias + ("cap exceeds policy" if configured > cap else "user cap preserved")
    return PlanItem(path, "preserved", original, original, note=note)


def _missing_cap(path: Path, original: bytes, cap: int) -> PlanItem:
    desired = _with_cap(original.decode("utf-8"), cap).encode("utf-8")
    if _parse(desired) is None:
        return PlanItem(path, "personal_conflict", original, original,
                        note="cannot add native cap without changing personal config structure")
    return PlanItem(path, "config_update", desired, original, _backup_path(path),
                    note="native cap missing")


def plan_config(path: Path, cap: int) -> PlanItem:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        return PlanItem(path, "invalid", b"", None, note="non-regular file")
    original = _read(path)
    if original is None:
        desired = f"[agents]\nmax_concurrent_threads_per_session = {cap}\n".encode()
        return PlanItem(path, "missing", desired, None, note="native cap missing")
    parsed = _parse(original)
    if parsed is None or not isinstance(parsed, dict):
        return PlanItem(path, "invalid", original, original)
    agents = parsed.get("agents", {})
    if not isinstance(agents, dict):
        return PlanItem(path, "invalid", original, original)
    configured = _configured_cap(path, original, agents, cap)
    if configured is not None:
        return configured
    return _missing_cap(path, original, cap)


def describe(items: list[PlanItem]) -> list[str]:
    lines = []
    for item in items:
        detail = f" ({item.note})" if item.note else ""
        backup = f" backup: {item.backup}" if item.backup else ""
        lines.append(f"{item.path}: {item.state}{detail}{backup}")
    return lines


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def apply(items: list[PlanItem], adopt_legacy: bool) -> None:
    conflicts = [item for item in items if item.state in {"invalid", "personal_conflict"}]
    if conflicts:
        raise ValueError("conflicting personal or invalid Codex file: " + str(conflicts[0].path))
    if not adopt_legacy and any(item.state == "legacy_candidate" for item in items):
        raise ValueError("legacy_candidate needs --adopt-legacy after --preview")
    if any(_read(item.path) != item.original for item in items):
        raise ValueError("Codex files changed since preview; retry")
    for item in items:
        if item.state in {"match", "preserved"}:
            continue
        if item.backup:
            descriptor = os.open(item.backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(item.original or b"")
                stream.flush()
                os.fsync(stream.fileno())
        _atomic_write(item.path, item.desired)
