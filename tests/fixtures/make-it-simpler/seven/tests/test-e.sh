#!/bin/bash
out="$(run)"
assert_contains "$out" "print the summary banner exactly once" "banner"
