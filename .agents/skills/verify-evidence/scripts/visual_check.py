"""Run a committed project visual check and validate its local browser evidence."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess


PNG = b"\x89PNG\r\n\x1a\n"


def capture(output, name):
    path = (output / name).resolve()
    if not path.is_relative_to(output.resolve()) or not path.is_file():
        raise ValueError(f"missing or external capture: {name}")
    if path.read_bytes()[:8] != PNG:
        raise ValueError(f"capture is not PNG: {name}")


def validate_manifest(output, manifest, changed_states):
    states = manifest.get("states", {})
    for state in changed_states:
        evidence = states.get(state)
        if not isinstance(evidence, dict):
            raise ValueError(f"missing changed UI state: {state}")
        for viewport in ("desktop", "mobile"):
            capture(output, evidence.get(viewport, ""))
        if evidence.get("interactions") is not True or evidence.get("console_errors"):
            raise ValueError(f"interaction or console failure: {state}")
        if evidence.get("visual_disposition") != "pass":
            raise ValueError(f"unresolved visual defect: {state}")
    return manifest


def run_visual_check(project, feature, changed_states, output):
    project, output = Path(project).resolve(), Path(output).resolve()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", feature):
        raise ValueError("feature must be a safe visual check name")
    script = Path("tests/visual") / f"{feature}.sh"
    if not shutil.which("playwright-cli"):
        raise ValueError("BackendUnavailable: playwright-cli is missing")
    subprocess.run(["git", "cat-file", "-e", f"HEAD:{script}"], cwd=project, check=True)
    subprocess.run(["git", "diff", "--quiet", "HEAD", "--", str(script)], cwd=project, check=True)
    output.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "JPLUGIN_UI_OUTPUT": str(output),
           "JPLUGIN_UI_STATES": json.dumps(changed_states)}
    subprocess.run([str(project / script)], cwd=project, env=env, check=True, timeout=300)
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    return validate_manifest(output, manifest, changed_states)
