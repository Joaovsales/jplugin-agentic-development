# Lens: `workflow` — agent workflow efficiency and reliability

The `workflow` routine looks at how the agents worked rather than what they
built: calls that were denied and reissued, retrieval that had expired and was
retried, files read twice, handovers written and then not passed on, full
suites rerun, and fixed context paid before any work. It is not a transcript collector. Its engine reads completed sessions
through the one transcript parser and the read-incidence row the read-shunt
baseline already trusts (specs/claude-mem-retention.md § Proposed routine:
workflow producer).

## Scope and privacy

The template ships this lens and its engine; each user runs the routine on
their own machine over **their own sessions of this repository**, and files
what it proves into this repository's tracker for later analysis. Two rules
follow, and the engine enforces both rather than leaving them to the run:

- **Only this repository's sessions are read.** A session is in scope when
  the working directory it ran in belongs to this repository: one of its
  worktrees, a live checkout sharing its git directory, or a deleted worktree
  under a directory that holds only this repository's worktrees. Another
  project's sessions and claude-mem's observer sessions are counted as out of
  scope; a session whose directory is gone and that nothing attributes is
  counted as unattributable. Neither is read.
- **Nothing that names the machine leaves it.** Anchors are
  `<session-id>[/<agent-id>]:<line>` — never a project directory or path; the
  owner reopens one locally with `find ~/.claude/projects -name
  '<session-id>.jsonl'`. A command subject has the session's working directory
  written `.`, the home directory `~`, and credentials scrubbed. An issue, the
  session record and the PR carry those anchors, digests, counts and quoted
  repository lines — never a transcript excerpt, a user prompt, file content or
  another project's name. A finding that cannot be stated that way stays
  Unverified.

## Engine

1. **Scan.** Run the engine once and record the command and its exit status:

   ```bash
   python3 .agents/skills/eval/scripts/workflow-incidence.py scan
   ```

   Run it from the repository root: it reads this repository's settled
   sessions after the cursor under `~/.claude/projects` through
   `read_transcript.py`, measures each with `read-incidence.py`'s
   `measure_session`, and ranks six candidate kinds — `repeated-denied-call`,
   `expired-retrieval-loop`, `duplicated-read`, `forgotten-handover`,
   `repeated-full-suite`, `excessive-fixed-context` — by the number of
   distinct sessions that carry each. A run is bounded to 50 sessions, 20
   minutes and a configured token budget (`--max-sessions`, `--max-seconds`,
   `--token-budget`; the estimator is printed); one session is charged at most
   `--max-session-tokens`, so an outsized session is read but cannot spend the
   run alone. A full suite is the project's own `Full suite: <command>` line
   in AGENTS.md or CLAUDE.md; a run narrowed to named files, or text that only
   mentions the command, is not a run of it, and a project that declares none
   has that detector off (the report says so). The scan writes its report
   beside the cursor and **does not move the cursor**.
2. **Parent and sub-agent accounting stay separate.** Every occurrence carries
   its frame, and every pattern counts parent and sub-agent occurrences in
   their own columns; a sub-agent's re-read never raises the parent's count.
3. **Other inputs.** An `/eval` results directory for the period may be graded
   with `grade-read-shunt.py` and its rows cited beside the scan. claude-mem is
   an optional locator only: a date- or project-filtered query may point at a
   candidate session, but the proof is always reopened from the original
   transcript through the parser — its summaries and vectors lose per-call
   timing, usage and causal order. Codex sessions are out of scope until a
   tested schema adapter exists; say so in *Coverage gaps*.
4. **Coverage.** Sessions the bounds left after the cursor are reported as
   unexamined, with a count and the first one; a transcript the parser cannot
   read is a coverage gap named by session id; the out-of-scope and
   unattributable counts are reported too. All go into the record's *Coverage
   gaps* section. A gap is never a zero, and an open session is never read.
5. **Advance, last.** Only after the session record is written (`/sweep` step
   6), advance the cursor to the last session the report examined:

   ```bash
   python3 .agents/skills/eval/scripts/workflow-incidence.py advance
   ```

   `advance` refuses a report scanned from a cursor that has since moved. A run
   that stops before its record is written leaves the cursor where it was, so
   the next run rereads the same sessions instead of silently skipping them.
   The cursor belongs to one transcript root and repository and refuses any
   other. Record the cursor's session id and the report's source digest in
   *Scope*.

## Bar

A candidate is filed only with all of:

- A verbatim minimal anchor: the `<session-id>:<line>` (or session/event
  anchor for a session-level kind) the scan printed, the session's source
  digest, and the repository `HEAD` sha. Quote the event's tool name and
  scrubbed subject, never file content or user text — § *Scope and privacy*.
- Observed and expected behaviour, and the four Finding Model axes —
  `severity`, `confidence`, `autofix_class`, `owner` — in the emission format.
- Confidence `75` or above. `NITPICK` is never filed. Every finding of a sweep
  has a single witness (no sub-agent is dispatched), so there is no confidence
  boost for single-agent agreement.
- **A repeat-pattern optimisation**: at least two distinct completed sessions
  carrying the pattern (the scan's `meets_repeat_bar`), and the mechanism
  reproduced against current source — the skill, hook or prompt line that
  causes it, quoted with `file:line`.
- **A correctness defect** may instead meet janitor's bar: a failing
  reproduction executed this run.
- **A claimed cost improvement**: `/eval` Mode C — the blinded paired
  comparison, its quality checks and measured model usage — before the saving
  is called proven. Token savings come from actual usage and context evidence,
  never from bytes guessed from a log line. Long duration or an unfinished
  session is not evidence of a failed task.
- A proposed fix as concrete steps and at least one checkable criterion.

A useful hypothesis below that bar goes into the record's *Unverified* section
with the reason. Files reproduced reliability defects as `--kind bug`, proven
waste as `--kind task --label tech-debt`, and a tradeoff needing an owner as
`--kind decision`; `MUST-FIX` → `--label now`, `SHOULD-FIX` → `--label next`.
The `discovered:` stamp is `sweep/workflow <YYYY-MM-DD> @ <sha>`. Product code
is never edited by this lens.
