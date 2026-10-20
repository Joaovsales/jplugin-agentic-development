---
implementation_paths:
  - .agents/skills/task-registry/scripts/registry/providers/github.py
  - .agents/skills/task-registry/scripts/registry/providers/base.py
  - .agents/skills/task-registry/scripts/registry/config.py
  - .agents/skills/task-registry/scripts/registry/routines.py
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/references/configuration.md
  - .agents/skills/task-registry/templates/task-tracking.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/wrap-up-session/references/closure-actions.md
  - .agents/skills/wrap-up-session/references/routines.md
  - .agents/skills/wrap-up-session/references/routine-prompts/README.md
  - .agents/skills/wrap-up-session/scripts/gh_pr.py
  - .agents/skills/wrap-up-session/scripts/pr_linkage.py
  - docs/task-tracking.md
  - tests/fixtures/task-registry/gh
  - tests/test-task-registry.sh
  - tests/test-routine-selectors.sh
  - tests/test-routine-wrapup.sh
  - tests/test-doc-conventions.sh
  - tests/test-gh-pr.sh
  - tests/test-task-closes.sh
---

# Spec: GitHub through REST in Claude Code cloud sandboxes

## Summary

Claude Code cloud sandboxes reach GitHub through a proxy that accepts REST
calls (`gh api repos/{owner}/{repo}/...`, `gh api user`) and refuses GitHub's
GraphQL endpoint with HTTP 403. `gh auth status` also exits non-zero there
although every REST call succeeds. The task-registry GitHub provider and the
wrap-up PR path both drive `gh` through subcommands that use GraphQL
(`gh issue`, `gh label`, `gh repo view --json`, `gh pr`), so an unattended
routine stops at `task-registry doctor` and could never open its PR. Both
move to REST: the provider calls `gh api` only, and the PR path runs through
one script, `gh_pr.py`, that the wrap-up prose cites instead of `gh pr`.
Every observable behavior stays the same; only the transport and the exact
`gh` argv change. The decision not to miss: linked-PR exclusion in `select`
is kept by reading each candidate's REST timeline, conservatively. The
merger's post-merge check (`task-registry closes`) and the `stranded:`
backstop in `select` read pull-request state from REST as well.

## Behavior

### The registry's GitHub provider speaks REST

`.agents/skills/task-registry/scripts/registry/providers/github.py` issues
every GitHub call as `gh api` against `user` or `repos/{owner}/{repo}/...`.
No `gh issue`, `gh label`, `gh repo` or `gh auth` invocation remains in the
provider or in `config.py`.

- **Reachability** (`discover()` and provider selection in `config.py`) is
  `gh api user` exiting 0. The failure line keeps its shape: `gh is
  unavailable or unauthenticated — run \`gh auth login\` (<last stderr line>)`.
- **Repository resolution** without a `repository =` line parses the GitHub
  remote (`config.github_remote`) instead of calling `gh repo view`; the
  refusal when no remote exists keeps its text, minus the `gh repo view`
  quotation.
- **Reads.** `list_tasks` pages `GET /repos/{r}/issues?state=all&per_page=100&page=N`
  until a short page or `LIST_LIMIT` entries, keeping today's truncation
  flag and note. Entries carrying a `pull_request` key are pull requests, not
  issues, and are dropped. `get_task` is `GET /repos/{r}/issues/{n}`. The
  REST shape maps onto the normalized model: `html_url` → url, `created_at`
  and `updated_at`, `state` lower-case, `labels[].name`, `assignees`.
- **Writes** send a JSON payload on stdin with `gh api --method <M> <path>
  --input -`. Create is `POST /issues` with `title`, `body` and `labels[]`;
  the issue URL comes from the response's `html_url`. Update is `PATCH
  /issues/{n}` with `body` and, when it changed, `title`, followed by `POST
  /issues/{n}/labels` only when there are labels to add. Additive labels are
  `POST /issues/{n}/labels`. Close is `PATCH /issues/{n}` with `state:
  closed` and `state_reason` `completed` or `not_planned`. Comment is `POST
  /issues/{n}/comments`. Label creation is `POST /labels`; label listing
  pages `GET /labels?per_page=100` to `LABEL_LIST_LIMIT` with today's cap
  refusal. Error lines read `github: \`gh api <METHOD> <path>\` exited N —
  <redacted output>`.
- **A label never reaches a write unless the repository already has it.**
  REST `POST /issues` silently creates unknown labels for anyone with push
  access, so the known-label filter is the only thing standing between an
  ordinary sync and a mutated vocabulary. The mock enforces it too.

### Linked-PR exclusion survives without GraphQL

`select` still skips an issue whose fix is already under review, and still
names an issue a merge left open. The provider gains
`linked_pr_state(task) -> Optional[Dict[str, str]]` (base default `None`,
unknown). The GitHub implementation reads `GET /repos/{r}/issues/{n}/timeline`
(paged, capped) and looks only at `cross-referenced` events whose source is a
pull request; an open issue that mentions the candidate counts for nothing.
It answers the two keys `select` reads today: `unresolved_linked_pr` is `true`
when any such pull request is open, in this repository or another;
`merged_linked_pr` names the first pull request of this repository that merged
with a closing keyword naming the candidate, when no pull request is open and
the issue's `state_reason` is not `reopened`. The event's `source.issue`
carries the pull request's state, `pull_request.merged_at`, `repository_url`
and body, so the read costs no second call. A timeline over the cap answers
`None`.

`select` evaluates the hook for the routine's candidates only, after the kind
and claim filters, so a 500-issue repository costs one call per candidate
rather than per issue; the `stranded:` backstop therefore covers the routine's
own pool, and a stranded issue of another routine is named when that routine
runs. A candidate whose state is unknown makes `select` refuse, naming the
issue, exactly as the missing field does today. `linked_pr_exclusion_available()`
answers `True` for this provider; the `select` refusal text no longer mentions
a `gh` version. `list_tasks_with_linked_prs`, the per-issue
`closedByPullRequestsReferences` and `stateReason` fields, the GraphQL
`PR_STATE_QUERY`, the `OPTIONAL_ISSUE_FIELDS` degradation and the mock's
`unknown-fields` knob are retired with it. `routines.md` states the exclusion
as a timeline read and drops its `gh` 2.73.0 floor and its GraphQL sentence.

### The post-merge check reads the pull request over REST

`closing_references(pr)` reads `GET /repos/{r}/pulls/{n}`; a pull request whose
`merged` is false is refused naming its state, as today. The issues it closes
are the closing keywords in its body — GitHub's own list (`close`, `closes`,
`closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`, an
optional colon, then `#N`, `owner/repo#N` or an issue URL) — parsed by one
helper that the stranded check shares. A reference outside the repository is
refused naming it and nothing is closed, as today. `task-registry closes` then
reads and closes each open issue through the REST reads and writes above.

### The wrap-up PR path runs through `gh_pr.py`

`.agents/skills/wrap-up-session/scripts/gh_pr.py` (standard library plus
`gh api`) owns every pull-request operation the wrap-up and its closure
actions perform:

| Subcommand | REST |
|---|---|
| `create --base <branch> --title <t> --body-file <f> [--draft]` | `POST /pulls` with `head` = current branch, `draft` as given; prints the PR URL |
| `view <n or branch> --json <fields>` | `GET /pulls/{n}`, or `GET /pulls?head=<owner>:<branch>&state=all` for a branch; fields `number,url,body,mergeable,headSha` |
| `edit <n> --body-file <f>` | `PATCH /pulls/{n}` |
| `ready <n> [--undo]` | `POST /pulls/{n}/ccr/ready_for_review`, or `POST /pulls/{n}/ccr/convert_to_draft` with `--undo`; when that route answers 404 the proxy is absent, and the script falls back to `gh pr ready [--undo]` (Decision 9) |
| `checks <n> [--watch] [--required]` | `GET /commits/{sha}/check-runs` and `/commits/{sha}/status`; `--required` reads the base branch's required checks and falls back to all when that read is refused |
| `mergeable <n>` | `GET /pulls/{n}` `.mergeable`, `null` reported as unknown |

`view` tells "no such pull request" (an empty list or 404) apart from "could
not ask" (any other failure) in its exit code and stderr, because the terminal
PR assertion depends on that distinction. The wrap-up prose (`SKILL.md`,
`closure-actions.md`, `routines.md`, the routine-prompts README) cites these
subcommands and contains no `gh pr`; the one-place rule for PR creation now
pins `gh_pr.py create` exactly once.

### The `gh` mock answers REST

`tests/fixtures/task-registry/gh` gains an `api` dispatcher over the routes
above: `GET user` honors `GH_MOCK_UNAUTH`; writes honor `GH_MOCK_FAIL`;
`--input -` bodies are parsed and appended to the `GH_MOCK_LOG` line so
assertions can grep what was sent; unknown labels on any write exit 1;
`issues` paging honors `per_page` and `page`; `issue-<n>.json` and
`issues.json` keep their meaning; `timeline-<n>.json` answers the timeline
route. The `auth`, `issue`, `label` and `repo` branches are removed, so a
provider that regresses to a GraphQL-backed subcommand fails loudly.

## Inputs

- `gh` on PATH, able to run `gh api` against api.github.com: a logged-in CLI
  or a sandbox-provided `GH_TOKEN`.
- The project's task-tracking configuration, unchanged.
- For the PR path: the current branch, its base branch, and a PR body file.

## Outputs

- `doctor` reports `reachable: yes — gh authenticated for <owner>/<repo>` in
  the cloud sandbox, and every registry read and write succeeds there.
- `select` reports how many candidates had their linked-PR state checked and
  prints a `stranded:` line for each candidate a merge left open.
- `gh_pr.py` prints the same facts the prose previously read from `gh pr`
  (URL, number, body, mergeable, check results) in the same places.
- Documentation states the environment requirement as "`gh api user`
  succeeds", not "`gh auth status` succeeds".

## Edge Cases

- `gh api user` fails: the provider is unreachable with the existing message;
  reads degrade to local-only and writes become `local-pending`, as today.
- The issues endpoint returns pull requests: dropped before normalization; a
  fixture entry with a `pull_request` key proves it.
- A page comes back exactly full at `LIST_LIMIT`: `result_truncated` is set
  and `select` refuses, as today.
- `update_task` patches the body and then fails to add labels: the error names
  the body as already written, so a retry does not re-apply a stale body.
- An unknown label is requested: filtered before the write, reported in a
  note; the mock exits 1 if one slips through.
- A candidate's timeline exceeds the page cap: state unknown, `select`
  refuses and names the issue.
- An open PR merely mentions the issue without closing it: it still excludes
  the issue. Over-exclusion is the chosen side of the error.
- A cross-reference comes from an issue, not a pull request, in this or
  another repository: ignored.
- A merged PR mentions the issue without a closing keyword: it excludes
  nothing and strands nothing.
- A merged PR closes the issue in a form the keyword parser misses: no
  `stranded:` line, and the issue stays a candidate (R6).
- `closes` on a PR whose body names `owner/other#N`: refused naming it,
  nothing closed, as today.
- `gh_pr.py view <branch>` on a branch with no PR: exit 1 and `no pull
  request for <branch>`; a network or auth failure exits 2 with `gh`'s
  stderr, so the terminal assertion reports UNKNOWN rather than "no PR".
- Required-checks read refused or `Branch not protected` (404): `checks
  --required` watches all checks and says so.
- `ready` outside a sandbox: the `ccr` route answers 404, and the script
  runs `gh pr ready [--undo]` instead, reporting which path it took.
- `mergeable` is `null` right after a push: reported as unknown and
  re-queried up to three times, as the closure action does today.
- REST writes are refused by the sandbox proxy (R3, Q1): the registry reports
  the HTTP status in its error line and the write becomes `local-pending`.
- Windows: the Python-called mock is unreachable from the registry (#129);
  the mock-backed assertions are proven on Linux CI, as before.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | REST `POST /issues` auto-creates labels the repository lacks | M | H | known-label filter before every write; mock rejects unknown labels on writes | 1 |
| R2 | Timeline cross-references over-exclude a candidate | M | L | conservative by design; `select` prints the excluding PR number | 2 |
| R3 | REST writes from the sandbox are refused although reads pass | L | H | unverified until the first real routine run; Q1 | 1 |
| R4 | Mock argv assertions drift from the real `gh api` surface | M | M | the mock validates method, path and body shape like the real CLI validates flags | 1 |
| R5 | The suite fails as uid 0 in the sandbox (4 of 72 files), so the wrap-up gate would still refuse to push there | H | H | out of scope here; a separate fix guards those assertions on `id -u` like the two already guarded | — |
| R6 | The body parser misses a closing form GitHub honours, so a stranded issue is re-picked | L | M | GitHub's documented keyword list, one test per form; `closes` reads the same helper, so a miss shows on the merger's run | 4 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | How does `select` learn linked-PR state without GraphQL? | Read each candidate's REST timeline; any cross-reference from an open PR excludes; over the cap is unknown and refuses | user | keeps the safety property that stops two routines racing on one branch |
| 2 | Does this spec cover the wrap-up PR path too? | Yes: `gh_pr.py` replaces every `gh pr` call | user | the routine's last step is a PR; a registry that works and a PR that cannot open is still a failed run |
| 3 | What is the reachability probe? | `gh api user` exit 0, in both `discover()` and provider selection | assumed | the sandbox token fails `gh auth status` while every REST call works; `GET /user` is the cheapest authenticated call |
| 4 | How is the repository resolved without `repository =`? | From the GitHub remote via `config.github_remote` | assumed | `gh repo view --json` is GraphQL; the remote already exists because selection chose GitHub for it |
| 5 | How do write payloads reach `gh api`? | JSON on stdin with `--input -` | assumed | argv is capped near 32K on Windows and issue bodies reach 64K; arrays (`labels`) are awkward as `-f` fields |
| 6 | How are lists paged? | `per_page=100&page=N` loop in Python until a short page or the cap | assumed | no `gh` version floor for `--paginate --slurp`, the mock stays simple, truncation detection stays explicit |
| 7 | When is linked-PR state read? | Per candidate inside `select`, after kind and claim filtering; the `stranded:` backstop covers the routine's own pool | assumed | one timeline call per listed issue would be hundreds of calls per run; another routine's stranded issue is named on that routine's run |
| 8 | Where does the PR logic live? | A script, `gh_pr.py`, cited by the prose | assumed | prose cannot be tested; a script with a mock can, and the "exactly one place creates the PR" rule transfers to it |
| 9 | Which route toggles draft and ready? | The sandbox proxy's `POST /repos/{o}/{r}/pulls/{n}/ccr/ready_for_review` and `.../ccr/convert_to_draft`; a 404 on that route means no proxy, and the script falls back to `gh pr ready [--undo]` | assumed | `gh pr ready` is GraphQL and fails in the sandbox; the proxy's own 403 message names these routes, and they exist nowhere else, so a plain `gh` outside the sandbox keeps the GraphQL path |
| 10 | What does the mock record for a write? | The argv line plus the parsed stdin body | assumed | the claim and label tests assert on what was sent, not only on which route was hit |
| 11 | What happens to the old-`gh` degradation path? | Retired with `OPTIONAL_ISSUE_FIELDS` and the `unknown-fields` knob | assumed | no `--json` field list exists on REST; the capability it degraded is now the timeline read |
| 12 | Is the uid-0 suite failure fixed here? | No; flagged as R5 for a separate, small fix | assumed | unrelated code, and this spec is already at the slice ceiling |
| 13 | How is "this PR closes that issue" known without `closingIssuesReferences`? | GitHub's closing keywords parsed from the PR body, by one helper shared by `closes` and the stranded check | assumed | REST exposes no closing-reference relation; the body is what GitHub itself reads, and the timeline event already carries it |
| 14 | Where do a cross-referencing PR's state and body come from? | The `cross-referenced` event's `source.issue` (`state`, `pull_request.merged_at`, `repository_url`, `body`) | assumed | verified live on #146 on 2026-10-19; no second call per PR |
| 15 | Does a PR in another repository count? | For the exclusion yes; for `stranded` no | assumed | conservative on the exclusion, and `closes` cannot reach a merge elsewhere, as today |

## Open questions

| ID | Question | Blocks | Needed from |
|---|---|---|---|
| Q1 | Do REST writes (`POST /issues`, `POST /pulls`) succeed from the sandbox, not only reads? | none | the first real routine run |

## Acceptance Criteria

- AC1: With a `gh` whose `auth status` exits 1 but whose `api user` exits 0, `doctor` prints `reachable: yes — gh authenticated for <owner>/<repo>` and provider selection with no `provider =` line picks `github`; with `api user` failing (`GH_MOCK_UNAUTH`) the existing unreachable line and the `local-pending` write path are unchanged.
- AC2: The provider and `config.py` contain no `gh issue`, `gh label`, `gh repo` or `gh auth` invocation; the lifecycle test's `gh.log` contains only `api` lines, each a `user` or `repos/<owner>/<repo>/...` path.
- AC3: Every section-7 GitHub provider test (normalization, create, update, additive labels, close, comment, gated writes, unauthenticated degradation) passes against the REST mock, with assertions changed only in the argv or body they grep.
- AC4: An `issues.json` entry carrying a `pull_request` key produces no task.
- AC5: A read of exactly `LIST_LIMIT` issues sets `result_truncated` and `select` refuses with the existing message.
- AC6: `select` excludes a candidate whose `timeline-<n>.json` holds a cross-reference from an open PR, keeps one whose references are merged or closed, prints a `stranded:` line for a candidate whose only cross-referencing PR merged in this repository with a closing keyword naming it and whose `state_reason` is not `reopened`, refuses and names the issue when the timeline exceeds the cap, and reports the number of candidates checked; the `select` cases of `tests/test-task-closes.sh` pin the timeline read in place of `gh api graphql`.
- AC7: Every write sends its payload on stdin; the mock's log line carries the body; a write naming a label absent from `labels.json` exits 1 and the test asserts the refusal.
- AC8: `update_task` with a changed body and a new label issues `PATCH /issues/{n}` then `POST /issues/{n}/labels`; with `GH_MOCK_FAIL` set only for the second call, the error names the body as already written.
- AC9: `configuration.md`, `templates/task-tracking.md`, `docs/task-tracking.md` and the routine-prompts README state the requirement as `gh api user` succeeding; `gh auth status` appears in none of them.
- AC10: `gh_pr.py` implements `create`, `view`, `edit`, `ready`, `checks` and `mergeable` through REST; `tests/test-gh-pr.sh` proves each subcommand's method, path and body against the mock, and proves `view` exits 1 for "no PR" and 2 for "could not ask".
- AC11: The wrap-up `SKILL.md`, `closure-actions.md`, `routines.md` and the routine-prompts README contain no `gh pr`; `gh_pr.py create` appears exactly once across the skill; `tests/test-routine-wrapup.sh` and `tests/test-doc-conventions.sh` pin the new tokens where they pinned `gh pr` ones.
- AC12: `bash tests/run.sh` is green on the pull request's Linux CI run.
- AC13: `task-registry closes '#N'` reads `GET /repos/{r}/pulls/{n}`, refuses an unmerged PR naming its state, takes its issues from the closing keywords in the body (one test per keyword form), refuses a reference outside the repository naming it, and closes each open one through `PATCH /issues/{n}`; the `closes` cases of `tests/test-task-closes.sh` pin that argv in place of `gh pr view`, `gh issue view` and `gh issue close`.

## Implementation Paths

- `.agents/skills/task-registry/scripts/registry/providers/github.py` — the REST provider: reachability, reads, writes, label vocabulary, timeline-based linked-PR state.
- `.agents/skills/task-registry/scripts/registry/providers/base.py` — the `linked_pr_state` hook with its `None` default; `list_tasks_with_linked_prs` retired.
- `.agents/skills/task-registry/scripts/registry/config.py` — `gh_authenticated` probes `gh api user`.
- `.agents/skills/task-registry/scripts/registry/routines.py` — candidate filtering and `stranded` read the hook's answer after kind and claim filters.
- `.agents/skills/task-registry/scripts/task-registry.py` — the `select` refusal text and the checked-candidates line.
- `.agents/skills/task-registry/references/configuration.md`, `.agents/skills/task-registry/templates/task-tracking.md`, `docs/task-tracking.md` — the environment requirement stated as REST reachability.
- `.agents/skills/wrap-up-session/scripts/gh_pr.py` — the REST PR helper.
- `.agents/skills/wrap-up-session/scripts/pr_linkage.py` — its docstring names `gh_pr.py create` as the step it precedes.
- `.agents/skills/wrap-up-session/SKILL.md`, `references/closure-actions.md`, `references/routines.md`, `references/routine-prompts/README.md` — prose cites `gh_pr.py` subcommands; `routines.md` describes the exclusion as a timeline read.
- `tests/fixtures/task-registry/gh` — the REST-aware mock.
- `tests/test-task-registry.sh`, `tests/test-routine-selectors.sh` — provider, selection and claim assertions against the REST mock.
- `tests/test-gh-pr.sh` — the PR helper's contract.
- `tests/test-task-closes.sh` — the post-merge check and the `select` backstop against the in-process `_run` seam, pinning REST argv.
- `tests/test-routine-wrapup.sh`, `tests/test-doc-conventions.sh` — the prose pins moved from `gh pr` to `gh_pr.py`.

## Build Order

Sizing: 7 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 5
(3 systems: one reachability sentence in the registry's reference and
template, the wrap-up's routine-prompts README and the project's
`docs/task-tracking.md`, kept together because AC9 reads the four documents
as one statement).

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | REST reads and reachability | `discover()` and `config.gh_authenticated` probe `gh api user`; `_repo()` falls back to the parsed remote; `list_tasks` and `get_task` page REST issues, drop pull requests and map the REST shape; the mock gains its `api` dispatcher for `user`, `issues`, `issues/{n}` and `labels` reads | `.agents/skills/task-registry/scripts/registry/providers/github.py`, `.agents/skills/task-registry/scripts/registry/config.py`, `tests/fixtures/task-registry/gh`, `tests/test-task-registry.sh` | — | 1, 4, 5 | `bash tests/test-task-registry.sh` | 4 files · 1 system · 3 ACs |
| 2 | REST writes | create, update, additive labels, close, comment, label creation and label listing on `gh api --method <M> <path> --input -`; the mock parses stdin bodies into the log, honors `GH_MOCK_FAIL` and exits 1 on an unknown label | `.agents/skills/task-registry/scripts/registry/providers/github.py`, `tests/fixtures/task-registry/gh`, `tests/test-task-registry.sh` | 1 | 3, 7, 8 | `bash tests/test-task-registry.sh` | 3 files · 1 system · 3 ACs |
| 3 | Timeline linked-PR exclusion | `linked_pr_state` hook (base `None`), the GitHub timeline read answering `unresolved_linked_pr` and `merged_linked_pr`, `select_candidates` and `stranded` reading it after kind and claim filters, the refusal text and checked-candidates line; `list_tasks_with_linked_prs`, `OPTIONAL_ISSUE_FIELDS`, `PR_STATE_QUERY`, `closedByPullRequestsReferences` and the mock's `auth`/`issue`/`label`/`repo` branches and `unknown-fields` knob removed; the `select` cases of `tests/test-task-closes.sh` moved to the timeline argv | `.agents/skills/task-registry/scripts/registry/providers/base.py`, `.agents/skills/task-registry/scripts/registry/providers/github.py`, `.agents/skills/task-registry/scripts/registry/routines.py`, `.agents/skills/task-registry/scripts/task-registry.py`, `tests/fixtures/task-registry/gh`, `tests/test-task-registry.sh`, `tests/test-routine-selectors.sh`, `tests/test-task-closes.sh` | 1, 2 | 2, 6 | `bash tests/test-task-registry.sh tests/test-routine-selectors.sh tests/test-task-closes.sh` | 8 files · 1 system · 2 ACs |
| 4 | Post-merge closes over REST | `closing_references` on `GET /pulls/{n}` plus the shared closing-keyword parser; unmerged and out-of-repository refusals kept; the `closes` cases of `tests/test-task-closes.sh` pin the REST argv, one per keyword form | `.agents/skills/task-registry/scripts/registry/providers/github.py`, `.agents/skills/task-registry/scripts/registry/providers/base.py`, `tests/test-task-closes.sh` | 3 | 13 | `bash tests/test-task-closes.sh` | 3 files · 1 system · 1 AC |
| 5 | REST reachability in the docs | the environment requirement reads "`gh api user` succeeds" in the registry reference, its template, the project file and the routine-prompts README; `gh auth status` appears in none | `.agents/skills/task-registry/references/configuration.md`, `.agents/skills/task-registry/templates/task-tracking.md`, `docs/task-tracking.md`, `.agents/skills/wrap-up-session/references/routine-prompts/README.md`, `tests/test-doc-conventions.sh` | — | 9 | `bash tests/test-doc-conventions.sh` | 5 files · 3 systems (over, see above) · 1 AC |
| 6 | gh_pr.py REST PR helper | `create`, `view`, `edit`, `ready`, `checks`, `mergeable` over `gh api`; `view` separates "no PR" (exit 1) from "could not ask" (exit 2); `ready` takes the `ccr` route and falls back to `gh pr ready` on 404; the mock answers `pulls`, `check-runs`, `status` and `ccr` routes | `.agents/skills/wrap-up-session/scripts/gh_pr.py`, `tests/test-gh-pr.sh`, `tests/fixtures/task-registry/gh` | 3 | 10 | `bash tests/test-gh-pr.sh` | 3 files · 2 systems · 1 AC |
| 7 | Wrap-up prose cites gh_pr.py | `SKILL.md`, `closure-actions.md`, `routines.md`, the routine-prompts README and the `pr_linkage.py` docstring cite `gh_pr.py` subcommands and contain no `gh pr`; `gh_pr.py create` pinned exactly once; `routines.md` states the exclusion as a timeline read without the `gh` 2.73 floor or the GraphQL sentence; the prose tests move their pins; Linux CI green | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/closure-actions.md`, `.agents/skills/wrap-up-session/references/routines.md`, `.agents/skills/wrap-up-session/references/routine-prompts/README.md`, `.agents/skills/wrap-up-session/scripts/pr_linkage.py`, `tests/test-routine-wrapup.sh`, `tests/test-doc-conventions.sh` | 5, 6 | 11, 12 | `bash tests/test-routine-wrapup.sh tests/test-doc-conventions.sh` | 7 files · 1 system · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/github-rest-in-sandboxes.md`.
Plan: `## Plan: github-rest-in-sandboxes` in `tasks/todo.md`, 7 slices, ready set <1, 5>.
Files: .agents/skills/task-registry/scripts/registry/providers/github.py, .agents/skills/task-registry/scripts/registry/providers/base.py, .agents/skills/task-registry/scripts/registry/config.py, .agents/skills/task-registry/scripts/registry/routines.py, .agents/skills/task-registry/scripts/task-registry.py, .agents/skills/task-registry/references/configuration.md, .agents/skills/task-registry/templates/task-tracking.md, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/wrap-up-session/references/closure-actions.md, .agents/skills/wrap-up-session/references/routines.md, .agents/skills/wrap-up-session/references/routine-prompts/README.md, .agents/skills/wrap-up-session/scripts/gh_pr.py, .agents/skills/wrap-up-session/scripts/pr_linkage.py, docs/task-tracking.md, tests/fixtures/task-registry/gh, tests/test-task-registry.sh, tests/test-routine-selectors.sh, tests/test-routine-wrapup.sh, tests/test-doc-conventions.sh, tests/test-gh-pr.sh, tests/test-task-closes.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/github-rest-in-sandboxes.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- Decision 5: every write payload travels on stdin through `gh api --input -`; no `-f`/`-F` fields.
- Decisions 1, 7 and 15: linked-PR state is read from the REST timeline per candidate, after kind and claim filtering; any open cross-referencing PR excludes, an over-cap timeline makes `select` refuse, and `stranded` covers the routine's own pool.
- Decisions 13 and 14: the closing relation is GitHub's closing-keyword list parsed from the PR body, one helper shared by `closes` and the stranded check, read off the timeline event's `source.issue`; no GraphQL anywhere.
- Decision 9: `ready` posts to the `ccr/ready_for_review` and `ccr/convert_to_draft` routes and falls back to `gh pr ready [--undo]` only on a 404 from that route.
- Decision 12: the uid-0 suite failures (R5) are not fixed in this plan; no edit outside the Surfaces for them.
```
