#!/bin/bash
# Routing belongs at the decision point; handover maintenance must fail open.
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
"$TEST_PYTHON" - "$(under_test .agents/skills)" <<'PY'
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

skills = Path(sys.argv[1])

def section(path, start, end):
    text = (skills / path).read_text()
    return text.split(start, 1)[1].split(end, 1)[0]

stages = [
    section('how/references/explorer-prompt.md', '**Find the entry point.**', '3.'),
    section('debug/SKILL.md', '## Phase 1 — Reproduce & Isolate', '## Phase 2'),
    section('plan/SKILL.md', '**Check this repository first', '2. **Check for'),
    section('quality-gate/SKILL.md', '## Phase 1 — Structural Quality', '## Phase 2'),
]
for text in stages:
    assert '.agents/references/code-navigation.md' in text, 'routing reference missing at decision point'
    assert 'Grep' in text, 'explicit Grep fallback missing'
    assert '${CLAUDE_PLUGIN_ROOT}' in text, 'plugin reference fallback missing'
assert re.search(r'confirm.{0,120}negative.{0,120}Grep', stages[-1], re.I | re.S), 'graph negatives need independent confirmation'
assert 'caller' in stages[-1].lower() and 'blast-radius' in stages[-1].lower()
print('ok: routing at entry-point, localization, preflight and caller review stages')

build = (skills / 'build/SKILL.md').read_text()
close = build.split('### Slice Close', 1)[1].split('**Unfinished slice**', 1)[0]
blocks = re.findall(r'```bash\n(.*?)```', close, re.S)
snippet = next(block for block in blocks if 'graphify update .' in block)
assert 'command -v graphify' in snippet and 'graphify-out/graph.json' in snippet
assert 'timeout 120 graphify update .' in snippet
assert 'warning' in close.lower() and 'never fails' in close.lower()
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    binary = root / 'bin'
    binary.mkdir()
    timeout = shutil.which('timeout')
    assert timeout
    (binary / 'timeout').symlink_to(timeout)
    env = dict(os.environ, PATH=str(binary))
    bash = shutil.which('bash')
    assert bash
    executable = binary / 'graphify'
    graph = root / 'graphify-out/graph.json'
    marker = root / 'called'
    for has_cli, has_graph, fails in [(False, False, False), (False, True, False), (True, False, False), (True, True, False), (True, True, True)]:
        if marker.exists(): marker.unlink()
        if executable.exists(): executable.unlink()
        if graph.exists(): graph.unlink()
        if has_cli:
            executable.write_text('#!' + bash + '\nprintf "%s\\n" "$*" > "' + str(marker) + '"\nexit ' + ('1' if fails else '0') + '\n')
            executable.chmod(0o755)
        if has_graph:
            graph.parent.mkdir(exist_ok=True)
            graph.write_text('{}')
        run = subprocess.run([bash, '-e', '-c', snippet], cwd=root, env=env, capture_output=True, text=True, timeout=3)
        assert run.returncode == 0, run
        assert marker.exists() == (has_cli and has_graph), (has_cli, has_graph, run)
        if marker.exists(): assert marker.read_text().strip() == 'update .'
        lines = (run.stdout + run.stderr).splitlines()
        assert len(lines) == int(has_cli and has_graph and fails), lines
        if lines: assert lines[0].startswith('> Warning:'), lines
print('ok: extracted handover refresh skips absent prerequisites and warns once on failure')
PY
rc=$?
assert_eq 0 "$rc" "code graph skill routing and bounded handover refresh"
finish
