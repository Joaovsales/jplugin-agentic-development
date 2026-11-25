#!/bin/bash
. "$(dirname "$0")/lib.sh"

CHECKER="$(under_test .agents/skills/verify-evidence/scripts/visual_check.py)"
PROJECT="$(fixture_dir)"
SCRIPT="$PROJECT/.agents/skills/verify-evidence/scripts/visual_check.py"
DECLARATION="$PROJECT/.claude/visual-validator"
VALIDATOR="$PROJECT/tests/visual/verify.py"
mkdir -p "$(dirname "$SCRIPT")" "$(dirname "$DECLARATION")" "$(dirname "$VALIDATOR")"
cp "$CHECKER" "$SCRIPT"
cat > "$VALIDATOR" <<'PY'
import sys

assert sys.argv[1:] == ["validate", "--output", "example"]
print("project validator")
sys.exit(23)
PY

run python3 "$SCRIPT" validate --output example
assert_contains "$output" "manifest.json" "The default path still reads the generic manifest"

printf 'tests/visual/verify.py\n' > "$DECLARATION"
run python3 "$SCRIPT" validate --output example
assert_eq 23 "$status" "The project validator controls the exit status"
assert_contains "$output" "project validator" "The validator gets the original arguments"

rm "$VALIDATOR"
run python3 "$SCRIPT" validate --output example
assert_eq 1 "$status" "A missing declared validator fails closed"
assert_contains "$output" ".claude/visual-validator" "The error identifies the declaration"

printf '../outside.py\n' > "$DECLARATION"
run python3 "$SCRIPT" validate --output example
assert_eq 1 "$status" "A validator outside the project is refused"
assert_contains "$output" "inside the project" "The error names the confinement boundary"

printf '\n' > "$DECLARATION"
run python3 "$SCRIPT" validate --output example
assert_eq 1 "$status" "An empty declaration fails closed"
assert_contains "$output" ".claude/visual-validator" "The error identifies the empty declaration"

finish
