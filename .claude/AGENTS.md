# Available Subagents

> This file documents agents available for Claude Code (`.claude/agents/`) and other AI coding tools.
> In Claude Code, agents are invoked via the Agent tool with `subagent_type`.

## Claude Code Agents (`.claude/agents/`)

### Planning & Architecture
| Agent | Purpose |
|-------|---------|
| `planner` | Spec writing, task breakdown, requirements interview, architecture decisions |

### Development
| Agent | Purpose |
|-------|---------|
| `backend-developer` | APIs, databases, auth, caching, performance, OWASP security |
| `frontend-developer` | React/Vue/Angular components, responsive UI, accessibility |
| `frontend-design-validator` | Validate UI against design reference documents |

### Quality & Security / Design
| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Post-implementation quality review — Clean Code, SOLID, bugs |
| `code-debugger` | Root-cause analysis for errors, test failures, runtime bugs |
| `security-reviewer` | OWASP checks, injection vectors, auth flows, data exposure |
| `software-design-expert-review` | Read-only APOSD structural review — depth, leakage, coupling, unknown unknowns, error design |
| `test-engineer` | Contract tests from spec and stubs before implementation (Write job); test adequacy review against the freeze lines (Review job) |

### Utilities
| Agent | Purpose |
|-------|---------|
| `context-document-optimizer` | Compress large docs for token-efficient AI context |

---

## Usage in Claude Code

The Agent tool accepts a `subagent_type` matching the filename in `.claude/agents/` (without `.md`):

```
subagent_type: "planner"
subagent_type: "backend-developer"
subagent_type: "code-reviewer"
subagent_type: "security-reviewer"
```

For agents not in `.claude/agents/`, use `general-purpose` and describe the role in the prompt.

## Delegation Guidelines

- **One task per agent** — focused context produces better outputs
- **Chain agents** — design → implement → review → security scan
- **Reference files explicitly** — use @filename or provide full paths in the prompt
- **Validate outputs** — always check agent work before moving to the next step
