#!/usr/bin/env python3
"""Report drift between reviewed Git revisions and registered upstream refs."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path, PurePosixPath
from typing import Any

try:
    import resource
except ImportError:  # Windows has no POSIX resource limits.
    resource = None

MAX_REGISTRY_BYTES = 1_000_000
MAX_SOURCES = 100
MAX_CHANGED_PATHS = 20
MAX_FIELD_LENGTH = 2_048
MAX_GIT_DIAGNOSTIC_BYTES = 4_096
CHECK_DEADLINE_SECONDS = 600
MAX_GIT_FILE_BYTES = 512 * 1024 * 1024
MAX_GIT_MEMORY_BYTES = 1024 * 1024 * 1024
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{40}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
CHECK_DEADLINE = float("inf")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default=".github/upstreams.json")
    parser.add_argument("--repository-root")
    parser.add_argument("--deadline-seconds", type=float, default=CHECK_DEADLINE_SECONDS)
    return parser.parse_args()


def safe_relative(value: object) -> bool:
    if not isinstance(value, str) or not value or len(value) > MAX_FIELD_LENGTH:
        return False
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and all(part not in ("", ".", "..") for part in path.parts)


def required_string(source: dict[str, Any], field: str, index: int) -> tuple[str, list[str]]:
    errors = []
    value = source.get(field)
    has_control = isinstance(value, str) and any(ord(character) < 32 or ord(character) == 127 for character in value)
    if not isinstance(value, str) or not value or len(value) > MAX_FIELD_LENGTH or has_control:
        errors.append(f"sources[{index}].{field} must be a non-empty bounded string")
        return "", errors
    if value.startswith("-"):
        errors.append(f"sources[{index}].{field} must not begin with '-'")
    return value, errors


def validate_paths(source: dict[str, Any], index: int) -> list[str]:
    if "paths" not in source:
        return []
    errors = []
    paths = source["paths"]
    if not isinstance(paths, list) or not paths:
        errors.append(f"sources[{index}].paths must be a non-empty list when present")
        return errors
    if len(paths) != len(set(item for item in paths if isinstance(item, str))):
        errors.append(f"sources[{index}].paths contains duplicates")
    for path_index, path in enumerate(paths):
        if not safe_relative(path):
            errors.append(f"sources[{index}].paths[{path_index}] must be a safe relative path")
    return errors


def validate_identity(fields: dict[str, str], index: int, seen: set[str]) -> list[str]:
    errors = []
    source_id = fields["id"]
    if source_id and not ID_RE.fullmatch(source_id):
        errors.append(f"sources[{index}].id has an invalid format")
    if source_id in seen:
        errors.append(f"sources[{index}].id duplicates '{source_id}'")
    seen.add(source_id)
    baseline = fields["baseline"]
    if baseline and not COMMIT_RE.fullmatch(baseline):
        errors.append(f"sources[{index}].baseline must be a full 40-character commit")
    return errors


def validate_ref(ref: str, index: int) -> list[str]:
    forbidden = ("..", "@{", "\\", " ", "~", "^", ":", "?", "*", "[")
    parts = ref.split("/")
    valid_prefix = ref.startswith("refs/heads/") or ref.startswith("refs/tags/")
    invalid_part = any(not part or part.startswith(".") or part.endswith(".") or part.endswith(".lock") for part in parts)
    if not valid_prefix or invalid_part or ref.endswith("/") or any(token in ref for token in forbidden):
        return [f"sources[{index}].ref must be a valid refs/heads/* or refs/tags/* name"]
    return []


def validate_source(source: object, index: int, seen: set[str]) -> list[str]:
    if not isinstance(source, dict):
        return [f"sources[{index}] must be an object"]
    fields = {}
    errors = []
    for field in ("id", "url", "ref", "baseline"):
        fields[field], field_errors = required_string(source, field, index)
        errors.extend(field_errors)
    errors.extend(validate_identity(fields, index, seen))
    errors.extend(validate_ref(fields["ref"], index))
    notice = source.get("source_notice")
    if not safe_relative(notice):
        errors.append(f"sources[{index}].source_notice must be a safe relative path")
    errors.extend(validate_paths(source, index))
    return errors


def validate_registry(registry: object) -> list[str]:
    if not isinstance(registry, dict):
        return ["registry root must be an object"]
    errors = []
    if registry.get("version") != 1:
        errors.append("version must equal 1")
    sources = registry.get("sources")
    if not isinstance(sources, list) or not sources or len(sources) > MAX_SOURCES:
        errors.append(f"sources must contain 1-{MAX_SOURCES} entries")
        return errors
    seen: set[str] = set()
    for index, source in enumerate(sources):
        errors.extend(validate_source(source, index, seen))
    return errors


def validate_notices(registry: dict[str, Any], repository_root: Path) -> list[str]:
    errors = []
    for index, source in enumerate(registry["sources"]):
        notice = source["source_notice"]
        if not (repository_root / notice).is_file():
            errors.append(f"sources[{index}].source_notice must name an existing file")
    return errors


def resolve_repository_root(registry_path: Path, configured: str | None) -> Path:
    if configured:
        return Path(configured).resolve()
    if registry_path.parent.name == ".github":
        return registry_path.parent.parent.resolve()
    return Path.cwd()


def load_registry(path: Path, repository_root: Path) -> tuple[dict[str, Any] | None, list[str]]:
    try:
        if path.stat().st_size > MAX_REGISTRY_BYTES:
            return None, [f"registry exceeds {MAX_REGISTRY_BYTES} bytes"]
        registry = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return None, [f"cannot read registry: {error}"]
    errors = validate_registry(registry)
    if not errors:
        errors.extend(validate_notices(registry, repository_root))
    return (registry if not errors else None), errors


def failed_git(command: list[str], returncode: int, message: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.CompletedProcess(command, returncode, b"", message.encode("utf-8", "replace"))


def child_resource_limits() -> Any:
    if resource is None:
        return None

    def apply_limits() -> None:
        limits = (("RLIMIT_FSIZE", MAX_GIT_FILE_BYTES), ("RLIMIT_AS", MAX_GIT_MEMORY_BYTES))
        for name, requested in limits:
            if not hasattr(resource, name):
                continue
            kind = getattr(resource, name)
            _, hard = resource.getrlimit(kind)
            bounded = requested if hard == resource.RLIM_INFINITY else min(requested, hard)
            resource.setrlimit(kind, (bounded, bounded))

    return apply_limits


def git_timeout() -> float | None:
    remaining = CHECK_DEADLINE - time.monotonic()
    return min(120, remaining) if remaining > 0 else None


def git_stdio(capture_output: bool) -> tuple[Any, Any]:
    if capture_output:
        return subprocess.PIPE, subprocess.PIPE
    return subprocess.DEVNULL, subprocess.DEVNULL


def run_git(repo: Path, *arguments: str, capture_output: bool = True) -> subprocess.CompletedProcess[bytes]:
    command = ["git", "-C", str(repo), *arguments]
    timeout = git_timeout()
    if timeout is None:
        return failed_git(command, 124, "total checker deadline exceeded")
    stdout, stderr = git_stdio(capture_output)
    try:
        return subprocess.run(
            command,
            stdout=stdout,
            stderr=stderr,
            timeout=timeout,
            check=False,
            preexec_fn=child_resource_limits(),
        )
    except subprocess.TimeoutExpired:
        return failed_git(command, 124, "Git command timed out")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return failed_git(command, 127, f"Git could not start: {error}")


def drain_bounded(stream: Any, captured: bytearray) -> None:
    try:
        while chunk := stream.read(8_192):
            remaining = MAX_GIT_DIAGNOSTIC_BYTES - len(captured)
            if remaining > 0:
                captured.extend(chunk[:remaining])
    except (OSError, ValueError):
        return


def process_group_options() -> dict[str, Any]:
    if os.name == "posix":
        return {"start_new_session": True}
    if os.name == "nt":
        return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    return {}


def kill_process_tree(process: subprocess.Popen[bytes]) -> None:
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        return


def wait_for_process(process: subprocess.Popen[bytes], timeout: float) -> int:
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_process_tree(process)
        process.wait()
        return 124


def run_git_with_diagnostic(repo: Path, *arguments: str) -> subprocess.CompletedProcess[bytes]:
    command = ["git", "-C", str(repo), *arguments]
    timeout = git_timeout()
    if timeout is None:
        return failed_git(command, 124, "total checker deadline exceeded")
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            preexec_fn=child_resource_limits(),
            **process_group_options(),
        )
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return failed_git(command, 127, f"Git could not start: {error}")
    captured = bytearray()
    reader = threading.Thread(target=drain_bounded, args=(process.stderr, captured), daemon=True)
    reader.start()
    returncode = wait_for_process(process, timeout)
    reader.join(timeout=1)
    return subprocess.CompletedProcess(command, returncode, b"", bytes(captured))


def git_diagnostic(completed: subprocess.CompletedProcess[bytes]) -> str:
    lines = (completed.stderr or b"").decode("utf-8", "replace").splitlines()
    message = " | ".join(lines) if lines else "Git returned no diagnostic"
    message = re.sub(r"(://)[^/@\s]+@", r"\1[redacted]@", message)
    return "".join(character if character.isprintable() else "?" for character in message)[:240]


def fetch_commit(repo: Path, url: str, revision: str) -> tuple[str | None, str]:
    fetched = run_git_with_diagnostic(
        repo,
        "fetch",
        "--quiet",
        "--no-tags",
        "--filter=blob:none",
        "--",
        url,
        revision,
    )
    if fetched.returncode != 0:
        return None, git_diagnostic(fetched)
    resolved = run_git(repo, "rev-parse", "--verify", "FETCH_HEAD^{commit}")
    if resolved.returncode != 0:
        return None, git_diagnostic(resolved)
    return resolved.stdout.decode("ascii").strip(), ""


def changed_paths(repo: Path, revisions: tuple[str, str], paths: list[str] | None) -> list[str] | None:
    baseline, head = revisions
    arguments = ["diff", "--name-only", "--no-renames", "-z", baseline, head, "--"]
    if paths:
        arguments.extend(f":(literal){path}" for path in paths)
    completed = run_git(repo, *arguments)
    if completed.returncode != 0:
        return None
    return [item.decode("utf-8", "replace") for item in completed.stdout.split(b"\0") if item]


def display_path(path: str) -> str:
    visible = "".join(character if character.isalnum() or character in "/._@-" else "?" for character in path)
    return visible[:240]


def source_revisions(repo: Path, source: dict[str, Any]) -> tuple[str, str] | str:
    baseline, diagnostic = fetch_commit(repo, source["url"], source["baseline"])
    if baseline is None:
        return f"unavailable: {source['id']}: could not fetch reviewed baseline ({diagnostic})"
    head, diagnostic = fetch_commit(repo, source["url"], source["ref"])
    if head is None:
        return f"unavailable: {source['id']}: could not fetch tracked ref ({diagnostic})"
    return baseline, head


def history_issue(repo: Path, source_id: str, revisions: tuple[str, str]) -> list[str]:
    baseline, head = revisions
    ancestor = run_git(repo, "merge-base", "--is-ancestor", baseline, head)
    if ancestor.returncode not in (0, 1):
        return [f"unavailable: {source_id}: could not compare Git history"]
    if ancestor.returncode == 1:
        return [f"history-diverged: {source_id}: baseline {baseline}; head {head}; manual review required"]
    return []


def drift_report(source_id: str, revisions: tuple[str, str], changes: list[str]) -> list[str]:
    baseline, head = revisions
    report = [f"drift: {source_id}: baseline {baseline}; head {head}"]
    report.extend(f"  changed: {display_path(path)}" for path in changes[:MAX_CHANGED_PATHS])
    if len(changes) > MAX_CHANGED_PATHS:
        report.append(f"  changed: ... {len(changes) - MAX_CHANGED_PATHS} more path(s) omitted")
    return report


def inspect_source(repo: Path, source: dict[str, Any]) -> list[str]:
    revisions = source_revisions(repo, source)
    if isinstance(revisions, str):
        return [revisions]
    issues = history_issue(repo, source["id"], revisions)
    if issues:
        return issues
    changes = changed_paths(repo, revisions, source.get("paths"))
    if changes is None:
        return [f"unavailable: {source['id']}: could not diff reviewed content"]
    return drift_report(source["id"], revisions, changes) if changes else []


def check_source(source: dict[str, Any]) -> list[str]:
    with tempfile.TemporaryDirectory(prefix="upstream-drift-") as directory:
        repo = Path(directory)
        initialized = run_git(repo, "init", "--quiet")
        if initialized.returncode != 0:
            return [f"unavailable: {source['id']}: could not initialize isolated Git repository"]
        return inspect_source(repo, source)


def configure_deadline(seconds: float) -> bool:
    global CHECK_DEADLINE
    if not math.isfinite(seconds) or seconds <= 0:
        print("deadline-seconds must be positive", file=sys.stderr)
        return False
    CHECK_DEADLINE = time.monotonic() + seconds
    return True


def main() -> int:
    arguments = parse_args()
    if not configure_deadline(arguments.deadline_seconds):
        return 2
    registry_path = Path(arguments.registry)
    repository_root = resolve_repository_root(registry_path, arguments.repository_root)
    registry, errors = load_registry(registry_path, repository_root)
    if errors:
        print("invalid registry:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 2
    failures = []
    for source in registry["sources"]:
        failures.extend(check_source(source))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
