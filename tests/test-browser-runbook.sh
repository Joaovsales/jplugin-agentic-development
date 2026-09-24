#!/bin/bash
# tests/test-browser-runbook.sh — the browser-adapter runbook contract.
#
# WHY THIS EXISTS
#
# `/verify-evidence --scope e2e` may resolve to lightpanda, a headless browser that
# executes JavaScript over a real network but has NO rendering path: no
# screenshots, no Canvas/WebGL, partial CSS layout. A page whose layout is
# broken can still expose a correct DOM, so a reviewer who does not know the
# ceiling will read a PASS as "the feature works" when it means "the DOM was
# right and nobody looked".
#
# The runbook is where that ceiling is written down. This test pins the
# frontmatter contract that makes the file machine-readable, and pins the body
# tokens that stop the ceiling being quietly dropped in a later edit. A ceiling
# documented once and deleted later is worse than never documented, because the
# skill still routes ACs to the tier on the strength of a file that no longer
# warns about it.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

RUNBOOK=".claude/browsers/lightpanda.md"

# --- 1. The file exists at the contracted location ---------------------------
if [ -f "$RUNBOOK" ]; then
  assert_eq "present" "present" "runbook: $RUNBOOK exists"
else
  assert_eq "present" "absent" "runbook: $RUNBOOK exists"
  finish
fi

# --- 2. Frontmatter contract -------------------------------------------------
# Extract the leading `---`-fenced block so a token appearing later in the body
# cannot satisfy a frontmatter assertion.
FRONTMATTER="$(awk 'NR==1 && $0=="---"{f=1;next} f&&$0=="---"{exit} f' "$RUNBOOK")"

assert_not_contains "$FRONTMATTER" "PLACEHOLDER" "frontmatter: no placeholder values"

for field in name display_name fidelity detect_command mcp_command platforms license; do
  assert_contains "$FRONTMATTER" "$field:" "frontmatter: declares $field"
done

# `name` must match the filename stem — it is the stable key a skill resolves
# the adapter by, mirroring the .claude/deployments/ contract.
assert_contains "$FRONTMATTER" "name: lightpanda" "frontmatter: name matches filename stem"

# `fidelity` is the field the classifier gates on. Anything outside the
# enumeration would route ACs by an unrecognised value.
FIDELITY="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^fidelity:[[:space:]]*//p' | tr -d '\r')"
case "$FIDELITY" in
  dom|full) assert_eq "valid" "valid" "frontmatter: fidelity is dom|full (got '$FIDELITY')" ;;
  *)        assert_eq "valid" "invalid: '$FIDELITY'" "frontmatter: fidelity is dom|full" ;;
esac

# Lightpanda specifically is the DOM tier. A future edit flipping this to `full`
# would silently make every VISUAL AC eligible for a browser that cannot render.
assert_eq "dom" "$FIDELITY" "frontmatter: lightpanda is the dom tier, not full"

# --- 3. The capability ceiling survives later edits --------------------------
# Each token below is a capability the browser does NOT have. Losing any one of
# them from the runbook is losing the warning that justifies the fail-closed
# classifier.
assert_file_contains "$RUNBOOK" "screenshot"     "ceiling: names the screenshot gap"
assert_file_contains "$RUNBOOK" "Canvas"         "ceiling: names the Canvas/WebGL gap"
assert_file_contains "$RUNBOOK" "Flexbox"        "ceiling: names the partial CSS layout gap"
assert_file_contains "$RUNBOOK" "Service Worker" "ceiling: names the Service Worker gap"
assert_file_contains "$RUNBOOK" "WebSocket"      "ceiling: names the limited WebSocket support"

# --- 4. Operational facts a reader cannot derive from the frontmatter --------
assert_file_contains "$RUNBOOK" "AGPL-3.0" "licensing: names the licence"
assert_prose_contains "$RUNBOOK" "unmodified upstream" \
  "licensing: states the unmodified-binary constraint"

# No Windows binary is published. A reader on Windows must be told to reach for
# WSL2 or Docker rather than concluding the tool is broken.
assert_file_contains "$RUNBOOK" "Windows" "platform: addresses the Windows gap"
assert_file_matches  "$RUNBOOK" "WSL2|Docker" "platform: offers the Windows workaround"

# The release is pinned, not tracked. `nightly` on a beta project changes
# unattended-run behaviour without a commit.
assert_file_matches "$RUNBOOK" "0\.3\.6" "pinning: names an explicit release tag"

# Registration is documented here because install.sh deliberately does not do it.
assert_file_contains "$RUNBOOK" "lightpanda mcp" "registration: documents the MCP one-liner"

# --- 5. platforms list excludes Windows, matching reality --------------------
# The frontmatter must not claim a platform upstream does not ship, or a harness
# reading this contract would try to resolve a binary that does not exist.
PLATFORMS="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^platforms:[[:space:]]*//p')"
assert_not_contains "$PLATFORMS" "windows" "frontmatter: platforms omits windows (no upstream build)"

# --- 6. Stubbed geometry is the ceiling's sharpest edge -----------------------
# getBoundingClientRect() does not throw here — it returns synthetic values
# (every element 5x5, x==y) that ignore CSS entirely. A missing API would be
# caught by its caller; a stubbed one silently answers wrong, so the defensive
# `r.width > 0 && r.x >= 0` visibility check passes for an off-screen element.
# That is the specific reason VISUAL criteria are refused rather than attempted,
# so losing this warning removes the justification for the whole fail-closed
# design while leaving the design in place.
assert_file_contains "$RUNBOOK" "getBoundingClientRect" \
  "ceiling: warns that geometry APIs are stubbed, not absent"
assert_prose_contains "$RUNBOOK" "stubbed" \
  "ceiling: names the stubbed-not-missing distinction"

finish
