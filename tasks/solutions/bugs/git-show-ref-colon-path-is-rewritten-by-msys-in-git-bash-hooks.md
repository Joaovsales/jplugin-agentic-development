---
title: git show <ref>:<path> is rewritten by MSYS in Git Bash hooks
date: 2026-09-29
problem_type: runtime-error
module: .agents/hooks/session-start.sh § Stale Plugin Install Check
tags: [windows, git-bash, msys, pathconv, git, hooks]
symptoms: "In the stale-plugin fixture the banner printed `the template is at  (bcbfdce)`: the sha was right but the version read from `git show refs/remotes/origin/master:.claude-plugin/plugin.json` came back empty, only on Windows"
root_cause: "Git Bash (MSYS) converts any argument that looks like a colon-separated path list before handing it to a native program such as git.exe, so `<ref>:<path>` reached git mangled and `git show` failed silently behind `2>/dev/null`"
resolution: "Prefix the one call with `MSYS_NO_PATHCONV=1` (.agents/hooks/session-start.sh:523-525). The variable is ignored outside MSYS, so the line stays portable. Pinned by the AC 3 fixture in tests/test-session-start.sh (`the remote ref is the template the headline names`)"
---

**Status**: fixed — 2026-09-29 (this session, #210)

Any `git show`, `git cat-file` or `git rev-parse` argument of the form
`<rev>:<path>` inside a hook or script that runs under Git Bash needs
`MSYS_NO_PATHCONV=1`, and so does anything else containing `:` followed by
a `/`. The failure is silent whenever stderr is discarded, which is the norm in
banner code. Test fixtures catch it only when they assert on the value read,
not merely that the block printed.

Related: tooling/print-mode-skill-probes-on-windows-git-bash.md (the same
conversion rewriting `/skill` prompt arguments).
