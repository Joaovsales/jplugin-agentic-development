#!/usr/bin/env bash
# Interpreter shim for the bulk-read gate (specs/bulk-read-gate.md).
#
# .claude/settings.json runs this, not the .py directly, so the interpreter is
# resolved the same way scripts/install-codex.sh resolves it: python3 first,
# then python. A hardcoded `python3` would exit non-zero on a python-only host,
# Claude Code would treat that as a non-blocking hook error, and the gate would
# quietly degrade to allowing every read.
set -euo pipefail

here="${BASH_SOURCE[0]%/*}"   # builtins only: PATH may hold nothing but python
[ "$here" = "${BASH_SOURCE[0]}" ] && here=.
here="$(cd "$here" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  exec python3 "$here/bulk-read-gate.py"
fi
if command -v python >/dev/null 2>&1; then
  exec python "$here/bulk-read-gate.py"
fi
echo "bulk-read-gate: Python 3 is required to run the gate" >&2
exit 1
