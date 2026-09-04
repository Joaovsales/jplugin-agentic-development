# Route Decision

```json
{
  "author_association": "unknown",
  "auto_confirm": false,
  "autonomy": "gated-at-plan-and-pre-push",
  "baseline_revision": "c3809a1642f328dc286fa5266529e4d80fa43237",
  "baseline_worktree": {},
  "ceiling": {
    "channel_grant": "gated-at-plan",
    "content_ceiling": "autonomous",
    "label_grant": "gated-at-plan"
  },
  "decision_id": "9c8d05546da24bdaad8aaaa6371da9b1",
  "declared_paths": [
    "specs/wrap-up-gate-and-tdd-fold.md"
  ],
  "declared_radius": 1,
  "downgrades": [
    {
      "reason": "actual diff exceeded the declared scope",
      "signal": "runtime_tripwire"
    },
    {
      "reason": "actual diff exceeded the declared scope",
      "signal": "runtime_tripwire"
    },
    {
      "reason": "runtime tripwire did not pass before reviewer finalization",
      "signal": "runtime-tripwire"
    }
  ],
  "human_verification": {
    "judges": [],
    "needed": false
  },
  "ignored_directives": [],
  "independently_dispatched_reviews": true,
  "lane": "gated-at-plan-and-pre-push",
  "prelude": "/debug",
  "review_outcomes": {
    "code-reviewer": "completed"
  },
  "reviewers": [
    "code-reviewer"
  ],
  "runtime_tripwire": {
    "actual_radius": 7,
    "changed_paths": [
      ".agents/skills/task-registry/references/configuration.md",
      ".agents/skills/task-registry/templates/task-tracking.md",
      ".claude/skills/task-registry/references/configuration.md",
      ".claude/skills/task-registry/templates/task-tracking.md",
      "CLAUDE.md",
      "specs/wrap-up-gate-and-tdd-fold.md",
      "tasks/history.md",
      "tasks/solutions/bugs/task-registry-provider-selection-docs-drift.md",
      "tests/test-doc-conventions.sh"
    ],
    "outside_declared_paths": [
      ".agents/skills/task-registry/references/configuration.md",
      ".agents/skills/task-registry/templates/task-tracking.md",
      ".claude/skills/task-registry/references/configuration.md",
      ".claude/skills/task-registry/templates/task-tracking.md",
      "CLAUDE.md",
      "tasks/history.md",
      "tasks/solutions/bugs/task-registry-provider-selection-docs-drift.md",
      "tests/test-doc-conventions.sh"
    ],
    "overflow": true,
    "status": "failed"
  },
  "task_reference": "https://github.com/Joaovsales/jplugin-agentic-development/issues/95",
  "unresolved_review_findings": [],
  "verification_method": "link-check"
}
```
