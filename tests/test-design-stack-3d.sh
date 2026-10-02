#!/bin/bash
. "$(dirname "$0")/lib.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
export DESIGN_STACK_REPO="$repo"
out="$("$TEST_PYTHON" - <<'PY' 2>&1
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/design-stack/scripts"))
from three import production_status, should_run_three

assert not should_run_three("Improve layout", "No 3D intent.")
assert not should_run_three("Improve layout", "Do not use 3D in this project.")
assert not should_run_three("Remove the 3D view", "No 3D intent.")
assert should_run_three("Build a 3D product view", "No 3D intent.")
assert should_run_three("Improve layout", "Use 3D for the hero model.")
assert production_status({"strict_spec": False, "forge": True})["label"] == "prototype"
assert production_status({"strict_spec": True, "forge": False})["label"] == "prototype"
assert production_status({"strict_spec": True, "forge": True})["label"] == "production"
assert production_status({"strict_spec": False, "forge": False})["open_gates"] == ["strict_spec", "forge"]
print("3D trigger and strict production gates passed")
PY
)"; code=$?
assert_eq 0 "$code" "$out"
assert_file_contains "$repo/.agents/skills/design-stack/SKILL.md" 'validate_sculpt_spec.py' 'strict upstream sculpt gate'
assert_file_contains "$repo/.agents/skills/build/SKILL.md" 'prototype' 'build preserves incomplete label'
finish
