---
title: git post-init hook never fires, so newproject and git init produce no scaffold
date: 2026-09-09
problem_type: bug
module: install.sh, scripts/scaffold-project.sh, README.md
tags: [git-hooks, install, bootstrap, dead-mechanism, project-template]
symptoms: In an isolated HOME, install.sh succeeds, but direct git init and the printed newproject function both create repositories with no CLAUDE.md, AGENTS.md, or tasks/ seeds; the helper only ever worked when invoked by hand
root_cause: Git has no post-init hook. init.templateDir copies hooks/post-init into every new repo's .git/hooks and never executes it; the "runs on every git init" claim was fiction. Two further defects sat behind it — the helper hardcoded $HOME/coding-agent-workflow/project-template and exited 0 silently when absent, and its copy list omitted .gitignore, .gitattributes, and tasks/solutions/.gitkeep
resolution: Replaced the hook with an explicit, supported entry point. install.sh copies project-template/ to ~/.agents/project-template, installs scripts/scaffold-project.sh to ~/.agents/bin, and registers the global alias `git scaffold`; the script resolves the template relative to itself, copies the whole inventory while keeping existing files byte-identical, and fails loudly (exit 1, path named) when the template or a git repo is missing. newproject and the README now call git scaffold; the README's overwriting cp block is gone
---

**Status**: fixed — 2026-09-09
**Regression test**: tests/test-install-sh.sh (cases 6–9: spaced checkout path, full inventory, preservation, loud failures, printed `newproject` evaluated as printed)

## git post-init hook never fires

Issues #99, #100, #101, #102 (all one family; #103 is the fourth split and is a
skill-text change, not this bug).

**Reproduction (Level 1).** A template dir holding an executable
`hooks/post-init` that writes a marker file, then `git -c init.templateDir=…
init newrepo`: the file lands in `newrepo/.git/hooks/post-init`, the marker is
never written. `git help githooks` lists 24 hook names; `post-init` is not one.

**Three candidates, one root.** The hardcoded clone path (#101) and the
incomplete copy list (#102) are real, but both live inside a helper that Git
never ran, so neither could explain "nothing appears". The disconfirming check
for both was the same: a hook with no path check and no copy list still never
fired. They surfaced only in the audit because it invoked the helper manually.

**Why it stayed invisible.** `tests/test-install-sh.sh` asserted the helper's
*text* (`copy_if_missing "tasks/history.md"`) rather than its *effect*, so a
mechanism that executed nowhere passed every test. Same shape as
[[a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos]] and
[[pre-push-force-guard-never-fires]]: present in the tree, wired to nothing.

**Fix shape.** There is no supported way to run code on `git init`, so the
entry point is a global alias the docs name honestly: `git scaffold`. The
template copy sits next to the script under `~/.agents/`, so the clone can live
anywhere (the test installs through a symlinked path with spaces). The
regression tests now `eval` the `newproject` function exactly as the installer
prints it, so the documented path is the tested path.

**Left as-is.** Old installs may still carry a dead `.git/hooks/post-init` in
repos created before this fix; it is inert. The installer removes the copy in
`~/.git-templates/hooks/` on the next run.
