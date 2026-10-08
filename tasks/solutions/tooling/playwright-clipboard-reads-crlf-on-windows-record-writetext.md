---
title: Assert what a page hands writeText, not what the Windows clipboard reads back
date: 2026-10-08
problem_type: tooling
module: .agents/skills/visual-plan/scripts/check_plan_page.py
tags: [playwright, clipboard, windows, crlf, testing]
applies_when: a browser check asserts that a copy button copied exact text
---

Reading the clipboard back through Playwright on Windows returns CRLF line endings for
text the page wrote with LF, so an exact-bytes copy check fails on a correct page. The
plan-page checker installs an init script that wraps `navigator.clipboard.writeText` and
stores its argument on `window.__planCopied` (`check_plan_page.py:33`), then compares that
with the source element's `textContent`. A sabotage that appends a space to the copied
text proves the check still bites (`tests/test-plan-page.sh:72`).
