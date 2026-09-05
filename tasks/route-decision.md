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
    "content_ceiling": "gated-at-plan-and-pre-push",
    "label_grant": "gated-at-plan"
  },
  "decision_id": "c2ec2147bbb941389a4fbfe445fec400",
  "declared_paths": [
    ".agents/skills/sync/",
    ".claude/skills/sync/",
    "tests/"
  ],
  "declared_radius": 1,
  "downgrades": [
    {
      "reason": "irreversible or outward-facing work requires a human gate",
      "signal": "irreversible_or_outward_facing"
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
  "prelude": "skip: not needed for this kind",
  "review_outcomes": {
    "code-reviewer": "completed",
    "security-reviewer": "completed"
  },
  "reviewers": [
    "code-reviewer",
    "security-reviewer"
  ],
  "runtime_tripwire": {
    "actual_radius": 6,
    "changed_paths": [
      ".agents/skills/sync/SKILL.md",
      ".agents/skills/sync/scripts/sync-retire.py",
      ".claude/skills/sync/SKILL.md",
      ".claude/skills/sync/scripts/sync-retire.py",
      "specs/sync-deterministic-retirement.md",
      "tasks/checkpoint.md",
      "tasks/details/glob-matcher-shared-module.md",
      "tasks/details/sync.syncable-paths-single-source.md",
      "tests/test-sync-retirement.sh"
    ],
    "outside_declared_paths": [
      "specs/sync-deterministic-retirement.md",
      "tasks/checkpoint.md",
      "tasks/details/glob-matcher-shared-module.md",
      "tasks/details/sync.syncable-paths-single-source.md"
    ],
    "overflow": true,
    "status": "failed"
  },
  "task_reference": "sync.deterministic-retirement",
  "unresolved_review_findings": [],
  "verification_method": "tests"
}
```
