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
# A four-source manifest over a four-source release stays valid offline; an unknown source does not.
home="$tmp/stale/home"
release_id="$(printf '%064d' 0)"
release="$home/releases/$release_id"
mkdir -p "$release/sources/taste/skills/soft" "$release/sources/references/design-md/acme" \
  "$release/sources/impeccable/.agent/skills/impeccable" "$release/sources/three" \
  "$release/.agents/skills/taste" "$release/.agent/skills/impeccable"
printf -- '---\nname: soft\ndescription: Soft style\n---\nSoft\n' > "$release/sources/taste/skills/soft/SKILL.md"
printf '# Acme\n' > "$release/sources/references/design-md/acme/DESIGN.md"
printf 'Impeccable\n' > "$release/sources/impeccable/.agent/skills/impeccable/SKILL.md"
printf 'Three\n' > "$release/sources/three/SKILL.md"
printf 'Taste\n' > "$release/.agents/skills/taste/SKILL.md"
printf 'Impeccable\n' > "$release/.agent/skills/impeccable/SKILL.md"
for source in taste impeccable references three; do
  git -C "$release/sources/$source" init -q
  git -C "$release/sources/$source" add .
  git -C "$release/sources/$source" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
done
export DESIGN_STACK_HOME="$home" DESIGN_STACK_RELEASE_ID="$release_id"
write_manifest() {
  "$TEST_PYTHON" - "$1" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

home = Path(os.environ["DESIGN_STACK_HOME"])
release = home / "releases" / os.environ["DESIGN_STACK_RELEASE_ID"]
sources = {name: subprocess.check_output(
    ["git", "-C", str(release / "sources" / name), "rev-parse", "HEAD"], text=True).strip()
    for name in ("taste", "impeccable", "references", "three")}
if sys.argv[1] == "unknown":
    sources["bogus"] = "0" * 40
(home / "manifest.json").write_text(json.dumps({"schema_version": 1, "current": release.name,
    "catalog_path": str(release / "sources"), "sources": sources}))
PY
}
CLI="$repo/.agents/skills/design-stack/scripts/design_stack.py"
write_manifest four
out="$("$TEST_PYTHON" "$CLI" status 2>&1)"; code=$?
assert_eq 0 "$code" "status accepts a four-source manifest: $out"
assert_eq "Ready $release_id (offline; update adds: hyperframes)" "$out" "status names the source update adds"
out="$("$TEST_PYTHON" "$CLI" catalog 2>&1)"; code=$?
assert_eq 0 "$code" "catalog reads a four-source release offline: $out"
assert_contains "$out" 'impeccable:impeccable' "four-source catalog lists the installed sources"
assert_not_contains "$out" 'hyperframes:' "four-source catalog has no hyperframes entry"
write_manifest unknown
out="$("$TEST_PYTHON" "$CLI" status 2>&1)"; code=$?
assert_eq 1 "$code" "status refuses a manifest naming an unknown source"
assert_contains "$out" 'unsupported design-stack manifest' "unknown source is named an unsupported manifest"

# ---------------------------------------------------------------- § docs
DS="$repo/.agents/skills/design-stack/SKILL.md"
BUILD="$repo/.agents/skills/build/SKILL.md"
assert_file_contains "$DS" 'sources/hyperframes/skills/*/SKILL.md' 'skill names the HyperFrames skill source path'
assert_file_contains "$DS" 'A `hyperframes:` ID is a tool' 'skill states the hyperframes: tool rule'
assert_file_contains "$DS" 'npx hyperframes@' 'skill names the pinned CLI invocation'
assert_file_contains "$DS" 'hyperframes check' 'skill names the check gate command'
assert_file_contains "$DS" 'prototype' 'skill names the prototype label'
assert_file_contains "$BUILD" 'design-stack video guard' 'build names the video guard'
assert_file_contains "$BUILD" 'design-stack 3D guard' 'build still names the 3D guard'
"$TEST_PYTHON" "$repo/scripts/render-skills-table.py" --repo "$repo" --check > /dev/null 2>&1; code=$?
assert_eq 0 "$code" 'README skills table is current'

finish
