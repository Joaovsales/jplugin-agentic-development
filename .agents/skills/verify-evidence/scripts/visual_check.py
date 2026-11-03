"""Run a committed project visual check and validate its local browser evidence."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys


PNG = b"\x89PNG\r\n\x1a\n"


def capture(output, name, viewport):
    path = (output / name).resolve()
    if not path.is_relative_to(output.resolve()) or not path.is_file():
        raise ValueError(f"missing or external capture: {name}")
    if path.stat().st_size < 36:
        raise ValueError(f"capture is truncated: {name}")
    with path.open("rb") as stream:
        header = stream.read(24)
        stream.seek(-12, 2)
        trailer = stream.read(12)
    if header[:8] != PNG or header[12:16] != b"IHDR" or trailer[4:8] != b"IEND":
        raise ValueError(f"capture is not a complete PNG: {name}")
    width, height = struct.unpack("!II", header[16:24])
    if height < 320 or (viewport == "desktop" and width < 768) or (
            viewport == "mobile" and not 240 <= width <= 600):
        raise ValueError(f"capture has wrong {viewport} viewport: {name}")


def validate_manifest(output, manifest, changed_states):
    states = manifest.get("states", {})
    if not changed_states:
        raise ValueError("visual check reported no states")
    for state in changed_states:
        evidence = states.get(state)
        if not isinstance(evidence, dict):
            raise ValueError(f"missing changed UI state: {state}")
        for viewport in ("desktop", "mobile"):
            capture(output, evidence.get(viewport, ""), viewport)
        if evidence.get("interactions") is not True or evidence.get("console_errors") != []:
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
    env = {**os.environ, "JPLUGIN_UI_OUTPUT": str(output)}
    subprocess.run([str(project / script)], cwd=project, env=env, check=True, timeout=300)
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    return validate_manifest(output, manifest, changed_states)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("validate",))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((args.output / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(args.output, manifest, list(manifest.get("states", {})))
    return 0


if __name__ == "__main__":
    sys.exit(main())
