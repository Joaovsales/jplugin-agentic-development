---
implementation_paths:
  - .agents/skills/wrap-up-session/scripts/unattended_scan.py
  - .agents/skills/wrap-up-session/scripts/unattended-scan-rules.json
  - .agents/git-hooks/pre-push
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/wrap-up-session/references/routines.md
  - tests/test-unattended-scan.sh
  - tests/test-pre-push-gate.sh
---

# Spec: Unattended Scan

> Origin: #444

## Summary

An unattended push — a `routine/` branch, or a caller that declares itself
unattended — is scanned by a fixed, standard-library-only ruleset before it
leaves the machine. The scan reads the commands the session ran (its transcript)
and the lines the push adds (its diff) through one text normalisation, and a
high-severity hit refuses the push. The rules are data with their own fixtures
and their own documented blind spots; a project can add rules but never remove
a built-in one. The scanner is deterministic: no model, no network, no clock.

## Behavior

`unattended_scan.py scan` loads the built-in rules
(`scripts/unattended-scan-rules.json`) and, when present, the project's
`.agents/unattended-scan-rules.json`, proves every rule against its own
fixtures, then scans:

- **The diff** — `git diff <base> <head>`: every added line (text rules whose
  `sources` include `diff`) and every changed path (path rules). The two rule
  files themselves are not text-scanned, because their fixtures are made to match;
  editing the built-in rule file or the scanner is itself a path-rule hit.
- **The transcript** — the commands and paths the session's tool calls named.
  A JSONL transcript (Claude Code, Codex) is read record by record; from every
  object whose `type` is a tool call (`tool_use`, `function_call`,
  `custom_tool_call`, `local_shell_call`) the scanner takes the `command`,
  `cmd`, `file_path`, `path` and `url` values of its input, or the whole input
  when it is a string that is not JSON. File *content* written by a tool is the
  diff's job. A transcript that is not JSONL is scanned line by line.
  `--transcript auto` resolves the running Claude Code session from
  `CLAUDE_CODE_SESSION_ID`, its sub-agent transcripts included, and scans no
  transcript when nothing resolves.

Both sources pass through the same normalisation before any rule sees them:
ANSI escape sequences are removed, `\r\n` becomes `\n` and a lone `\r` starts a
new line (so text hidden behind a carriage return is scanned), and a line
ending in a backslash is joined to the next.

Each hit prints one finding in the finding-model format — `high` is
`MUST-FIX`, `medium` is `SHOULD-FIX`, always `confidence: 75`,
`autofix_class: manual`, `owner: human` — sorted by source, location and rule
id, followed by one summary line. The pre-push hook runs the scan for every
pushed branch under `routine/`, and for any push made with `UNATTENDED_SCAN=1`
(the caller-declared case: `/yolo`, `/auto-push`), passing
`--transcript "${UNATTENDED_SCAN_TRANSCRIPT:-auto}"`. Exit 1 (a high hit) or 2
(the scan could not run) blocks the push; medium hits print and pass. The scan
runs before the `SKIP_PREPUSH` kill switch, so an environment variable cannot
silence it; `git push --no-verify` remains the human override.

`/wrap-up-session` treats a scan refusal like any pre-push gate refusal, and
on an unattended run first files the findings as one `bug` task through
`/task-registry upsert --derive-id unattended-scan --apply`, then ends through
§ *Terminal PR assertion*.

## Inputs

- `scan [--base REV] [--head REV] [--transcript PATH|auto]...` — `--base`
  defaults to the merge base with the first of `origin/master`, `origin/main`,
  `origin/develop`; `--head` defaults to `HEAD`. Run from the repository root.
- `selftest` — load both rule files and prove every rule's fixtures; scan
  nothing.
- The rule-file schema: a top-level object with `rules` (a list) and, in the
  built-in file, `known_gaps` (scanner-wide blind spots). A rule carries `id`,
  `severity` (`high` | `medium`), `kind` (`text` | `path`), `sources` (text
  rules: a non-empty subset of `transcript`, `diff`), `pattern` (a Python
  regular expression), `description`, `match` and `no_match` (each at least one
  fixture), and `gaps` (known false negatives; at least one per built-in rule).

## Outputs

- stdout: zero or more findings, then
  `unattended-scan: <h> high, <m> medium — <sources>`.
- Exit 0 — no high hit. Exit 1 — at least one high hit. Exit 2 — a rule file
  that does not load, a rule whose fixture fails, a project rule that reuses a
  built-in id, an unreadable transcript or a git failure; the reason on stderr.
- The hook prints `BLOCKED: unattended scan …` and exits 1 on scan exit 1 or 2.

## Edge Cases

- A project rule file with an unknown key, a rule reusing a built-in id, or a
  rule without fixtures is refused (exit 2): a project can add rules, never
  override or remove one.
- An empty diff and no transcript scan nothing and exit 0.
- A truncated final JSONL record (the session is still writing) and any other
  line that is not JSON are scanned as raw text, never dropped.
- A branch deletion (all-zero local sha) is not scanned.
- Two scans of the same input print byte-identical output and exit the same.

## Interfaces

### unattended_scan.py

- **Path:** `.agents/skills/wrap-up-session/scripts/unattended_scan.py`
- **Hides:** rule loading and the add-only merge, fixture proof, transcript
  shapes, diff parsing and the normalisation.
- **Interface:** `unattended_scan.py scan [--base R] [--head R] [--transcript P|auto]...` → findings, exit 0/1/2.
- **Alternative considered:** a model reviewer over the transcript — rejected,
  as esf rejected it: two runs of the same input could disagree.
- **Depth:** one call reads both sources, applies every rule and decides the
  exit; the hook knows only the exit code.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | A legitimate routine change (a CI fix, a doc showing an install command) is blocked | M | M | Medium severity for noisy rules; the finding names the rule and line; a human pushes with `--no-verify` | 1 |
| R2 | An agent bypasses the hook with `--no-verify` | M | H | Documented in `known_gaps`; the transcript rule flags `--no-verify` at the next scanned push | 1 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where does the block happen? | In the pre-push git hook, for `routine/` branches and `UNATTENDED_SCAN=1` pushes | assumed | The hook runs on every push whatever the model remembers; wrap-up already treats a hook refusal as a terminal exit |
| 2 | Which `routine/` branches? | Every branch under the `routine/` prefix, not only the ones `routine_branch.py` parses | assumed | Over-including is the safe direction for a scan, and the hook stays free of a Python call for the check |
| 3 | Rule format | One JSON schema for the built-in and the project file, fixtures and gaps inside each rule | assumed | Fixtures and blind spots sit next to the pattern they describe (AC1, AC4), and the loader can prove a project rule the same way |
| 4 | What part of the transcript is scanned? | Tool-call commands and paths only; written content is the diff's job | assumed | Tool results and prose (issue bodies, file reads) would match the rules' own vocabulary on every run |
| 5 | Does `SKIP_PREPUSH=1` skip the scan? | No — the scan runs before the kill switch | assumed | An unattended agent can set an environment variable; `--no-verify` stays the human override and is a documented gap |
| 6 | A scan that cannot run | Blocks the push (exit 2) | assumed | No silent failures: an unattended push that was not scanned must not look like one that was |
| 7 | Who opens the finding? | `/wrap-up-session`, through `/task-registry upsert --apply`; the hook does no network I/O | assumed | The hook's no-network rule is load-bearing for offline and CI pushes |

## Acceptance Criteria

- AC1: Every built-in rule carries at least one `match` and one `no_match`
  fixture, and the scanner refuses (exit 2) a rule file in which any rule lacks
  one or any fixture disagrees with its pattern.
- AC2: A push of a `routine/` branch whose diff or transcript hits a
  high-severity rule is refused by the pre-push hook with exit 1, `SKIP_PREPUSH=1`
  notwithstanding; a clean routine push and a non-routine push pass; a medium
  hit prints and passes; `/wrap-up-session` names the refusal and the finding it
  files.
- AC3: Two scans of the same diff and transcript print byte-identical output and
  return the same exit code.
- AC4: Every built-in rule carries a non-empty `gaps` list, and the built-in file
  carries a non-empty scanner-wide `known_gaps` list.
- AC5: A project rule file adds its rules to the scan; one that reuses a
  built-in id or carries an unknown key is refused.

## Implementation Paths

- `.agents/skills/wrap-up-session/scripts/unattended_scan.py` — loads and proves
  the rules, extracts the two sources, normalises and scans them.
- `.agents/skills/wrap-up-session/scripts/unattended-scan-rules.json` — the
  built-in ruleset with fixtures and known false negatives.
- `.agents/git-hooks/pre-push` — runs the scan on unattended pushes.
- `.agents/skills/wrap-up-session/SKILL.md` — the refusal row and the finding.
- `.agents/skills/wrap-up-session/references/routines.md` — the unattended scan
  under § *Wrap-up on a routine branch*.
- `tests/test-unattended-scan.sh` — fixtures, normalisation, determinism and
  the add-only project merge.
- `tests/test-pre-push-gate.sh` — the hook blocks a routine push on a hit.

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: four ACs on one module — the loader, the rules and the scan are one interface and its tests share one fixture set; slice 2: three systems — the hook and the wrap-up text that names its refusal ship together.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Scanner and ruleset | The stdlib scanner, the built-in rules with fixtures and gaps, the add-only project merge | `.agents/skills/wrap-up-session/scripts/unattended_scan.py`, `.agents/skills/wrap-up-session/scripts/unattended-scan-rules.json`, `tests/test-unattended-scan.sh` | — | 1, 3, 4, 5 | `bash tests/test-unattended-scan.sh` | 3 files · 2 systems · 4 ACs |
| 2 | Push gate wiring | The pre-push hook blocks an unattended push on a high hit; wrap-up files the finding | `.agents/git-hooks/pre-push`, `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/routines.md`, `tests/test-pre-push-gate.sh` | 1 | 2 | `bash tests/test-pre-push-gate.sh` | 4 files · 3 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/unattended-scan.md`.
Plan: `## Plan: Unattended scan` in `tasks/todo.md`, 2 slices, ready set <1>.
Files: .agents/skills/wrap-up-session/scripts/unattended_scan.py, .agents/skills/wrap-up-session/scripts/unattended-scan-rules.json, .agents/git-hooks/pre-push, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/wrap-up-session/references/routines.md, tests/test-unattended-scan.sh, tests/test-pre-push-gate.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: the block happens in the pre-push hook, before SKIP_PREPUSH; the hook does no network I/O; standard library only; no model in the scan.
```
