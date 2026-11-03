# retrykit — Agent Instructions

<!-- jplugin-agentic-development:begin -->
## Workflow

Specs live in `specs/`; the plan lives in `tasks/todo.md`. Build from the plan one
slice at a time and keep the suite green before moving on.

## Core Principles

**Never Guess — Verify.** Read before editing. Check that files exist.

**Minimal Impact.** Touch only what the task needs.

**No Silent Failures.** Explicit errors only. No `except: pass`.
<!-- jplugin-agentic-development:end -->

## Project-Specific Rules

Python 3 standard library only. No third-party packages.

### Test Commands

Full suite: python scripts/run_tests.py
Affected tests: python scripts/run_tests.py {base}
