---
name: grill-me
description: A relentless interview to sharpen a plan, decision, or idea, typed by the user and never started by the agent. Use when the user says 'grill me' about something.
argument-hint: "[plan, decision, or idea to grill]"
disable-model-invocation: true
harness: universal
---

# /grill-me — Stateless Grilling

Invoke `/grilling` with the argument as the root of the design tree, and do
nothing else.

## Constraints

- Writes no files: no spec, no glossary entry, no store document, no
  `tasks/todo.md` row. The settled tree lives in the conversation.
- Needs no repository, and the subject does not have to be software.
- When the subject is a feature in the current repository, say so and point the
  user at `/brainstorm`, which runs the same interview and records what it
  settles. Continue here only if they still want the stateless version.

## Why the flag is `true`

This is a user-only front door: the agent must never decide on its own to grill
someone. `/grilling` itself stays model-invocable so that `/brainstorm` and other
skills can call it. The rule and its harness check are in `/writing-skills`
§ YAML Frontmatter.

## Provenance

Adapted from `skills/productivity/grill-me/SKILL.md` in
[mattpocock/skills](https://github.com/mattpocock/skills) at revision
`c55ee46073ed923f86ce59a5eb3b6d895095d1b7`. The upstream MIT notice is bundled
as `LICENSE.mattpocock`; repository-level provenance is in
`THIRD_PARTY_NOTICES.md`.
