---
title: A gate that ships into a template dir never reaches existing repos
date: 2026-09-02
problem_type: pattern
module: install.sh, .agents/git-hooks, .agents/skills/sync
tags: [git-hooks, deployment, install, enforcement, dead-mechanism]
applies_when: Adding or changing a git hook that the installer distributes
date_source: session
---

## A gate that ships into a template dir never reaches existing repos

`install.sh` copied `pre-push` into `$GIT_TEMPLATE_DIR/hooks/` and set
`init.templateDir`. Git applies a template only to repositories created
**afterwards**, so every already-cloned repo — including this one — never
received the hook. Verified: this repository's `--git-common-dir/hooks` held only
`pre-push.sample`, meaning even the pre-existing typecheck/lint gate had never
run here.

**The failure mode is silence.** The file exists in the tree, tests can assert
its content, reviewers can read it — and it executes nowhere. This is exactly how
`.claude/hooks/pre-push-guard.sh` ended up deprecated: present, wired to nothing.

**Rule:** a distribution mechanism is not an installation mechanism. Any hook the
template ships needs three things, and shipping fewer than three ships a
decoration:

1. the template dir, for repos created later,
2. an install into `--git-common-dir/hooks` for the repo in hand
   (worktrees share it, so one copy covers all of them),
3. a `/sync` step, because a sync updates the file in the tree while git keeps
   running the copy under `.git/hooks`.

**Check before trusting any hook-based guarantee:**
`ls "$(git rev-parse --git-common-dir)/hooks/"` — a `.sample` suffix means it is
not installed.

Related: [[pre-push-force-guard-never-fires]]
