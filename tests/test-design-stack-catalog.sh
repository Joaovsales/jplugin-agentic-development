#!/bin/bash
# Catalog discovery and selection use only the verified local release.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
mkdir -p "$box/sources/taste/skills/soft-skill" \
  "$box/sources/taste/skills/new-style" \
  "$box/sources/references/design-md/example" \
  "$box/sources/references/design-md/new-reference" \
  "$box/.agents/skills/impeccable/scripts" "$box/sources/three" \
  "$box/sources/impeccable/.agent/skills/impeccable"
cat > "$box/sources/taste/skills/soft-skill/SKILL.md" <<'MD'
---
name: soft-ui
description: Soft visual style for wellness and lifestyle interfaces.
---
### A. Layout Archetypes (Pick 1)
1. **The Editorial Split:** Content and imagery side by side.
2. **The Z-Axis Cascade:** Overlapping cards.
MD
cat > "$box/sources/taste/skills/new-style/SKILL.md" <<'MD'
---
name: new-style
description: A new dashboard style for data-heavy products.
---
## Visual Archetypes
### 2.1 Metric Wall
Dense information with strong hierarchy.
MD
printf '# Example\n' > "$box/sources/references/design-md/example/DESIGN.md"
printf '# New reference\n' > "$box/sources/references/design-md/new-reference/DESIGN.md"
printf '# img2threejs\n' > "$box/sources/three/SKILL.md"
printf '# Impeccable\n' > "$box/sources/impeccable/.agent/skills/impeccable/SKILL.md"
cat > "$box/.agents/skills/impeccable/scripts/command-metadata.json" <<'JSON'
{"critique":{"description":"Review an interface"},"polish":{"description":"Refine an interface"}}
JSON

printf '\n--- dynamic catalog and selection ---\n'
export DESIGN_STACK_FIXTURE="$box" DESIGN_STACK_REPO="$REPO"
out="$("$TEST_PYTHON" - <<'PY' 2>&1
import importlib.util
import json
import os
from pathlib import Path
import sys

base = Path(os.environ["DESIGN_STACK_FIXTURE"])
sys.path.insert(0, str(Path(os.environ["DESIGN_STACK_REPO"]) / ".agents/skills/design-stack/scripts"))
from catalog import build_catalog, select_direction

revisions = {key: key + "-sha" for key in ("taste", "impeccable", "references", "three")}
entries = build_catalog(base, revisions)
by_id = {entry["id"]: entry for entry in entries}
assert len(by_id) == len(entries), "catalog IDs must be unique"
for identifier, kind in {
    "spatial": "direction", "custom": "direction",
    "taste:new-style": "direction",
    "taste:soft-skill:the-editorial-split": "archetype",
    "taste:soft-skill:the-z-axis-cascade": "archetype",
    "taste:new-style:metric-wall": "archetype",
    "reference:example": "reference",
    "reference:new-reference": "reference",
    "impeccable:critique": "tool", "impeccable:polish": "tool",
    "three:img2threejs": "tool",
}.items():
    assert by_id[identifier]["kind"] == kind, identifier
assert by_id["taste:new-style"]["source_revision"] == "taste-sha"
(base / "sources/taste/skills/future-style").mkdir()
(base / "sources/taste/skills/future-style/SKILL.md").write_text(
    "---\nname: future-style\n---\n## Visual Archetypes\n### Ribbon Columns\n")
(base / "sources/references/design-md/future").mkdir()
(base / "sources/references/design-md/future/DESIGN.md").write_text("# Future\n")
grown = build_catalog(base, revisions)
assert len(grown) == len(entries) + 3
assert {"taste:future-style", "taste:future-style:ribbon-columns", "reference:future"}.issubset(
    {item["id"] for item in grown})
metadata = base / ".agents/skills/impeccable/scripts/command-metadata.json"
backup = metadata.read_text()
metadata.unlink()
fallback = base / "sources/impeccable/.agent/skills/impeccable/reference"
fallback.mkdir()
(fallback / "critique.md").write_text("# Critique\n")
assert any(item["id"] == "impeccable:critique" for item in build_catalog(base, revisions))
metadata.write_text(backup)
outside = base.parent / "outside-design-reference.md"
outside.write_text("# Outside\n")
(base / "sources/references/design-md/escape").mkdir()
(base / "sources/references/design-md/escape/DESIGN.md").symlink_to(outside)
try:
    build_catalog(base, revisions)
except ValueError as error:
    assert "leaves the verified release" in str(error)
else:
    raise AssertionError("external reference path was accepted")
(base / "sources/references/design-md/escape/DESIGN.md").unlink()
outside.unlink()
selection = select_direction(entries, "taste:new-style", ["reference:example"],
                             custom_brief="Keep current typography", use_case="dashboard")
assert selection["direction"] == "taste:new-style"
assert selection["references"] == ["reference:example"]
assert selection["custom_brief"] == "Keep current typography"
assert select_direction(entries, "custom", [], custom_brief="A bespoke palette")["direction"] == "custom"
assert select_direction(entries, "taste:soft-skill:the-editorial-split", [])["direction"].startswith("taste:")
for direction in ("impeccable:critique", "reference:example", "missing"):
    try:
        select_direction(entries, direction, [])
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid primary direction accepted: {direction}")
try:
    select_direction(entries, "taste:soft-skill", [], use_case="financial dashboard")
except ValueError as error:
    assert "fit warning" in str(error).lower(), str(error)
else:
    raise AssertionError("unsuitable direction lacked a fit warning")
assert select_direction(entries, "taste:soft-skill", [], use_case="financial dashboard",
                        override_fit=True)["direction"] == "taste:soft-skill"
try:
    select_direction(entries, "custom", ["taste:new-style"])
except ValueError:
    pass
else:
    raise AssertionError("non-reference accepted as reference")
print("catalog and selection passed")
PY
)"; code=$?
assert_eq 0 "$code" "$out"

printf '\n--- offline browsable CLI ---\n'
release_id="$(printf '%064d' 0)"
release="$box/home/releases/$release_id"
mkdir -p "$release" "$release/.agents/skills/taste" \
  "$release/.agent/skills/impeccable" "$box/home"
cp -a "$box/sources" "$release/"
cp -a "$box/.agents/skills/impeccable" "$release/.agents/skills/"
printf 'Taste\n' > "$release/.agents/skills/taste/SKILL.md"
printf 'Impeccable\n' > "$release/.agent/skills/impeccable/SKILL.md"
for source in taste impeccable references three; do
  git -C "$release/sources/$source" init -q
  git -C "$release/sources/$source" add .
  git -C "$release/sources/$source" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
done
export DESIGN_STACK_HOME="$box/home" DESIGN_STACK_RELEASE_ID="$release_id"
"$TEST_PYTHON" - <<'PY'
import json
import os
from pathlib import Path
import subprocess

home = Path(os.environ["DESIGN_STACK_HOME"])
release = home / "releases" / os.environ["DESIGN_STACK_RELEASE_ID"]
sources = {name: subprocess.check_output(
    ["git", "-C", str(release / "sources" / name), "rev-parse", "HEAD"], text=True).strip()
    for name in ("taste", "impeccable", "references", "three")}
(home / "manifest.json").write_text(json.dumps({"schema_version": 1, "current": release.name,
    "catalog_path": str(release / "sources"), "sources": sources}))
PY
export DESIGN_STACK_TASTE_URL="$box/no-network-source"
CLI="$REPO/.agents/skills/design-stack/scripts/design_stack.py"
out="$("$TEST_PYTHON" "$CLI" catalog 2>&1)"; code=$?
assert_eq 0 "$code" "catalog command reads the verified release offline"
assert_contains "$out" 'taste:future-style:ribbon-columns' "new archetype is browsable"
assert_contains "$out" 'reference:future' "new reference is browsable"
assert_contains "$out" 'impeccable:critique' "installed Impeccable command is a tool"
out="$("$TEST_PYTHON" "$CLI" catalog --json 2>&1)"; code=$?
assert_eq 0 "$code" "JSON catalog is available for tooling"
assert_contains "$out" '"source_revision"' "JSON entries carry source revisions"
out="$("$TEST_PYTHON" "$CLI" select --direction taste:new-style \
  --reference reference:future --custom-brief 'Keep current typography' \
  --use-case dashboard 2>&1)"; code=$?
assert_eq 0 "$code" "owner selection accepts one direction, a reference and custom text"
assert_contains "$out" 'Keep current typography' "custom brief is retained"
out="$("$TEST_PYTHON" "$CLI" select --direction taste:soft-skill \
  --use-case 'financial dashboard' 2>&1)"; code=$?
assert_eq 1 "$code" "unsuitable choice shows a fit warning"
assert_contains "$out" 'Fit warning' "warning names the mismatch"
out="$("$TEST_PYTHON" "$CLI" select --direction taste:soft-skill \
  --use-case 'financial dashboard' --override-fit 2>&1)"; code=$?
assert_eq 0 "$code" "owner override accepts the warned choice"
finish
