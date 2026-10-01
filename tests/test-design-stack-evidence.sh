#!/bin/bash
. "$(dirname "$0")/lib.sh"
repo="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
export DESIGN_STACK_REPO="$repo" DESIGN_STACK_FIXTURE="$box"
out="$("$TEST_PYTHON" - <<'PY' 2>&1
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(os.environ["DESIGN_STACK_FIXTURE"])
sys.path.insert(0, str(Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/verify-evidence/scripts"))
from visual_check import validate_manifest, run_visual_check

project = root / "project"
script = project / "tests/visual/feature.sh"
script.parent.mkdir(parents=True)
script.write_text('''#!/bin/sh
set -eu
mkdir -p "$JPLUGIN_UI_OUTPUT"
playwright-cli --version >/dev/null
printf '\\211PNG\\r\\n\\032\\n' > "$JPLUGIN_UI_OUTPUT/desktop.png"
printf '\\211PNG\\r\\n\\032\\n' > "$JPLUGIN_UI_OUTPUT/mobile.png"
cat > "$JPLUGIN_UI_OUTPUT/manifest.json" <<'JSON'
{"states":{"home":{"desktop":"desktop.png","mobile":"mobile.png","interactions":true,"console_errors":[],"visual_disposition":"pass"}}}
JSON
''')
script.chmod(0o755)
subprocess.run(["git", "init", "-q", str(project)], check=True)
subprocess.run(["git", "-C", str(project), "add", "tests/visual/feature.sh"], check=True)
subprocess.run(["git", "-C", str(project), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "visual"], check=True)
bin_dir = root / "bin"
bin_dir.mkdir()
cli = bin_dir / "playwright-cli"
cli.write_text("#!/bin/sh\nexit 0\n")
cli.chmod(0o755)
os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ["PATH"]
result = run_visual_check(project, "feature", ["home"], root / "captures")
assert result["states"]["home"]["visual_disposition"] == "pass"
for changed in ({"console_errors": ["boom"]}, {"interactions": False}, {"visual_disposition": "open"}):
    bad = json.loads((root / "captures/manifest.json").read_text())
    bad["states"]["home"].update(changed)
    try:
        validate_manifest(root / "captures", bad, ["home"])
    except ValueError:
        pass
    else:
        raise AssertionError("failed browser or visual check was accepted")
try:
    validate_manifest(root / "captures", result, ["home", "settings"])
except ValueError:
    pass
else:
    raise AssertionError("changed state without captures was accepted")
print("committed visual check and desktop/mobile evidence passed")
PY
)"; code=$?
assert_eq 0 "$code" "$out"
assert_file_contains "$repo/.agents/skills/verify-evidence/SKILL.md" 'run_visual_check' 'visual check in verifier contract'
finish
