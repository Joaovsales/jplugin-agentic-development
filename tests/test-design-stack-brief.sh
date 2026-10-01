#!/bin/bash
# A project brief remains authored project data across shared source updates.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
export DESIGN_STACK_REPO="$REPO" DESIGN_STACK_FIXTURE="$box"

printf '\n--- stable project brief ---\n'
out="$("$TEST_PYTHON" - <<'PY' 2>&1
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys

root = Path(os.environ["DESIGN_STACK_FIXTURE"])
sys.path.insert(0, str(Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/design-stack/scripts"))
from brief import create_brief, read_brief, refresh_brief
import design_stack

path = root / "project/DESIGN.md"
choice = {"direction": "spatial", "references": [], "custom_brief": ""}
create_brief(path, choice)
initial = path.read_bytes()
brief = read_brief(path)
assert brief["version"] == 1 and brief["direction"] == "spatial"
assert all(brief["rules"][name].strip() for name in
           ("palette", "typography", "layout", "motion", "accessibility"))
assert "3d intent" in brief["rules"]

design_stack.HOME = root / "shared"
old = {"schema_version": 1, "sources": {"taste": "old"}, "current": "old"}
design_stack.current_manifest = lambda: old
design_stack.stage_release = lambda stage: {"taste": "new"}
design_stack.install_skills = lambda stage: None
design_stack.validate = lambda stage: None
design_stack.build_catalog = lambda stage, revisions: []
design_stack.promote = lambda stage, revisions: {"current": "new"}
sys.argv = ["design_stack.py", "update"]
with contextlib.redirect_stdout(io.StringIO()):
    assert design_stack.main() == 0
assert path.read_bytes() == initial, "shared update changed the approved project brief"

for attempt in (
    lambda: create_brief(path, choice),
    lambda: refresh_brief(path, choice, {"palette": "Ink and ivory"}),
):
    try:
        attempt()
    except ValueError:
        pass
    else:
        raise AssertionError("an unapproved write changed the brief")
assert path.read_bytes() == initial

refresh_brief(path, choice, {"palette": "Ink and ivory", "typography": "Serif headings",
                            "layout": "Editorial split", "motion": "Subtle transitions"},
              owner_choice=True)
after = read_brief(path)
assert after["rules"]["palette"] == "Ink and ivory"
assert after["rules"]["typography"] == "Serif headings"
assert after["rules"]["layout"] == "Editorial split"
assert after["rules"]["motion"] == "Subtle transitions"
assert after["rules"]["accessibility"] == brief["rules"]["accessibility"]
assert after["version"] == 1
approved = path.read_bytes()
design_stack.select_direction = lambda *args: choice
sys.argv = ["design_stack.py", "refresh", "--project", str(path.parent),
            "--direction", "spatial"]
rejected = io.StringIO()
with contextlib.redirect_stderr(rejected):
    assert design_stack.main() == 1
assert "SelectionRejected:" in rejected.getvalue(), rejected.getvalue()
assert path.read_bytes() == approved, "refresh without owner choice altered approved brief"
for invalid in (["Palette=wrong"], ["palette=first", "palette=second"],
                ["unknown=wrong"]):
    sys.argv = ["design_stack.py", "refresh", "--project", str(path.parent),
                "--direction", "spatial", "--owner-choice"]
    for rule in invalid:
        sys.argv.extend(("--rule", rule))
    with contextlib.redirect_stderr(io.StringIO()):
        assert design_stack.main() == 1
    assert path.read_bytes() == approved, "invalid rule altered approved brief"
design_stack.current_manifest = lambda: None
sys.argv = ["design_stack.py", "select", "--direction", "spatial"]
missing = io.StringIO()
with contextlib.redirect_stderr(missing):
    assert design_stack.main() == 1
assert "SetupRequired:" in missing.getvalue(), missing.getvalue()
path.write_bytes(approved + b"\n## Palette\nDuplicate.\n")
try:
    read_brief(path)
except ValueError as error:
    assert "duplicate" in str(error)
else:
    raise AssertionError("duplicate visual rule section was accepted")
path.write_bytes(approved)
reader = Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/design-stack/scripts/design_stack.py"
output = subprocess.check_output([sys.executable, str(reader), "read-brief", "--project",
                                  str(path.parent)], text=True)
assert '"version": 1' in output and '"direction": "spatial"' in output
try:
    create_brief(root / "other/DESIGN.md", {"direction": "custom", "references": []})
except ValueError as error:
    assert "owner-authored" in str(error)
else:
    raise AssertionError("non-spatial brief accepted spatial defaults")
print("brief stable across update; refresh requires owner choice")
PY
)"; status=$?
assert_eq 0 "$status" "brief lifecycle"
assert_contains "$out" "brief stable across update" "brief lifecycle evidence"
finish
