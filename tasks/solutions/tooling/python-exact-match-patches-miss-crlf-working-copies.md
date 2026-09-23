---
title: A python exact-match patch misses its target in a CRLF working copy; the Edit tool does not
date: 2026-09-23
problem_type: tooling
module: tests/*.sh and .agents/skills/*/SKILL.md patch workflow on the Windows clone
tags: [windows, crlf, autocrlf, python, patching, edit-tool]
applies_when: patching a tracked file on the Windows clone with a script that matches a multi-line string containing "\n"
---

## The rule

On this clone, `core.autocrlf` checks tracked files out with CRLF line endings
(`file tests/run.sh` reports "with CRLF line terminators"). A patch script that
opens the file with `newline=''` and matches a literal containing `\n` never
finds the target. This session observed it twice in one build
(`tests/run.sh`, `.agents/skills/build/SKILL.md`). Both times the script's own
`assert t.count(a) == 1` stopped it before it wrote anything. The Edit tool
applied the same replacement to both files first try, because it matches
line-ending-agnostically.

## How to apply

1. For a replacement that spans lines in a tracked file, use the Edit tool, not
   a python or sed patch.
2. If a script is unavoidable, read with the default universal-newline mode and
   write back with `newline='\r\n'` when the original used CRLF. Keep the
   exact-count assert: it is what turned a silent no-op into a visible failure.
3. A single-line pattern with no `\n` is unaffected.

Related: [[claude-code-bash-tool-collapses-backslash-escapes]] — the other way a
Bash-tool patch reports success and changes nothing.
