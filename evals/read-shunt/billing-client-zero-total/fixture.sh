#!/usr/bin/env bash
set -eu
python3 "$(dirname "$0")/../fixture_gen.py" billing-client-zero-total --out .
