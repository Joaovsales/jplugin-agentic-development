---
title: Hardening a list of exec-capable knobs misses the ones that choose targets
date: 2026-09-05
problem_type: security
module: .agents/skills/sync/scripts/sync-retire.py
tags: [git, untrusted-input, config, deletion, sync]
symptoms: identical template content produced different retirement sets depending on one line in the untrusted checkout's .git/config
root_cause: the git hardening enumerated knobs that execute commands; core.quotePath executes nothing but decides how paths are spelled, and the deletion set is keyed on those strings
resolution: pass -z to the history walk so git never quotes, removing the dependence instead of pinning the knob (sync-retire.py, template_history_blobs)
---

## The rule

When you harden against untrusted configuration, enumerate by **what the config
can influence**, not by what it can execute. A knob that runs no command can
still choose which file gets deleted.

## What happened

Reading an untrusted template checkout with git executes that checkout's config —
`core.fsmonitor` names a command git runs on `ls-files`. That was found and fixed
by pinning the exec-capable knobs on the command line (`-c` outranks repo config)
and dropping system and global config.

The fix was correct and incomplete, because the list was built from one question:
*which knobs run a command?* `core.quotePath` runs nothing. It decides whether
`git log --raw` C-quotes paths holding non-ASCII bytes. The provenance map was
keyed on those strings while the project side used raw bytes, so:

```
quotePath=true    candidate: .claude/hooks/café.sh   ← held for a human
quotePath=false   retire:    .claude/hooks/café.sh   ← deleted
```

Same template content, same project, one line of someone else's config. It also
broke the acceptance criterion that `--from-ref` and `--from-dir` agree, since
the knob is read from the project in one mode and the template in the other.

## Prefer removing the dependence to pinning the knob

`-c core.quotePath=false` would have worked and would have been wrong in kind: it
adds a second entry to the same fragile enumeration. `-z` makes git emit
NUL-separated raw bytes, so no configuration can affect the spelling at all. When
a knob can be made irrelevant, make it irrelevant.

## Where the enumeration is still an enumeration

The exec-knob pin remains a list, and lists rot. What bounds it here is that the
script uses six read-only subcommands with no pager, no patch generation and no
network — verified by testing `core.pager`, `diff.external`,
`core.alternateRefsCommand`, `uploadpack.packObjectsHook` and `core.sshCommand`,
none of which fire. That reasoning belongs in the code, because the next
subcommand added is what invalidates it.

Related: [[running-git-in-an-untrusted-checkout-executes-its-config]].
