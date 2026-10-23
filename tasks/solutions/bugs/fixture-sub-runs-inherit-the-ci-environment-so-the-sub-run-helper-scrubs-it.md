---
title: Fixture sub-runs inherit the CI environment, so the sub-run helper scrubs it
date: 2026-10-22
problem_type: test-failure
module: tests/test-lib.sh (run_case); tests/test-run-sh.sh (run_box); tests/lib.sh § finish (REQUIRE_ALL); .github/workflows/tests.yml
tags: [testing, ci, environment, require-all, false-green, aposd]
symptoms: PR #356's first `test` run failed 3 assertions (`skip: a skipped file exits 0 without REQUIRE_ALL`, `summary:`/`jobs: the file without a trailer is counted as a failed file`) that passed on Windows and under WSL; the fixture files the assertions ran had exited 1 or been counted as a third failed file
root_cause: `tests.yml` exports `REQUIRE_ALL=1` (and `REQUIRE_BROWSER=1`) so CI never goes green on a skip; a fixture sub-run started with a bare `bash "$f"` inherits that environment, so a fixture that calls `skip` fails in CI and nowhere else. The tests handled the knob per sub-run, at the sites that happened to need it, in two spellings (`REQUIRE_ALL=0 run_case …`, `env -u REQUIRE_ALL … bash …`)
resolution: Fixed by closure repair 1 of PR #356; `run_case` and `run_box` run every fixture sub-run through `env -u REQUIRE_ALL -u REQUIRE_BROWSER`, and a case that wants a knob set passes it as a leading `VAR=value` argument to the helper
---

## What happened

The test-suite migration (specs/test-suite-aposd.md) added `skip` and the
`REQUIRE_ALL=1` rule to `tests/lib.sh` § finish, and tests for both. Three of
those tests run a fixture file that skips and assert the *unset* behaviour — exit
0, one skipped in the trailer, two failed files out of five. Every developer host
runs the suite with `REQUIRE_ALL` unset, so the three passed locally through the
whole build, the gate and the Windows and WSL suite runs. CI exports
`REQUIRE_ALL=1`, the fixture inherited it, and the three went red there alone.
Two sites in the same file had already met the problem (`test-run-sh.sh`'s
plan-page sub-runs) and solved it inline with `env -u`.

## The rule

A fixture sub-run is a trust boundary for the library's environment knobs. The
helper that starts the sub-run owns that boundary: `run_case` and `run_box` run
their command through `env -u REQUIRE_ALL -u REQUIRE_BROWSER`, and a case that
wants a knob set asks the helper (`run_case REQUIRE_ALL=1 required.sh …`,
`run_box REQUIRE_ALL=1 … bash tests/test-plan-page.sh`). No test file spells
`env -u` or `VAR=0` for a library knob itself; a new knob in `lib.sh` or `run.sh`
is added to the two helpers, not to every call site.

## How to check

Run the file with the CI environment exported before pushing:
`REQUIRE_ALL=1 REQUIRE_BROWSER=1 bash tests/run.sh tests/test-lib.sh tests/test-run-sh.sh`.
A test whose fixture calls `skip` and whose message says "without REQUIRE_ALL"
must still pass under that command. The WSL clone proves Linux, not CI: it
inherits nothing either.
