#!/usr/bin/env bash
# PostToolUse regression matrix; cases migrated from the PR #128 deny gate.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/context_read_cases.py
