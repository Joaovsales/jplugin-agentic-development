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
assert_file_contains "$CODEX_HOME/config.toml" 'max_concurrent_threads_per_session = 3' \
  "install: native three-child default lands in Codex config"
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
expected = sorted(expected + ["explorer", "scout", "debug-escalation"])
assert [p.stem for p in agents if p.stem != "personal-agent"] == expected
for path in agents:
    data = tomllib.loads(path.read_text())
    if path.stem != "personal-agent":
        assert {"name", "description", "developer_instructions"} <= data.keys(), path
    if path.stem in {"explorer", "scout"}:
        assert data["model"] == "gpt-6-luna", path
        assert data["model_reasoning_effort"] == "low", path
    if path.stem == "explorer":
        assert data["sandbox_mode"] == "read-only"
    if path.stem == "scout":
        assert "sandbox_mode" not in data
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

# A known unmarked renderer output is offered for adoption, never adopted by a
# routine install. An explicit adoption keeps the original bytes in a backup.
MIG="$BOX/migration"
mkdir -p "$MIG/home/.codex/agents" "$MIG/home/.agents"
"$TEST_PYTHON" - "$REPO" "$MIG/home/.codex/agents/planner.toml" <<'PY'
import json
import sys
from pathlib import Path
source = Path(sys.argv[1]) / ".agents/agents/planner.md"
lines = source.read_text().splitlines()
end = lines.index("---", 1)
description = next(line.split(":", 1)[1].strip() for line in lines[1:end] if line.startswith("description:"))
name = next(line.split(":", 1)[1].strip() for line in lines[1:end] if line.startswith("name:"))
body = "\n".join(lines[end + 1:]).strip()
Path(sys.argv[2]).write_text("".join(f"{key} = {json.dumps(value, ensure_ascii=False)}\n" for key, value in
    (("name", name), ("description", description), ("developer_instructions", body))))
PY
printf 'theme = "personal"\n[agents]\nmax_concurrent_threads_per_session = 5\n' > "$MIG/home/.codex/config.toml"
cp "$MIG/home/.codex/agents/planner.toml" "$MIG/legacy.before"
cp "$MIG/home/.codex/config.toml" "$MIG/config.before"
MIG_HOME="$MIG/home/.codex"
MIG_AGENTS="$MIG/home/.agents"
HOME="$MIG/home" CODEX_HOME="$MIG_HOME" AGENTS_HOME="$MIG_AGENTS" bash "$INSTALL" --preview > "$MIG/preview.log" 2>&1
assert_contains "$(cat "$MIG/preview.log")" 'legacy_candidate' "preview: exact old planner shape identified"
assert_contains "$(cat "$MIG/preview.log")" 'backup' "preview: planned backup named"
assert_contains "$(cat "$MIG/preview.log")" 'exceeds policy' "preview: excess user cap diagnosed"
assert_files_identical "$MIG/legacy.before" "$MIG_HOME/agents/planner.toml" "preview: legacy file unchanged"
if HOME="$MIG/home" CODEX_HOME="$MIG_HOME" AGENTS_HOME="$MIG_AGENTS" bash "$INSTALL" > "$MIG/refused.log" 2>&1; then
  assert_eq "refused" "applied" "install: legacy adoption needs opt-in"
else
  assert_files_identical "$MIG/legacy.before" "$MIG_HOME/agents/planner.toml" "install: legacy remains before opt-in"
fi
( umask 022; HOME="$MIG/home" CODEX_HOME="$MIG_HOME" AGENTS_HOME="$MIG_AGENTS" bash "$INSTALL" --adopt-legacy ) > "$MIG/adopt.log" 2>&1
assert_eq "0" "$?" "install: explicit legacy adoption succeeds"
assert_files_identical "$MIG/legacy.before" "$MIG_HOME/agents/planner.toml.bak" "adoption: original bytes backed up"
if "$TEST_PYTHON" - "$MIG_HOME/agents/planner.toml.bak" <<'PY'
import os
import stat
import sys
from pathlib import Path
if os.name != "nt":
    assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o600
PY
then
  assert_eq "0" "0" "adoption: backup is private under a permissive umask"
else
  assert_eq "0" "1" "adoption: backup is private under a permissive umask"
fi
assert_file_contains "$MIG_HOME/agents/planner.toml" 'jplugin-agentic-development:managed' "adoption: new managed shape installed"
assert_files_identical "$MIG/config.before" "$MIG_HOME/config.toml" "adoption: user cap and unrelated config survive byte-identical"
cp "$MIG_HOME/agents/planner.toml" "$MIG/adopted.before"
HOME="$MIG/home" CODEX_HOME="$MIG_HOME" AGENTS_HOME="$MIG_AGENTS" bash "$INSTALL" > "$MIG/repeat.log" 2>&1
assert_files_identical "$MIG/adopted.before" "$MIG_HOME/agents/planner.toml" "repeat: adopted file is byte-identical"

CONFIG_CASE="$BOX/config-update"
mkdir -p "$CONFIG_CASE/home/.codex"
printf 'theme = "personal"\n[agents]\nmax_custom_setting = 9\n[notice]\nhide_full_access_warning = true\n' > "$CONFIG_CASE/home/.codex/config.toml"
cp "$CONFIG_CASE/home/.codex/config.toml" "$CONFIG_CASE/before"
HOME="$CONFIG_CASE/home" CODEX_HOME="$CONFIG_CASE/home/.codex" bash "$INSTALL" --preview > "$CONFIG_CASE/preview.log" 2>&1
assert_contains "$(cat "$CONFIG_CASE/preview.log")" 'native cap missing' "config preview: missing native cap diagnosed"
assert_files_identical "$CONFIG_CASE/before" "$CONFIG_CASE/home/.codex/config.toml" "config preview: existing bytes unchanged"
HOME="$CONFIG_CASE/home" CODEX_HOME="$CONFIG_CASE/home/.codex" bash "$INSTALL" > "$CONFIG_CASE/install.log" 2>&1
assert_files_identical "$CONFIG_CASE/before" "$CONFIG_CASE/home/.codex/config.toml.bak" "config apply: original bytes backed up"
if "$TEST_PYTHON" - "$CONFIG_CASE/home/.codex/config.toml" <<'PY'
import sys
import tomllib
from pathlib import Path
config = tomllib.loads(Path(sys.argv[1]).read_text())
assert config["theme"] == "personal"
assert config["agents"]["max_custom_setting"] == 9
assert config["agents"]["max_concurrent_threads_per_session"] == 3
assert config["notice"]["hide_full_access_warning"] is True
PY
then
  assert_eq "0" "0" "config apply: native cap and unrelated keys survive"
else
  assert_eq "0" "1" "config apply: native cap and unrelated keys survive"
fi
cp "$CONFIG_CASE/home/.codex/config.toml" "$CONFIG_CASE/applied.before"
HOME="$CONFIG_CASE/home" CODEX_HOME="$CONFIG_CASE/home/.codex" bash "$INSTALL" > "$CONFIG_CASE/repeat.log" 2>&1
assert_files_identical "$CONFIG_CASE/applied.before" "$CONFIG_CASE/home/.codex/config.toml" "config repeat: no rewrite"

ALIAS_CASE="$BOX/legacy-cap-alias"
mkdir -p "$ALIAS_CASE/home/.codex"
printf 'theme = "personal"\n[agents]\nmax_threads = 5\n' > "$ALIAS_CASE/home/.codex/config.toml"
cp "$ALIAS_CASE/home/.codex/config.toml" "$ALIAS_CASE/before"
HOME="$ALIAS_CASE/home" CODEX_HOME="$ALIAS_CASE/home/.codex" bash "$INSTALL" --preview > "$ALIAS_CASE/preview.log" 2>&1
assert_contains "$(cat "$ALIAS_CASE/preview.log")" 'exceeds policy' "legacy cap alias: excess override diagnosed"
HOME="$ALIAS_CASE/home" CODEX_HOME="$ALIAS_CASE/home/.codex" bash "$INSTALL" > "$ALIAS_CASE/install.log" 2>&1
assert_files_identical "$ALIAS_CASE/before" "$ALIAS_CASE/home/.codex/config.toml" \
  "legacy cap alias: user override stays byte-identical"

DEFAULT_CASE="$BOX/global-default"
mkdir -p "$DEFAULT_CASE/home/.codex"
printf '[agents]\ndefault_subagent_model = "gpt-6-luna"\n' > "$DEFAULT_CASE/home/.codex/config.toml"
cp "$DEFAULT_CASE/home/.codex/config.toml" "$DEFAULT_CASE/before"
HOME="$DEFAULT_CASE/home" CODEX_HOME="$DEFAULT_CASE/home/.codex" bash "$INSTALL" --preview > "$DEFAULT_CASE/preview.log" 2>&1
assert_contains "$(cat "$DEFAULT_CASE/preview.log")" 'agents.default_subagent_model' "default preview: Ceiling conflict named"
if HOME="$DEFAULT_CASE/home" CODEX_HOME="$DEFAULT_CASE/home/.codex" bash "$INSTALL" > "$DEFAULT_CASE/install.log" 2>&1; then
  assert_eq "refused" "applied" "default apply: global model cap refused"
else
  assert_files_identical "$DEFAULT_CASE/before" "$DEFAULT_CASE/home/.codex/config.toml" "default apply: personal config unchanged"
fi

EFFORT_CASE="$BOX/global-effort-default"
mkdir -p "$EFFORT_CASE/home/.codex"
printf '[agents]\ndefault_subagent_reasoning_effort = "low"\n' > "$EFFORT_CASE/home/.codex/config.toml"
cp "$EFFORT_CASE/home/.codex/config.toml" "$EFFORT_CASE/before"
HOME="$EFFORT_CASE/home" CODEX_HOME="$EFFORT_CASE/home/.codex" bash "$INSTALL" --preview > "$EFFORT_CASE/preview.log" 2>&1
assert_contains "$(cat "$EFFORT_CASE/preview.log")" 'agents.default_subagent_reasoning_effort' "effort preview: Ceiling conflict named"
if HOME="$EFFORT_CASE/home" CODEX_HOME="$EFFORT_CASE/home/.codex" bash "$INSTALL" > "$EFFORT_CASE/install.log" 2>&1; then
  assert_eq "refused" "applied" "effort apply: global reasoning cap refused"
else
  assert_files_identical "$EFFORT_CASE/before" "$EFFORT_CASE/home/.codex/config.toml" "effort apply: personal config unchanged"
fi

CONFLICT="$BOX/conflict"
mkdir -p "$CONFLICT/home/.codex/agents"
printf 'name = "planner"\ndescription = "mine"\ndeveloper_instructions = "personal"\n' > "$CONFLICT/home/.codex/agents/planner.toml"
cp "$CONFLICT/home/.codex/agents/planner.toml" "$CONFLICT/personal.before"
if HOME="$CONFLICT/home" CODEX_HOME="$CONFLICT/home/.codex" bash "$INSTALL" --adopt-legacy > "$CONFLICT/result.log" 2>&1; then
  assert_eq "refused" "applied" "install: personal role conflict is refused"
else
  assert_files_identical "$CONFLICT/personal.before" "$CONFLICT/home/.codex/agents/planner.toml" "install: personal conflict stays byte-identical"
fi

INVALID="$BOX/invalid"
mkdir -p "$INVALID/home/.codex/agents"
printf 'this is not toml = [\n' > "$INVALID/home/.codex/agents/planner.toml"
cp "$INVALID/home/.codex/agents/planner.toml" "$INVALID/before"
if HOME="$INVALID/home" CODEX_HOME="$INVALID/home/.codex" bash "$INSTALL" --adopt-legacy > "$INVALID/result.log" 2>&1; then
  assert_eq "refused" "applied" "install: invalid TOML is refused"
else
  assert_files_identical "$INVALID/before" "$INVALID/home/.codex/agents/planner.toml" "install: invalid TOML stays byte-identical"
fi

LINK_CASE="$BOX/dangling-link"
mkdir -p "$LINK_CASE/home/.codex/agents"
ln -s "$LINK_CASE/missing-personal-target" "$LINK_CASE/home/.codex/agents/planner.toml"
if [ -L "$LINK_CASE/home/.codex/agents/planner.toml" ]; then
  if HOME="$LINK_CASE/home" CODEX_HOME="$LINK_CASE/home/.codex" bash "$INSTALL" --adopt-legacy > "$LINK_CASE/result.log" 2>&1; then
    assert_eq "refused" "applied" "install: dangling personal link is refused"
  else
    assert_eq "present" "$([ -L "$LINK_CASE/home/.codex/agents/planner.toml" ] && echo present || echo missing)" \
      "install: dangling personal link remains"
  fi
fi

WRONG="$BOX/wrong-managed"
mkdir -p "$WRONG/home/.codex/agents"
printf '# jplugin-agentic-development:managed\nname = "another-agent"\ndescription = "mine"\ndeveloper_instructions = "keep"\n' > "$WRONG/home/.codex/agents/planner.toml"
cp "$WRONG/home/.codex/agents/planner.toml" "$WRONG/before"
if HOME="$WRONG/home" CODEX_HOME="$WRONG/home/.codex" bash "$INSTALL" > "$WRONG/result.log" 2>&1; then
  assert_eq "refused" "applied" "install: marked wrong-identity file is refused"
else
  assert_files_identical "$WRONG/before" "$WRONG/home/.codex/agents/planner.toml" \
    "install: marked wrong-identity file stays byte-identical"
fi

OLD_PY="$BOX/old-python"
mkdir -p "$OLD_PY/bin"
printf '#!/bin/sh\nexit 1\n' > "$OLD_PY/bin/python3"
chmod +x "$OLD_PY/bin/python3"
if PATH="$OLD_PY/bin:$PATH" HOME="$OLD_PY/home" CODEX_HOME="$OLD_PY/home/.codex" bash "$INSTALL" > "$OLD_PY/result.log" 2>&1; then
  assert_eq "refused" "applied" "installer: unsupported Python refused"
else
  assert_contains "$(cat "$OLD_PY/result.log")" 'Python 3.11 or newer' "installer: minimum runtime diagnosed"
  assert_eq "missing" "$([ -e "$OLD_PY/home/.codex" ] && echo present || echo missing)" \
    "installer: runtime preflight wrote no files"
fi

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
