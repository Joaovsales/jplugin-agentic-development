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

# frontmatter <file> — the leading `---`-fenced block, so a token appearing
# later in the body cannot satisfy a frontmatter assertion.
frontmatter() { awk 'NR==1 && $0=="---"{f=1;next} f&&$0=="---"{exit} f' "$1"; }

# field <frontmatter> <key> — one scalar value, CR-stripped.
field() { printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | tr -d '\r'; }

# --- 1. The shared contract, for every runbook -------------------------------
# A runbook added later inherits the contract without a test edit; a runbook
# that drifts from it fails here rather than being silently mis-routed.
RUNBOOKS="$(ls .claude/browsers/*.md 2>/dev/null)"
assert_contains "$RUNBOOKS" ".claude/browsers/lightpanda.md" "runbooks: lightpanda.md exists"
assert_contains "$RUNBOOKS" ".claude/browsers/playwright-cli.md" "runbooks: playwright-cli.md exists"

for book in $RUNBOOKS; do
  fm="$(frontmatter "$book")"
  assert_not_contains "$fm" "PLACEHOLDER" "$book: no placeholder values"
  for key in name display_name fidelity screenshot detect_command platforms license; do
    assert_contains "$fm" "$key:" "$book: declares $key"
  done

  # `name` must match the filename stem — it is the stable key a skill resolves
  # the adapter by, mirroring the .claude/deployments/ contract.
  assert_eq "$(basename "$book" .md)" "$(field "$fm" name)" "$book: name matches filename stem"

  # `fidelity` is the field the classifier gates on. Anything outside the
  # enumeration would route ACs by an unrecognised value.
  case "$(field "$fm" fidelity)" in
    dom|full) assert_eq "valid" "valid" "$book: fidelity is dom|full" ;;
    *)        assert_eq "valid" "invalid: '$(field "$fm" fidelity)'" "$book: fidelity is dom|full" ;;
  esac

  # `screenshot` says whether a VISUAL PASS can have its PNG on disk: only
  # `file` can. `session` (an id in the harness) and `none` cannot.
  case "$(field "$fm" screenshot)" in
    file|session|none) assert_eq "valid" "valid" "$book: screenshot is file|session|none" ;;
    *)                 assert_eq "valid" "invalid: '$(field "$fm" screenshot)'" "$book: screenshot is file|session|none" ;;
  esac
done

# --- 2. Lightpanda: the DOM tier ---------------------------------------------
RUNBOOK=".claude/browsers/lightpanda.md"
FRONTMATTER="$(frontmatter "$RUNBOOK")"
FIDELITY="$(field "$FRONTMATTER" fidelity)"
assert_contains "$FRONTMATTER" "mcp_command:" "frontmatter: lightpanda declares mcp_command"
assert_eq "none" "$(field "$FRONTMATTER" screenshot)" "frontmatter: lightpanda cannot screenshot"

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

# --- 7. Playwright CLI: the first-choice, file-capable full tier --------------
# specs/visual-e2e-evidence.md AC 2. It is the only backend whose screenshot is
# a file, so it is the only one a VISUAL PASS can rest on.
PW=".claude/browsers/playwright-cli.md"
PW_FM="$(frontmatter "$PW")"
assert_eq "full" "$(field "$PW_FM" fidelity)" "playwright-cli: fidelity full"
assert_eq "file" "$(field "$PW_FM" screenshot)" "playwright-cli: screenshot file"
assert_contains "$PW_FM" 'detect_command: "command -v playwright-cli"' \
  "playwright-cli: detected on PATH, not by MCP tools"
# 0.x — the command surface can change between releases (Decision 8).
# The frontmatter is the pin's only source: install.sh reads it, the body refers to it.
PW_PIN="$(field "$PW_FM" pinned_version | tr -d '"')"
assert_eq "semver" "$(printf %s "$PW_PIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && echo semver || echo "not-semver")" "playwright-cli: pinned to an exact semver"
assert_eq "1" "$(grep -cF "$PW_PIN" "$PW")" "playwright-cli: the version literal appears once, in the frontmatter"
assert_not_contains "$PW_FM" "mcp_command:" "playwright-cli: registers no MCP server (Decision 4)"

# The command crib: every step a walkthrough needs, spelled as the CLI spells it.
for cmd in open goto click fill eval console screenshot close; do
  assert_file_matches "$PW" "playwright-cli $cmd( |\$|\`)" "playwright-cli: crib gives the $cmd command"
done
assert_file_contains "$PW" "--filename=tasks/e2e-artifacts/" \
  "playwright-cli: the screenshot lands where the evidence check looks"
# A missing Chromium must be named, not fallen back from (spec § Edge Cases).
assert_file_contains "$PW" "playwright-cli install-browser chromium" \
  "playwright-cli: names the missing-Chromium remedy"
assert_file_contains "$PW" "@playwright/mcp" "playwright-cli: says why not the MCP server"

finish
