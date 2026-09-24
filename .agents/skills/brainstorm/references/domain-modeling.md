# Domain modeling — the layer active inside `/brainstorm` Step 3

Reference for `/brainstorm`. While `/grilling` runs the interview, these six
moves run inside it: they sharpen the project's vocabulary and record the
decisions that deserve recording, at the moment each one crystallises. This
repository's glossary is `tasks/concepts.md` and its decision record is the
typed learning store's knowledge track. Upstream's `CONTEXT.md` and `docs/adr/`
have no equivalent here and are not created.

## Challenge against the glossary

When the user uses a term that conflicts with an entry in `tasks/concepts.md`,
call it out before the round continues, as a frontier question: "The glossary
defines *register* as X, but you seem to mean Y. Which is it?"

## Sharpen fuzzy language

When a term is vague or overloaded, propose a precise canonical term as a
frontier question with a ➡️ recommendation: "You say 'account'. Customer or
User? Those are different things here."

## Discuss concrete scenarios

When a relationship between concepts is being settled, stress-test it with an
invented edge-case scenario that forces the boundary to be stated: "A routine
claims an issue and the tracker never created the claim label. Is that issue
claimed?" Invent the scenario; do not wait for the user to supply one.

## Cross-reference with code

When the user states how the code behaves, check the tree before accepting it.
Surface a contradiction with the line that proves it, cited as `file:line`:
"`registry/detail.py:88` renders the marker from the index row, but you just
said the detail block is the source of truth. Which is right?"

## Write the glossary inline

When a project-specific term resolves, write it to `tasks/concepts.md` right
then, not at the end of the session. A term resolves when the user's answer
settles what it means; the reply to that answer writes the entry first and asks
the next round second. Naming a term as "new vocabulary" and moving on is not a
write. The entry format and rules are `/learn`
§ Capture New Concepts: `- **term** — definition.`, alphabetical within its
section, an existing term refined in place rather than duplicated, standard
industry terms excluded. If the file is absent, recreate the seed exactly as
that section specifies; the rule is referenced, not restated here.

The glossary is a glossary and nothing else: it holds definitions. Implementation
detail, decisions, spec-like prose and open questions never enter it. A write that
would carry any of them is refused, and the content goes to the spec or to an
architecture decision instead.

## Offer an architecture decision sparingly

Offer to record a decision only when all three gates hold at once:

1. **Hard to reverse** — changing course later costs something real.
2. **Surprising without context** — a future reader would ask "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and one was picked for specific reasons.

The offer is a frontier question with a ➡️ recommendation; the user decides.
When a gate fails, say which one and write nothing. On yes, score overlap
against the existing documents first (`/learn` § Score Overlap Before Writing:
4 to 5 dimensions matched updates the existing document in place, never a
sibling), then write `tasks/solutions/architecture/<slug>.md` on the knowledge
track:

```yaml
---
title: <imperative statement of the decision>
date: YYYY-MM-DD
problem_type: architecture-decision
module: <area the decision governs>
tags: [two, to, five, lowercase-kebab, tags]
applies_when: <the situation in which this decision should be recalled>
---
```

The body is at least one to three sentences stating the context, the decision
and the reason, in that order. Slug rules are the store's
(`tasks/solutions/README.md`): a stable ASCII kebab-case slug from the title,
the date in frontmatter only.

## Provenance

Adapted from `skills/engineering/domain-modeling/SKILL.md` in
[mattpocock/skills](https://github.com/mattpocock/skills) at revision
`c55ee46073ed923f86ce59a5eb3b6d895095d1b7` (MIT; see `THIRD_PARTY_NOTICES.md`).
The six moves and the three decision gates are upstream's. The file targets,
the `/learn` entry format and the overlap scoring are this repository's.
