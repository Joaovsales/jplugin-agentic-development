"""Small opt-in, completion and version guard for the installed HyperFrames video pipeline."""

import json
import re
from pathlib import Path

_VIDEO = r"(?:video|mp4|motion graphics|explainer (?:video|clip|animation)|hyperframes)"
_NEGATED = r"\b(?:remove|disable|avoid|no|without|drop)\b.{0,20}"


def _mentions(term, text):
    """An explicit mention of `term`; a negation word just before it cancels."""
    requested = bool(re.search(rf"\b{term}\b", text, re.IGNORECASE))
    negated = re.search(rf"{_NEGATED}\b{term}\b", text, re.IGNORECASE)
    return requested and not negated


def should_run_hyperframes(task, brief_motion):
    """Only an explicit video request in the task, or a Motion rule that names HyperFrames, opts in."""
    return _mentions(_VIDEO, task) or _mentions("hyperframes", brief_motion)


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
