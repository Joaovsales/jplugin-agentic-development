#!/usr/bin/env bash
set -eu
python3 "$(dirname "$0")/../fixture_gen.py" settings-loader-port --out .
