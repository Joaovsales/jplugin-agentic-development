# Spec: Superpowers Best Practices Adoption

## Behavior
Incorporate high-value patterns from the Superpowers workflow into our coding-agent-workflow, organized in 3 tiers by impact and effort.

## Inputs
- Analysis of obra/superpowers repo (skills, hooks, agents, patterns)
- Current coding-agent-workflow structure

## Outputs
- New skills: `/verify-evidence`, `/brainstorm`, `/receive-review`, `/writing-skills`
- Enhanced skills: `/build`, `/debug`, `/tdd`, `/wrap-up-session`
- New reference documents in skill directories
- Updated session-start hook and CLAUDE.md

## Acceptance Criteria

### Tier 1 — High Impact, Low Effort
- [ ] `/verify-evidence` skill created with iron law, gate function, rationalization table
- [ ] `/tdd` skill enhanced with iron law, rationalization table, testing anti-patterns reference
- [ ] `/debug` skill enhanced with architecture questioning after 3 failed fixes, user signal recognition
- [ ] `/build` skill enhanced with 2-stage review (spec compliance + code quality)

### Tier 2 — High Impact, Medium Effort
- [ ] `/brainstorm` skill created with divergent design phase, multi-option proposals
- [ ] `/receive-review` skill created with anti-performative-agreement, pushback protocol
- [ ] `/build` enhanced with parallel dispatch pattern for independent tasks
- [ ] `/debug` reference docs added (root-cause-tracing.md, defense-in-depth.md, condition-based-waiting.md, find-polluter.sh)

### Tier 3 — Medium Impact, Medium Effort
- [ ] `/wrap-up-session` enhanced with worktree merge-to-main flow and verification gate
- [ ] `/writing-skills` meta-skill created for authoring new skills
- [ ] Session-start hook enhanced with skill awareness injection
- [ ] CLAUDE.md updated with new skills table entries
