"""Small opt-in and completion guard for the installed img2threejs pipeline."""

import re


def should_run_three(task, brief_intent):
    """Only explicit task or positive brief intent opts into 3D generation."""
    requested = bool(re.search(r"\b3d\b|\bthree[-.]?js\b", task, re.IGNORECASE))
    requested = requested and not bool(re.search(r"\b(remove|disable|avoid|no)\b.{0,20}\b3d\b", task, re.IGNORECASE))
    intent = brief_intent.strip().lower()
    excluded = intent in {"none", "no 3d intent.", "no 3d intent"} or "do not use 3d" in intent
    return requested or (bool(intent) and not excluded)


def production_status(gates):
    """An incomplete strict spec or forge stage stays visibly a prototype."""
    required = ("strict_spec", "forge")
    open_gates = [name for name in required if gates.get(name) is not True]
    return {"label": "prototype" if open_gates else "production",
            "open_gates": open_gates}
