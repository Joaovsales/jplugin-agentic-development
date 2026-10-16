#!/bin/bash
. "$(dirname "$0")/lib.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
export DESIGN_STACK_REPO="$repo"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------- § guard
mkdir -p "$tmp/release/sources/hyperframes/packages/cli"
printf '{"name": "hyperframes", "version": "1.2.3"}\n' > "$tmp/release/sources/hyperframes/packages/cli/package.json"
mkdir -p "$tmp/broken/sources/hyperframes/packages/cli"
printf '{"name": "hyperframes"}\n' > "$tmp/broken/sources/hyperframes/packages/cli/package.json"
export VIDEO_RELEASE="$tmp/release" VIDEO_BROKEN="$tmp/broken" VIDEO_MISSING="$tmp/missing"
out="$("$TEST_PYTHON" - <<'PY' 2>&1
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/design-stack/scripts"))
from hyperframes import cli_version, production_status, should_run_hyperframes

assert should_run_hyperframes("Render a 30s product launch video", "")
assert should_run_hyperframes("Export an MP4 of the intro", "")
assert should_run_hyperframes("Improve layout", "Render a 15s MP4 for the hero.")
assert not should_run_hyperframes("Smooth the hover transition", "Ease-out 200ms on hover")
assert not should_run_hyperframes("Improve layout", "Ease-out 200ms on hover transition")
assert not should_run_hyperframes("Remove the video hero", "")
assert not should_run_hyperframes("No video on this page", "")
assert production_status({"check": True, "render": False})["label"] == "prototype"
assert production_status({"check": False, "render": True})["label"] == "prototype"
assert production_status({"check": True, "render": True})["label"] == "production"
assert production_status({"check": False, "render": False})["open_gates"] == ["check", "render"]
assert cli_version(os.environ["VIDEO_RELEASE"]) == "1.2.3"
assert cli_version(Path(os.environ["VIDEO_RELEASE"])) == "1.2.3"
for bad in (os.environ["VIDEO_BROKEN"], os.environ["VIDEO_MISSING"]):
    try:
        cli_version(bad)
    except ValueError as error:
        assert "hyperframes" in str(error)
    else:
        raise AssertionError("cli_version must raise on a broken release")
print("video opt-in, production gates and CLI pin passed")
PY
)"; code=$?
assert_eq 0 "$code" "$out"

# ---------------------------------------------------------------- § stale-manifest
# (appended by a later slice)

# ---------------------------------------------------------------- § docs
# (appended by a later slice)

finish
