# Provider Configuration Guide

Reference for `/task-registry`. The starting file is `templates/task-tracking.md`;
this document explains what each provider does with it, and what to do when
something fails.

---

## Discovery and selection

The registry looks for its configuration in this order:

1. a `Task tracking instructions: <path>` line in `.claude/project.md`,
   `AGENTS.md`, or `CLAUDE.md`, searched in that order — the first path found
   wins. Project-owned files come first because `CLAUDE.md` is template-managed
   and `/sync` overwrites it;
2. `docs/task-tracking.md`;
3. nothing — configuration defaults apply; provider auto-selection still follows
   the table below.

Every path the configuration names — the pointer target, the index, the detail
directory — must resolve inside the project root. One that escapes is refused,
because the configuration arrives as a file in the repository and a file in the
repository must not be able to make the tool read or write somewhere else.

Then it selects a provider:

| Precedence | Condition | Result |
|-----------|-----------|--------|
| 1 | `provider =` set in the configuration | that provider, always |
| 2 | GitHub remote **and** `gh auth status` exits 0 | `github` |
| 3 | anything else | `local` |

**Jira is never reached by inference.** Credentials in the environment do not
select it; only `provider = jira` does. A tracker that other teams depend on is
not something a tool should start writing to because it could.

`doctor` prints the selection and the reason:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py doctor
```

---

## GitHub

Driven through the `gh` CLI — the same tool `/wrap-up-session` already uses for
PRs — so it inherits existing auth and adds no dependency.

### Reading the existing label vocabulary

The mapping is a *reading*, not a rename. These are the defaults, matching the
label set this harness already ships:

| Label | Becomes | Notes |
|-------|---------|-------|
| `bug` | kind `bug` | |
| `enhancement` | kind `feature` | |
| `design-decision` | kind `decision` | |
| `question` | *unmapped by default* | ambiguous — configure `decision` or `research` |
| `now` | priority `high` | |
| `next` | priority `medium` | |
| *(no queue label)* | priority **unset** | unset is not `low` |
| `area/*` | the task's `area` | the label itself is also preserved |
| `documentation`, `tech-debt`, anything else | preserved verbatim | still gets a kind (`task`) |

Every label on an issue survives a round trip. Nothing is removed, renamed, or
replaced, and an ordinary sync never *creates* a label: if a mapped label does
not exist upstream, the issue is written without it and the omission is reported.
Set `allow_label_creation = true` only if you want that changed: the adapter then
runs `gh label create` for the missing label, reports having done so, and adds it
to the issue. Creation still passes the write gate, so it never happens on a
dry run or without approval.

### Status

GitHub issues have two states, so:

| GitHub | Normalized |
|--------|-----------|
| open | `open` |
| closed | `done` |

`in_progress` and `blocked` do not exist in GitHub's issue state and are never
inferred from it. They come only from a source you name under `[status]`:

```ini
[status]
in_progress = label:in-progress
blocked = label:blocked
; or: in_progress = assignee
```

A `field:Status` source names a GitHub Projects field. This adapter cannot read
project fields through `gh`, so it reports that as a limitation rather than
silently leaving the status wrong.

### Capabilities

| Capability | GitHub |
|-----------|--------|
| native hierarchy | **no** — parent stored in the task's metadata block, reported `inferred` |
| native dependencies | **no** — same |
| comments | yes |
| labels | yes |
| offline | no |
| atomic updates | no |

### Example

```ini
[tracker]
provider = github
repository = my-org/project-name
require_write_approval = true

[labels.kind]
bug = bug
enhancement = feature
design-decision = decision
question = research

[labels.priority]
now = high
next = medium

[status]
in_progress = assignee
```

---

## Jira

Optional, explicit, and stdlib-only: `urllib` behind a one-method transport, no
SDK. REST **v2** endpoints are used deliberately — v3 takes descriptions as
Atlassian Document Format, and the identity block has to survive byte-for-byte.

### Setup

```ini
[tracker]
provider = jira
project = REG
require_write_approval = true
```

```bash
export JIRA_BASE_URL=https://your-site.atlassian.net
export JIRA_EMAIL=you@example.com
export JIRA_API_TOKEN=...
```

### Vocabulary

Issue types and priorities map through `[jira.issuetype]` and `[jira.priority]`.
Status comes from the native workflow state — Jira genuinely has one, so nothing
is inferred:

| Jira status category | Normalized |
|---------------------|-----------|
| To Do / new | `open` |
| In Progress / indeterminate | `in_progress` |
| Done | `done` (or `cancelled` for "Won't Do") |
| a status named Blocked / On Hold | `blocked` |

### Capabilities and degradation

Hierarchy (`parent`) and dependencies (`Blocks` issue links) are declared native,
because a standard Jira site has both. A team-managed project, a missing link
type, or a permissions gap all present as a *refused* link rather than an absent
feature — so the adapter attempts the link, and on refusal stores the
relationship in the metadata block and reports it as `inferred`, with the HTTP
status that caused the fallback. It never reports a fallback as native.

### Credentials

- `JIRA_API_TOKEN` is held in a `Secret` wrapper whose `repr` is `Secret(***)`,
  so it cannot leak through an f-string or a traceback frame.
- Every provider message passes through a redactor that masks the known token,
  any `Authorization:` header, any `Bearer`/`Basic` payload, and `user:pass@` in
  a URL.
- Nothing writes a credential to a report file or a log line.

---

## Local Markdown

The offline default. Canonical task detail lives in one file per task under
`local_detail_dir` (default `tasks/details/`), and `tasks/todo.md` links to them.

- Fully offline: create, update, close, comment, parent, dependency.
- Hierarchy and dependencies are **native** to this format, because the format is
  ours.
- Writes are atomic (temp file plus `os.replace`).
- Sections a human adds to a task file are preserved; only `## Summary`,
  `## Acceptance Criteria`, and the metadata block are rewritten.

```ini
[tracker]
provider = local
local_detail_dir = tasks/details
```

---

## Troubleshooting

**`provider: local` on a repository that has GitHub issues.**
`gh` is missing or logged out. `gh auth status` to confirm, `gh auth login` to
fix. Selection deliberately falls back rather than failing — reads still work.

**`reads degraded to local-only: ...`**
The provider was unreachable and `offline_reads = degrade` (the default). The
local half of the reconciliation still ran. Set `offline_reads = fail` if you
would rather the whole run stop.

**`refusing to publish: <provider> is unreachable`**
An external write was requested against a provider that is down or unauthorized.
Nothing was written and the exit code is 1. Degrading a read is a service;
degrading a write is data loss with a success message.

**`refusing to create issue — external writes need approval`**
Read the dry run, then re-run with `--approve`. Note that approval is a *floor*:
`require_write_approval = false` in this file is ignored unless the operator also
exports `TASK_REGISTRY_TRUSTED_CONFIG=1`, because a file in the repository must
not be able to switch off a safety gate for everyone who clones it. `doctor` says
so when it has ignored a relaxation.

**`label 'area/render' does not exist in <repo> and allow_label_creation is off`**
Create the label in the tracker yourself, or set `allow_label_creation = true`.
The issue was still written, just without that label.

**`jira: refusing to send credentials over an insecure transport`**
The Jira base URL is `http://` to a remote host, which would put the Basic
credentials on the wire in clear text. Use `https://`, or export
`TASK_REGISTRY_ALLOW_INSECURE_TRANSPORT=1` if you genuinely mean it. Loopback
`http://` is allowed without the override.

**`jira: authentication rejected (HTTP 401)`**
Token expired or wrong account. Tokens are per-user at
`id.atlassian.com/manage/api-tokens`. The token never appears in the message —
that is by design, not a truncation.

**`jira: no closing transition available for REG-1 (offered: ...)`**
The workflow has no transition into a Done category from the issue's current
state. Close it in Jira, or add the transition. The registry will not force a
status field behind the workflow's back.

**`missing-id` on every row.**
The index predates the registry. Run `migrate`, read the report, then
`migrate --apply`. See `migration.md`.
