---
title: The Claude Code Bash tool collapses backslash escapes before the shell sees the command, whatever the quoting
date: 2026-09-11
problem_type: tooling
module: Claude Code Bash tool (harness), tests/*.sh patch workflow
tags: [claude-code, bash-tool, heredoc, backslash, crlf, windows, patching]
applies_when: patching a file from the Bash tool with text that contains a backslash — a `\r` or `\n` escape, a `\` line continuation, a regex — through a heredoc, a `python3 -c '...'` argument, or a sed program
---

## The rule

Any backslash in the **command text** may reach the shell already collapsed:
`\r` arrives as a literal carriage return, `\n` as a newline, `\\` as `\`. Quoted
heredocs (`<<'EOF'`) and single quotes do not protect it — the substitution
happens before the shell parses anything. Observed twice on 2026-09-11:

- A heredoc patch that should have written `tr -d '\r'` wrote a real CR inside
  the quotes. The test still passed, because `tr -d <CR>` deletes CRs just as
  well — but the lone CR flipped git's view of the CRLF file to `w/-text`, so
  `git diff` showed all 1,075 lines as changed.
- A `python3 -c '...'` repair whose replacement was `'\\r'` reached Python as
  `'\r'`, replaced CR with CR, and printed "fixed".

Both produced plausible diffs that ran. Neither would have been caught by the
test suite.

## How to apply

1. Route any patch whose replacement text carries a backslash through a
   **script file written with the Write tool**, then run `python3 <file>` from
   Bash. File bytes are exact; only the command line is mangled.
2. For Bash-only edits, write text with **no backslashes**: one-line commands,
   no line continuations, `chr(92)` / `chr(13)` / `chr(10)` in Python instead
   of escapes.
3. After any patch, `bash -n` or `py_compile` the file **and** re-read the
   patched region. Then `git ls-files --eol <file>`: a CRLF file must still
   read `w/crlf`; `w/-text` or `w/mixed` means a stray lone CR or LF got in.

## Why this matters here

Most of this repository's tracked text is CRLF on Windows checkouts
(`core.autocrlf=true`), and several tests strip `\r` explicitly. Those are
exactly the lines a backslash-eating patch corrupts silently.
