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
from e2e_evidence import check as check_e2e
from ui_publication import append_ui_entry, artifact_review_link, install_workflow, validate_artifact
import ui_publication

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
workflow = install_workflow(project)
content = workflow.read_text()
assert "pull_request:" in content and "actions/upload-artifact@v4" in content
assert "retention-days: 30" in content and "head.sha" in content
assert "tests/visual/*.sh" in content
assert install_workflow(project).read_bytes() == workflow.read_bytes()
run = {"id": 42, "head_sha": "a" * 40, "conclusion": "success", "event": "pull_request"}
artifact = {"id": 7, "name": "jplugin-ui-pr-12-" + "a" * 40,
            "expired": False, "size_in_bytes": 1024,
            "created_at": "2026-10-01T00:00:00Z", "expires_at": "2026-10-31T00:00:00Z"}
assert validate_artifact(run, artifact, "a" * 40, 12)
assert artifact_review_link("owner/repo", run, artifact).endswith("/actions/runs/42/artifacts/7")
ui_publication.github_api = lambda path: ({"workflow_runs": [run]} if path.endswith("per_page=100")
                                      else {"artifacts": [artifact]})
assert ui_publication.lookup_ci_artifact("owner/repo", 12, "a" * 40).endswith("/artifacts/7")
for bad in ({"expired": True}, {"size_in_bytes": 0}, {"expires_at": "2026-10-02T00:00:00Z"}):
    broken = {**artifact, **bad}
    try:
        validate_artifact(run, broken, "a" * 40, 12)
    except ValueError:
        pass
    else:
        raise AssertionError("invalid CI artifact was accepted")
log = project / "tasks/e2e-log.md"
append_ui_entry(log, "feature", "a" * 40, "home", root / "captures", "review/link", "pass")
append_ui_entry(log, "feature", "a" * 40, "home", root / "captures", "review/link", "pass")
assert log.read_text().count("## E2E Walkthrough") == 2
assert "Screenshot:" in log.read_text() and "Mobile Screenshot:" in log.read_text()
assert "Review Link: review/link" in log.read_text()
assert check_e2e(log, ["a" * 12], project) == 0
(root / "captures/mobile.png").unlink()
assert check_e2e(log, ["a" * 12], project) == 1
print("append-only visual log and 30-day CI artifact contract passed")
PY
)"; code=$?
assert_eq 0 "$code" "$out"
assert_file_contains "$repo/.agents/skills/verify-evidence/SKILL.md" 'run_visual_check' 'visual check in verifier contract'
assert_file_contains "$repo/.agents/skills/wrap-up-session/SKILL.md" 'PublicationUnavailable' 'UI closure blocks missing publication'
finish
