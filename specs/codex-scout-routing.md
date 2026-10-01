---
implementation_paths:
  - config/agent-policy.toml
  - scripts/agent-policy
  - scripts/agent_policy/**
  - scripts/render-codex.py
  - scripts/install-codex.sh
  - .agents/references/model-routing.md
  - .agents/skills/how/SKILL.md
  - .agents/skills/why/SKILL.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/prd/SKILL.md
  - .agents/skills/grilling/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - tests/test-agent-policy.sh
  - tests/test-codex-install.sh
  - tests/test-model-tiers.sh
  - tests/test-how-why-skills.sh
  - tests/test-doc-conventions.sh
  - tests/fixtures/agent-policy/**
  - README.md
---

# Spec: Codex Scout Routing

> Origin: [#158](https://github.com/Joaovsales/jplugin-agentic-development/issues/158), child of [#157](https://github.com/Joaovsales/jplugin-agentic-development/issues/157) · Designed 2026-09-29 · Review status: **draft; critic 1 applied, 0 declined**
> Visual: specs/codex-scout-routing.plan.html

## Problem

Codex users see read-heavy explorer children inherit the parent's model and effort because the installed agent files do not select either. The Codex adapter resolves workflow roles from the canonical policy, installs a bounded Scout profile, and explains configuration drift. Claude/Pi emission and usage receipts remain in sibling issues [#159](https://github.com/Joaovsales/jplugin-agentic-development/issues/159) and [#164](https://github.com/Joaovsales/jplugin-agentic-development/issues/164).

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Scout model | Codex Scout resolves to `gpt-6-luna` with a supported effort; a managed explorer never inherits the parent model | user; #158 | rendered TOML and effective-route fixtures |
| Other Codex tiers | Planner = `gpt-6-astra`/high, Builder = `gpt-6.1-sol`/medium, Reviewer = `gpt-6.1-sol`/medium; Ceiling inherits, subject to floors | inferred from existing tier purposes; #157 | policy mapping fixtures and reviewer check |
| High-stakes routing | Ceiling roles inherit the parent model unless a documented floor requires escalation; no fixed Scout default silently caps them | #157; #158 | policy resolver and doctor fixtures |
| User ownership | Unrelated config keys and genuinely personal agents remain byte-identical; ambiguous legacy files are reported, not overwritten | #157; #158 | migration fixtures and repeat-install comparison |
| Read-only exploration | Code reconnaissance uses a read-only Scout profile; MCP-backed `/why` investigators retain the tool access they require | #158; `.agents/skills/why/SKILL.md:83-85` | role config and skill-dispatch tests |
| Concurrency | Generated Codex default permits at most 3 child threads per session; a user override is retained and diagnosed if it exceeds policy | inferred from #158 and the local 4-slot limit | config merge and doctor fixtures |
| Install rollback | Applying generated config is previewable and opt-in where an existing file changes ownership; backups permit restoring prior user content | #157; #158 | migration and rollback fixtures |
| Compatibility | A fresh `install-codex.sh` remains repeatable and existing unrelated hooks/skills remain intact | `scripts/install-codex.sh:50-76` | `tests/test-codex-install.sh` |
| Runtime support | The policy parser either supports the installer's Python runtime or fails with the minimum version before writing any file | inferred from `scripts/install-codex.sh:20-48` | isolated installer fixture |
| Effective-config provenance | `doctor` includes trusted project and selected profile layers when supplied and labels CLI/cloud/session layers unknown when unavailable; user-scope install success alone is not an effective-route claim | official Codex config precedence | layered-config fixtures |

## System design

### Current state

```text
.agents/agents/*.md --parse_agent--> scripts/render-codex.py:64-118
    --render_agents--> ~/.codex/agents/*.toml (name, description, instructions)
scripts/install-codex.sh:50-58 calls that renderer after copying skills.
.agents/skills/how/SKILL.md:23-29 names Claude Explore and Pi scout;
    Codex has no explicit route. No policy/config/agent-policy.toml exists.
```

### Ownership

| Component | Owns | Reads |
|-----------|------|-------|
| `config/agent-policy.toml` (NEW; #157 foundation) | Semantic role, tier, lane, effort, and budget intent; Codex provider model map | Existing tier language in `.agents/references/model-routing.md:7-17` |
| `scripts/agent-policy` (NEW; #157 foundation) | Validation, lane/role resolution, read-only `explain` and `doctor`, preview and apply boundary | Policy and Codex config layers visible in the inspection context |
| Codex emitter in `scripts/agent_policy/` (NEW) | Native Codex TOML and config merge plan | Resolved policy, canonical persona instructions, Codex's native precedence |
| `scripts/install-codex.sh` | User-scope install entry point | Render/apply interface, canonical skills/hooks |
| Skill dispatch instructions | Choice of role for a task, including `/how` explorer versus `/why` investigator | Semantic Scout/Ceiling policy; no concrete model ID |

### Interaction

```text
skill/routine --(1 sync: lane + role)--> policy resolver (NEW)
installer/CLI --(2 sync: render/explain/doctor)--> Codex emitter (NEW)
Codex emitter --(3 sync: inspect/preview/apply)--> ~/.codex/agents/*.toml,
                                               ~/.codex/config.toml
Codex host --(4 sync: spawn named role)--> selected agent config
```

| Arrow | On failure or timeout | On duplicate |
|-------|-----------------------|--------------|
| (1) | Unknown or unsupported lane/role is an actionable error; no silent parent-model fallback | Deterministic resolution |
| (2) | Invalid policy or unsupported model/effort aborts before any write | Deterministic render bytes |
| (3) | Read or parse failure stops apply; a partial write is recoverable from the original backup | Reapply makes no change |
| (4) | Missing/unmanaged role is visible to `doctor` and the caller; live host failures are reported by the caller | Each spawn is a new task; no persistent state mutation by exploration |

### Failure unit

Policy validation and preview fail independently of a Codex session. A failed or ambiguous apply leaves existing personal configuration intact; a missing Scout route can affect one delegated investigation and does not prevent the parent from reporting the gap.

## Component contracts

### Policy resolution (#157 shared foundation)

```text
resolve(policy, harness="codex", lane, role, parent_model) -> Route | Unsupported | InvalidPolicy
```

`Route` includes semantic tier, concrete model or explicit inheritance, effort, permission intent, and supported limits. `Unsupported` names the missing capability or mapping. Resolution is pure and repeatable; no file or network access occurs. Schema version changes require an explicit migration or refusal, never an implicit reinterpretation.

### Codex render and inspection

```text
render(policy, canonical_agents) -> DesiredCodexFiles | Unsupported | InvalidPolicy
inspect(desired, context) -> Match | Missing | ManagedDrift | LegacyCandidate | PersonalConflict | InvalidInstalled | UnknownLayer
```

Render emits deterministic native TOML for every canonical workflow role plus a named `explorer` profile and an MCP-capable `scout` profile. Both use the Scout model; `explorer` explicitly uses Codex's read-only sandbox, while `scout` retains the MCP tools `/why` needs and still receives read-only task instructions. It sets model and effort for routine roles, leaves both fields absent for Ceiling inheritance, and represents floors in the resolver/dispatch instructions. Effective `agents.default_subagent_model` or `agents.default_subagent_reasoning_effort` makes apply refuse conflicting user-scope configuration and makes doctor name the winning key and layer; the adapter preserves user content for its owner to resolve. Inspection takes the Codex home, current project directory and trust state, project-scoped agent files, selected profile, known CLI overrides, and parent model as context. A required floor is reported separately from the visible model until a spawn override is supplied; policy intent alone never proves an effective dispatch. An unavailable higher-priority layer produces `UnknownLayer`, not a healthy effective-route claim. A `LegacyCandidate` matches a known old generated shape exactly; a `PersonalConflict` is never automatically changed.

### Codex preview and apply

```text
preview(desired, installed) -> Plan(actions, conflicts)
apply(plan, codex_home, *, explicit_opt_in) -> Applied | Refused | Failed
```

The preview names each create/update/migration and the backup path. Apply refuses ambiguous conflicts, backs up changed user-owned settings, writes atomically, and is idempotent on retry. Existing `install-codex.sh` remains the user entry point; it never silently adopts a personal file. There is no network call, so timeout is not applicable.

## Data models

### Versioned policy and route

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `schema_version` | positive integer | Unknown versions are refused | parser |
| `tier`, `role`, `lane` | named entries | Every dispatched role resolves exactly once | policy validator |
| Codex provider mapping | model ID + supported effort | Scout maps to `gpt-6-luna`; a missing mapping is an error | resolver and fixtures |
| `inherit_model` | boolean | True only where the semantic tier requires inheritance | resolver |
| permission and limits | typed capability fields | Unsupported fields are diagnosed, never reported as enforced | emitter and doctor |
| inspection context | cwd/trust, project agent files, profile, CLI overrides, parent model | Every effective field has a winning layer or an explicit unknown-provenance result | doctor |
| parent model input | effective Codex model or explicit doctor argument | Unknown parent model is reported as unresolved inheritance, never as a measured cost | doctor |

### Installed-file classification

| State | Meaning | Permitted action |
|-------|---------|------------------|
| `missing` | No file at expected path | Create managed file |
| `managed` | Current marker and valid shape | Refresh if drifted |
| `legacy_candidate` | Unmarked file matches a known renderer shape | Preview migration; explicit opt-in to adopt |
| `personal_conflict` | Unmarked file does not match a known shape | Preserve and report |
| `invalid` | File cannot be safely parsed | Preserve and report error |

### Illegal states and transitions

| Illegal state | Prevented by |
|---------------|--------------|
| Ceiling route marked inheriting while a global default changes its effective model or effort | Resolver/doctor effective-precedence check |
| Floor target reported as effective without a verified spawn override | Effective-route and doctor provenance checks |
| Scout role with no concrete model or unsupported effort | Policy validation |
| Ambiguous unmarked file rewritten as managed | Exact legacy classifier and explicit apply gate |
| Doctor claims a cap that Codex cannot enforce | Capability-aware `Unsupported` result |

| From | To | Trigger |
|------|----|---------|
| `missing` | `managed` | Explicit install/apply creates it |
| `managed` | `managed` | Idempotent refresh |
| `legacy_candidate` | `managed` | Previewed opt-in migration with backup |
| `personal_conflict` / `invalid` | same state | Installer/doctor reports; user repairs separately |

### Migration and compatibility

The known old shape is the three-key TOML emitted by `scripts/render-codex.py:112-118`; classification also checks agent identity and instructions before offering migration. The adapter keeps original user content in a backup before adopting a legacy file. Re-running the current installer preserves unrelated personal agents, hooks, skills, and config keys (`tests/test-codex-install.sh:35-54,69-87`). Rollback restores backups and the previous installer behavior; no persisted application data changes.

## Build Order

Sizing: 6 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1 spans config, scripts, and tests because the versioned schema must be validated with its resolver; slice 4 spans the routing reference, two skills with different tool contracts, and tests; slice 5 spans four existing Scout dispatch skills plus their shared guard and README, which must agree before Codex routing is advertised.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Policy contract and resolver | Versioned #157 policy foundation resolves Codex lanes and roles and explains unsupported mappings | `config/agent-policy.toml`, `scripts/agent-policy`, `scripts/agent_policy/**`, `tests/test-agent-policy.sh`, `tests/fixtures/agent-policy/**` | — | 1 | `bash tests/test-agent-policy.sh` | 5 paths · 3 systems · 1 AC |
| 2 | Managed Codex role rendering | Native TOML covers canonical roles plus Scout, with correct Ceiling and floor outcomes | `scripts/agent_policy/**`, `scripts/render-codex.py`, `tests/test-agent-policy.sh`, `tests/test-codex-install.sh`, `tests/fixtures/agent-policy/**` | 1 | 2, 3 | `bash tests/test-agent-policy.sh && bash tests/test-codex-install.sh` | 5 paths · 2 systems · 2 ACs |
| 3 | Safe Codex install and migration | Concurrency default, previewed legacy adoption, backups, and repeatable install | `scripts/agent_policy/**`, `scripts/install-codex.sh`, `scripts/render-codex.py`, `tests/test-agent-policy.sh`, `tests/test-codex-install.sh`, `tests/fixtures/agent-policy/**` | 2 | 6, 7 | `bash tests/test-agent-policy.sh && bash tests/test-codex-install.sh` | 6 paths · 2 systems · 2 ACs |
| 4 | How and why Scout dispatch | `/how` uses managed explorer; `/why` uses an MCP-capable Scout investigator | `.agents/references/model-routing.md`, `.agents/skills/how/SKILL.md`, `.agents/skills/why/SKILL.md`, `tests/test-how-why-skills.sh`, `tests/test-model-tiers.sh` | 2 | 4 | `bash tests/test-how-why-skills.sh && bash tests/test-model-tiers.sh` | 5 files · 4 systems · 1 AC |
| 5 | Other Scout dispatch and guidance | Remaining Scout skills and Codex floor dispatch name the effective roles; the install guide shows routing | `.agents/skills/plan/SKILL.md`, `.agents/skills/build/SKILL.md`, `.agents/skills/prd/SKILL.md`, `.agents/skills/grilling/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `tests/test-model-tiers.sh`, `tests/test-doc-conventions.sh`, `README.md` | 4 | 5 | `bash tests/test-model-tiers.sh && bash tests/test-doc-conventions.sh` | 8 files · 7 systems · 1 AC |
| 6 | Codex doctor and conformance | Read-only doctor reports effective routes, inherited expense, and missing caps with fixture-backed traces | `scripts/agent_policy/**`, `scripts/agent-policy`, `tests/test-agent-policy.sh`, `tests/fixtures/agent-policy/**` | 3, 5 | 8 | `bash tests/test-agent-policy.sh` | 4 paths · 2 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/codex-scout-routing.md`.
Plan: `## Plan: codex-scout-routing` in `tasks/todo.md`, 6 slices, ready set 1.
Files: config/agent-policy.toml, scripts/agent-policy, scripts/agent_policy/**, scripts/render-codex.py, scripts/install-codex.sh, .agents/references/model-routing.md, .agents/skills/how/SKILL.md, .agents/skills/why/SKILL.md, .agents/skills/plan/SKILL.md, .agents/skills/build/SKILL.md, .agents/skills/prd/SKILL.md, .agents/skills/grilling/SKILL.md, .agents/skills/system-design-planning/SKILL.md, tests/test-agent-policy.sh, tests/test-codex-install.sh, tests/test-model-tiers.sh, tests/test-how-why-skills.sh, tests/test-doc-conventions.sh, tests/fixtures/agent-policy/**, README.md.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/codex-scout-routing.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Codex Scout uses `gpt-6-luna`; the Codex model map lives in the policy, not skill prose.
Constraints: Named Scout roles are pinned; a global model default does not silently cap Ceiling roles.
Constraints: The minimal #157 foundation ships here; Claude/Pi emitters and usage receipts remain #159/#164.
Constraints: Personal configuration is preserved, and legacy adoption is previewed and backed up.
```

## Decisions

| Decision | Options | Chosen / recommended | Source | Wrong when |
|----------|---------|----------------------|--------|------------|
| Scope | Full #158 / `/how` guidance only | Full #158 | user | Only guidance would leave the inherited-model install defect |
| Codex Scout model | `gpt-6-luna` / unset | `gpt-6-luna` | user | The account cannot use this model; a live spawn must fail clearly because static doctor cannot prove account entitlement |
| Global model default | Pin named Scout role / set global Luna default | Pin named Scout role | assumed | Global default is right only if Ceiling inheritance has an explicit compatible resolution |
| Relationship to #157 | Include minimal shared foundation / block on separate #157 delivery | Include minimal shared foundation and leave Claude/Pi emitters to #159 | assumed | Separate prerequisite is right if #157 is already being built independently |
| Codex non-Scout mapping | Explicit models for Planner/Builder/Reviewer / inherit | Planner = `gpt-6-astra`/high; Builder and Reviewer = `gpt-6.1-sol`/medium | assumed | A provider model is unavailable or no longer matches the tier purpose |
| Legacy unmarked files | Exact-shape previewed adoption / unconditional overwrite | Exact-shape previewed adoption | #158 | Candidate detection cannot prove template origin |

## Acceptance Criteria

- A versioned canonical policy resolves Codex lanes and every workflow role to a semantic tier, effective model/effort, permissions, and supported limits; `explain` shows the full trace and refuses unknown or ambiguous input (#157 foundation).
- The Codex emitter produces deterministic managed TOML for every canonical workflow role and a read-only explorer/Scout profile using `gpt-6-luna`; routine roles do not accidentally inherit the parent model (#158).
- Ceiling inheritance and documented floors resolve correctly under actual Codex precedence; no global setting silently changes a high-stakes role to Scout (#158).
- `/how` selects the managed Codex explorer for code reconnaissance and a Ceiling explainer for synthesis; `/why` selects an MCP-capable Scout investigator; model IDs live in the provider mapping, not in skill prose (#158).
- The shared routing reference and other Scout-using skills select named Codex Scout roles for read-heavy work; Codex floor dispatch uses the resolved parent tier and does not change Claude/Pi routes (#158).
- Codex concurrency has a conservative documented default or a diagnosis when absent, and an explicit override path (#158).
- Installation previews and safely migrates only known old generated shapes, preserves genuinely personal agents and unrelated config, creates backups before adopting user-owned files, and is idempotent (#158).
- `doctor --harness codex` names inherited expensive roles, missing caps, and responsible config layers or agent files, or reports unknown provenance; conformance tests cover project agent shadows, layered precedence, rendering, migration, drift, repeat installs, and unrelated configuration (#158).

## Implementation Paths

- `config/agent-policy.toml`, `scripts/agent-policy`, `scripts/agent_policy/**` — canonical intent, resolution, CLI, and Codex native emitter/inspector.
- `scripts/render-codex.py`, `scripts/install-codex.sh` — compatibility entry points and safe user-scope installation.
- `.agents/references/model-routing.md` and the listed `.agents/skills/*/SKILL.md` paths — semantic tier, Ceiling/floor, and Codex Scout dispatch guidance.
- `tests/test-agent-policy.sh`, `tests/fixtures/agent-policy/**`, `tests/test-codex-install.sh`, `tests/test-model-tiers.sh`, `tests/test-how-why-skills.sh`, `tests/test-doc-conventions.sh` — contract and regression verification.
- `README.md` — Codex install, preview, migration, and diagnosis commands.
