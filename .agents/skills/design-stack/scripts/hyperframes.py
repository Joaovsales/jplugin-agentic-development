"""Small opt-in, completion and version guard for the installed HyperFrames video pipeline."""

import json
import re
from pathlib import Path

_TERM = r"(?:video|mp4|motion graphics|explainer|render)"


def _asks_for_video(text):
    """An explicit video, MP4, motion-graphics, explainer or render request; a negation just before it cancels."""
    requested = bool(re.search(rf"\b{_TERM}\b", text, re.IGNORECASE))
    negated = re.search(rf"\b(remove|disable|avoid|no|without|drop)\b.{{0,20}}\b{_TERM}\b", text, re.IGNORECASE)
    return requested and not negated


def should_run_hyperframes(task, brief_motion):
    """Only an explicit video request in the task or the Motion rule opts in; UI easing never does."""
    return _asks_for_video(task) or _asks_for_video(brief_motion)


def production_status(gates):
    """An incomplete check or render stage stays visibly a prototype."""
    required = ("check", "render")
    open_gates = [name for name in required if gates.get(name) is not True]
    return {"label": "prototype" if open_gates else "production",
            "open_gates": open_gates}


def cli_version(release):
    """The HyperFrames CLI version the release pins; a broken release is an error, not a default."""
    package = Path(release) / "sources" / "hyperframes" / "packages" / "cli" / "package.json"
    try:
        version = json.loads(package.read_text(encoding="utf-8")).get("version")
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"hyperframes CLI package.json unreadable at {package}") from error
    if not isinstance(version, str) or not version:
        raise ValueError(f"hyperframes CLI package.json has no version at {package}")
    return version
