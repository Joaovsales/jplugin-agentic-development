#!/bin/bash
# The optional graph hint uses fresh files, never the graphify executable.
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
HOOK="$(under_test .agents/hooks)/code-graph-hint.sh"
GUIDE="$(under_test .agents/references)/code-navigation.md"
REGISTRY="$(under_test hooks/hooks.json)"
assert_file_exists "$HOOK" "code graph hint hook exists"
assert_file_exists "$GUIDE" "code navigation reference exists"
if [ ! -f "$HOOK" ] || [ ! -f "$GUIDE" ]; then finish; exit $?; fi

"$TEST_PYTHON" - "$HOOK" "$GUIDE" "$REGISTRY" <<'PY'
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

hook, guide, registry = (Path(value).resolve() for value in sys.argv[1:])
text = guide.read_text().lower()
for requirement in ("lsp", "grep", "glob", "read", "timeout 20 graphify explain",
                    "timeout 20 graphify path", "timeout 20 graphify query",
                    "--budget 1500", "non-zero", "timeout", "unparsable", "empty",
                    "at most one", "timeout 120 graphify update .", "no callers",
                    "unused", "nothing touches this", "never installs or upgrades",
                    "language server", "graph_report.md", "claude_plugin_root",
                    "text-only"):
    assert requirement in text, requirement
assert "do not retry" in text
assert "confirm" in text
entries = json.loads(registry.read_text())["hooks"].get("PreToolUse", [])
registered = [item for entry in entries if entry.get("matcher") == "Grep|Glob"
              for item in entry.get("hooks", []) if "code-graph-hint.sh" in item.get("command", "")]
assert len(registered) == 1 and registered[0].get("timeout") == 5, registered
assert "GRAPH_REPORT.md" not in json.dumps(entries), entries
print("ok: routing contract and one bounded plugin registration")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    repository, binary = root / "project", root / "bin"
    repository.mkdir()
    binary.mkdir()
    bash = shutil.which("bash")
    assert bash
    env = dict(os.environ)
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
        env.pop(key, None)
    env.update(PATH=str(binary), GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
    # Only these existing tools enter PATH; no host graphify can leak into a case.
    for name, executable in (("python3", sys.executable), ("git", shutil.which("git")),
                             ("timeout", shutil.which("timeout"))):
        assert executable, name
        wrapper = binary / name
        wrapper.write_text("#!/bin/bash\nexec " + shlex.quote(str(Path(executable).resolve())) + ' "$@"\n')
        wrapper.chmod(0o755)
    git = shutil.which("git")
    def command(*args):
        return subprocess.check_output([git, *args], cwd=repository, env=env, stderr=subprocess.DEVNULL)
    command("-c", "init.templateDir=", "init", "-q")
    command("config", "core.hooksPath", str(root / "no-hooks"))
    source = repository / "service.py"
    source.write_text("def calculate(value):\n    return value\n")
    command("add", "service.py")
    command("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-qm", "initial")
    head_time = int(command("log", "-1", "--format=%ct")) * 1_000_000_000
    graph = repository / "graphify-out/graph.json"
    called = root / "graphify-called"
    executable = binary / "graphify"
    executable.write_text("#!/bin/bash\nprintf called > " + shlex.quote(str(called)) + "\nexit 1\n")
    executable.chmod(0o755)

    def fresh_graph():
        graph.parent.mkdir(exist_ok=True)
        graph.write_text('{"nodes": [], "edges": []}\n')
        stamp = max(time.time_ns(), head_time) + 1_000_000_000
        os.utime(graph, ns=(stamp, stamp))
        return stamp

    def invoke(payload=None, expected_hint=False):
        start = time.monotonic()
        result = subprocess.run([bash, str(hook)], cwd=repository, env=env,
                                input=payload if payload is not None else '{"tool_name":"Grep","tool_input":{"pattern":"calculate"}}',
                                text=True, capture_output=True, timeout=2)
        assert time.monotonic() - start < 2, result
        assert result.returncode == 0 and not result.stderr, result
        if expected_hint:
            assert len(result.stdout.splitlines()) == 1, result.stdout
            output = json.loads(result.stdout)
            context = output["hookSpecificOutput"]
            assert context["hookEventName"] == "PreToolUse", output
            assert ".agents/references/code-navigation.md" in context["additionalContext"], output
            assert "permissionDecision" not in context, output
        else:
            assert result.stdout == "", result.stdout
        assert not called.exists(), "hook executed graphify"

    fresh_graph()
    invoke(expected_hint=True)
    invoke('{"tool_name":"Glob","tool_input":{"pattern":"*.py"}}', expected_hint=True)
    print("ok: fresh graph emits one hint for Grep and Glob, without executing graphify")
    os.utime(graph, ns=(head_time - 1_000_000_000, head_time - 1_000_000_000))
    invoke()
    stamp = fresh_graph()
    source.write_text("def calculate(value):\n    return value + 1\n")
    os.utime(source, ns=(stamp + 1_000_000_000, stamp + 1_000_000_000))
    invoke()
    command("add", "service.py")
    invoke()
    command("reset", "-q", "HEAD", "service.py")
    command("checkout", "--", "service.py")
    fresh_graph()
    source.unlink()
    invoke()
    command("checkout", "--", "service.py")
    fresh_graph()
    graph.write_text("{broken\n")
    invoke()
    graph.unlink()
    invoke()
    fresh_graph()
    executable.unlink()
    invoke()
    executable.write_text("#!/bin/bash\nprintf called > " + shlex.quote(str(called)) + "\nwhile :; do :; done\n")
    executable.chmod(0o755)
    invoke(expected_hint=True)
    invoke("not JSON")
    invoke('{"tool_name":"Bash"}')
    print("ok: stale, staged, deleted, corrupt, absent and malformed states fail open; hanging CLI is never called")
PY
rc=$?
assert_eq 0 "$rc" "code graph hint freshness, fail-open behavior and navigation contract"
finish
