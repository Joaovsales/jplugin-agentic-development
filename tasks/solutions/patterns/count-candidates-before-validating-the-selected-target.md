---
title: Count candidates before validating the selected target
date: 2026-08-30
problem_type: pattern
module: .agents/skills/maintain-verification-skill, .agents/skills/verify
tags: [skills, discovery, ambiguity, validation, lifecycle]
applies_when: two or more chained workflow stages discover and operate on the same class of project-local resource
---

When chained consumers resolve the same resource type, they must first count the
same raw candidate set and only then validate the uniquely selected candidate.
Filtering malformed candidates during discovery makes one stage silently ignore
an ambiguity that the next stage rejects.

The verification maintainer now counts every canonical `verify-*` directory
before checking its required files (`.agents/skills/maintain-verification-skill/SKILL.md:34`).
That matches the E2E resolver, which also discovers canonical `verify-*` entries
before selecting exactly one (`.agents/skills/verify/SKILL.md:123`).

Apply this order whenever stages share a discovery boundary:

1. Discover and count raw candidates with one common rule.
2. Stop on zero or ambiguity according to the shared contract.
3. Validate the contents of the single selected target.
4. Test malformed extra candidates so filtering cannot silently change cardinality.
