#!/usr/bin/env bash
set -eu
python3 "$(dirname "$0")/../fixture_gen.py" pipeline-checks-intermittent --out .
