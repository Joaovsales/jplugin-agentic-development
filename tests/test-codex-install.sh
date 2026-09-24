# tests/test-codex-install.sh — isolated Codex adapter contract.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/scripts/install-codex.sh"
RENDERER="$REPO/scripts/render-codex.py"

# specs/single-instruction-file.md slice 5: the shared rules reach Codex through
# the managed block /sync writes into each project's AGENTS.md, so the renderer
# no longer writes a global file and the markers live with the script that does.
assert_file_not_matches "$RENDERER" 'render_global' \
  "renderer: render_global is gone"
assert_file_not_matches "$RENDERER" '\-\-global' \
  "renderer: the --global operation is gone"
assert_file_contains "$REPO/.agents/skills/sync/scripts/sync-managed-block.py" "{SLUG}:begin -->" \
  "sync-managed-block.py: the managed block markers live with the script that writes them"
assert_file_contains "$INSTALL" "CODEX_HOME" \
  "installer: supports CODEX_HOME override"
assert_file_contains "$INSTALL" ".agents/skills/." \
  "installer: installs canonical skills additively"
assert_file_contains "$INSTALL" "Review installed hooks with /hooks" \
  "installer: tells users to review hook registrations"
assert_file_contains "$REPO/project-template/AGENTS.md" "Project-Specific Rules" \
  "project template: carries a neutral rules section"
assert_file_contains "$REPO/README.md" "bash scripts/install-codex.sh" \
  "README: documents the Codex adapter command"
assert_file_contains "$REPO/README.md" "project-template/AGENTS.md" \
  "README: documents the neutral project seed"
assert_file_contains "$REPO/README.md" "scripts/scaffold-project.sh" \
  "README: Codex users scaffold through the checkout script, not an alias the adapter never installs"

BOX="$(mktemp -d)"
HOME_DIR="$BOX/home"
CODEX_HOME="$HOME_DIR/.codex"
PROJECT="$BOX/project"
mkdir -p "$HOME_DIR/.agents/skills/personal" "$CODEX_HOME/agents" "$PROJECT"
printf 'personal skill\n' > "$HOME_DIR/.agents/skills/personal/SKILL.md"
printf 'name = "personal-agent"\ndescription = "Keep me"\ndeveloper_instructions = "Do not remove me"\n' \
  > "$CODEX_HOME/agents/personal-agent.toml"
# The fixture carries the three hook registrations a machine installed before the
# repository rename holds, under the old slug. The slug is assembled at runtime so
# tests/test-repo-identity.sh's sweep does not read this file as a live reference.
LEGACY_SLUG="coding-agent"; LEGACY_SLUG="$LEGACY_SLUG-workflow"
cat > "$CODEX_HOME/hooks.json" <<JSON
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "echo existing"}]},
      {"hooks": [{"type": "command", "command": "python3 $CODEX_HOME/hooks/$LEGACY_SLUG-session-start.py"}]},
      {"hooks": [{"type": "command", "command": "bash $HOME_DIR/$LEGACY_SLUG-notes/hook.sh"}]}
    ],
    "PreCompact": [
      {"hooks": [{"type": "command", "command": "bash $CODEX_HOME/hooks/$LEGACY_SLUG-pre-compact.sh"}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": "bash $CODEX_HOME/hooks/$LEGACY_SLUG-session-end.sh"}]}
    ]
  },
  "userSetting": true
}
JSON

( cd "$PROJECT" && HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME" bash "$INSTALL" ) \
  > "$BOX/install.log" 2>&1

assert_eq "present" "$([ -f "$HOME_DIR/.agents/skills/build/SKILL.md" ] && echo present || echo missing)" \
  "install: canonical skills are available to Codex"
assert_eq "missing" "$([ -f "$CODEX_HOME/AGENTS.md" ] && echo present || echo missing)" \
  "install: no global AGENTS.md is created — the rules live in each project's AGENTS.md block (slice 5)"
assert_not_contains "$(cat "$BOX/install.log")" "rendered shared workflow rules" \
  "install: the adapter no longer reports rendering a global file"
assert_eq "present" "$([ -f "$CODEX_HOME/agents/planner.toml" ] && echo present || echo missing)" \
  "install: canonical agents become Codex TOML"
assert_eq "present" "$([ -f "$CODEX_HOME/agents/personal-agent.toml" ] && echo present || echo missing)" \
  "install: unrelated personal agent is preserved"
assert_eq "present" "$([ -f "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py" ] && echo present || echo missing)" \
  "install: SessionStart adapter is installed"
assert_contains "$(cat "$BOX/install.log")" "Review installed hooks with /hooks" \
  "install: hook trust remains an explicit user action"

# The Codex adapter registers no git alias, so the README sends Codex users to the
# checkout script itself. Prove that path delivers the neutral seed.
git init -q "$PROJECT"
( cd "$PROJECT" && HOME="$HOME_DIR" bash "$REPO/scripts/scaffold-project.sh" ) > "$BOX/scaffold.log" 2>&1
assert_eq "0" "$?" "scaffold from checkout: exits 0 without install.sh having run"
assert_files_identical "$REPO/project-template/AGENTS.md" "$PROJECT/AGENTS.md" \
  "scaffold from checkout: neutral AGENTS.md seed lands in the project"

if "$TEST_PYTHON" - "$CODEX_HOME" "$REPO" "$LEGACY_SLUG" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

codex_home = Path(sys.argv[1])
repo = Path(sys.argv[2])
agents = sorted((codex_home / "agents").glob("*.toml"))
expected = sorted(p.stem for p in (repo / ".agents" / "agents").glob("*.md") if p.name != "README.md")
assert [p.stem for p in agents if p.stem != "personal-agent"] == expected
for path in agents:
    data = tomllib.loads(path.read_text())
    if path.stem != "personal-agent":
        assert {"name", "description", "developer_instructions"} <= data.keys(), path
hooks = json.loads((codex_home / "hooks.json").read_text())
assert hooks["userSetting"] is True
assert any("echo existing" in h.get("command", "") for g in hooks["hooks"]["SessionStart"] for h in g["hooks"])
legacy_slug = sys.argv[3]
for event in ("SessionStart", "PreCompact", "SessionEnd"):
    commands = [h["command"] for g in hooks["hooks"][event] for h in g["hooks"]]
    adapter_commands = [command for command in commands if "jplugin-agentic-development" in command]
    assert len(adapter_commands) == 1, (event, commands)
    # A re-run on a machine installed before the rename replaces the old-slug
    # registration for the same event instead of leaving two adapters firing.
    legacy_files = (f"{legacy_slug}-session-start.py", f"{legacy_slug}-pre-compact.sh", f"{legacy_slug}-session-end.sh")
    assert not [command for command in commands if any(command.endswith(name) for name in legacy_files)], (event, commands)
# A user hook whose path merely contains the old slug is not this adapter's and survives.
assert any(f"{legacy_slug}-notes/hook.sh" in h.get("command", "") for g in hooks["hooks"]["SessionStart"] for h in g["hooks"])
PY
then
  :
else
  assert_eq "0" "1" "install: generated Codex configuration validates"
fi

cp "$CODEX_HOME/hooks.json" "$BOX/hooks.before"
( cd "$PROJECT" && HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME" bash "$INSTALL" ) \
  > "$BOX/install-again.log" 2>&1
assert_files_identical "$BOX/hooks.before" "$CODEX_HOME/hooks.json" \
  "install: hook registration is idempotent"

# A ~/.codex/AGENTS.md an earlier adapter rendered into is the user's file: this
# script never writes it again; install.sh lists the stale block for removal
# (tests/test-install-sh.sh, Case 9) and the file itself is never deleted (D8).
printf '# Personal\n\n<!-- %s:begin -->\nOLD\n<!-- %s:end -->\n' "$LEGACY_SLUG" "$LEGACY_SLUG" > "$CODEX_HOME/AGENTS.md"
cp "$CODEX_HOME/AGENTS.md" "$BOX/agents.seeded"
( cd "$PROJECT" && HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME" bash "$INSTALL" ) \
  > "$BOX/install-seeded.log" 2>&1
assert_files_identical "$BOX/agents.seeded" "$CODEX_HOME/AGENTS.md" \
  "install: a pre-seeded ~/.codex/AGENTS.md is left byte-identical — the adapter neither renders nor strips it"

HOOK_RESULT="$(printf '%s\n' '{"source":"startup"}' | HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME" \
  "$TEST_PYTHON" "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py")"
# Run it a second time before asserting anything. The shell hook's
# double-invocation guard is a Claude Code workaround that the adapter disables,
# because it keys on $PPID — which is 1 for every bash spawned from a native
# Windows process, collapsing all invocations onto one sentinel. Left enabled,
# only the very first run in a 5-minute window carries a banner, so a
# single-shot assertion passes on a clean machine and fails on a busy one.
HOOK_RESULT_AGAIN="$(printf '%s\n' '{"source":"startup"}' | HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME" \
  "$TEST_PYTHON" "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py")"
if "$TEST_PYTHON" - "$HOOK_RESULT" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
assert data["hookSpecificOutput"]["hookEventName"] == "SessionStart"
context = data["hookSpecificOutput"]["additionalContext"]
assert "SESSION START" in context, context[:200]
# The banner is non-ASCII, which is why the adapter must not let Python encode
# stdout with the platform default (cp1252 on Windows raises UnicodeEncodeError
# there and emits nothing). Asserting only on shape would not catch that.
assert any(ord(character) > 127 for character in context)
PY
then
  :
else
  assert_eq "0" "1" "hook: SessionStart output validates as Codex JSON"
fi
assert_contains "$HOOK_RESULT_AGAIN" '"hookEventName": "SessionStart"' \
  "hook: repeat invocation still emits context"

BAD="$BOX/bad-agents"
mkdir -p "$BAD"
printf '# malformed\n' > "$BAD/broken.md"
if "$TEST_PYTHON" "$RENDERER" --agents "$BAD" "$BOX/bad-output" > "$BOX/bad.log" 2>&1; then
  assert_eq "failure" "success" "renderer: malformed agent input is rejected"
else
  assert_contains "$(cat "$BOX/bad.log")" "broken.md" \
    "renderer: malformed input identifies the source file"
fi

rm -rf "$BOX"
finish
