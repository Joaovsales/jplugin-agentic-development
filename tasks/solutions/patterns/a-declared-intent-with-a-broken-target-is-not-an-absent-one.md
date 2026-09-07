---
title: A declared intent with a broken target is not an absent one
date: 2026-09-06
problem_type: pattern
module: .agents/skills/task-registry/scripts/registry/config.py
tags: [configuration, silent-failure, three-states, pointers, defaults]
applies_when: Resolving an optional pointer, override, or config path where "not declared" legitimately falls back to defaults
---

## The failure shape

An optional declaration has three states, and the tempting code handles two:

| State | Right behaviour |
|---|---|
| not declared | defaults, silently — that is what optional means |
| declared, target usable | use it |
| **declared, target unusable** | **refuse, naming the declaration and the target** |

`if os.path.isfile(target): return target` followed by a fall-through to the
default collapses the third state into the first. The project then runs on
defaults while its own instructions say it is configured, and the only tool that
could have said so reports "configuration: none" (#82,
`.agents/skills/task-registry/scripts/registry/config.py:261`). The same shape swallowed a path-escape error in the
sibling branch.

## The rule

"Absent is not an error" licenses silence for *absent*. A declaration you found
and could not honour is a broken configuration and gets the malformed-file
treatment: refuse, name the declaring file and the declared path, say how to
fix it. Keep the diagnostic command reachable — load non-strictly there and
render the fault instead — so the failure is inspectable exactly when it fires.

Check the sibling branches of the same resolver: a `try/except: continue` next
to the `isfile` fall-through is the same bug wearing a different exception.

## The template corollary

A template-managed file must never emit a live pointer to a path outside the
sync boundary. It ships the declaration to every consumer and can never ship
the target, so every consumer inherits the third state by construction.
Document the convention with a placeholder the parser treats as inert — here
`<path>`, because the pointer regex stops at a backtick but does not require
one, so a backticked concrete path still matches. Pin it with a test that
resolves any live pointer it finds, not one that asserts the pointer is present.

Related: [[validate-in-the-loader-not-in-one-optional-command]] — a gate that
exists but never runs; this is a gate that runs and returns the wrong answer.
