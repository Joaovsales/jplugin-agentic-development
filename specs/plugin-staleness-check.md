---
implementation_paths:
  - .agents/hooks/session-start.sh
  - .claude-plugin/plugin.json
  - README.md
  - tests/test-session-start.sh
  - tests/test-plugin-manifest.sh
---

# Spec: Stale Plugin Install Check

## Behavior

The session-start banner tells the user when their installed `jplugin@jplugin-agentic-development`
plugin is older than the template they could be running, and prints the exact commands that
bring it current. It never runs them: `claude plugin update` needs a restart and would swap
the skills out from under the running session. When the install is current, it prints nothing
(AGENTS.md § Observability Discipline).

On 2026-09-29 `~/.claude/plugins/installed_plugins.json` recorded version `1.0.0` at
`gitCommitSha` `7980eff` (installed 2026-09-21) while master was at `b2b5634` with
`plugin.json` version `1.1.0`, and the marketplace clone had not been refreshed since
2026-09-21. Nothing said so; it was found and fixed by hand.

A template-side test makes the other half of that failure impossible to merge: a change to
the plugin payload without a `plugin.json` `version` bump never reaches any install.

### Why a bump is required (probe, 2026-09-29, Claude Code 2.1.277)

An isolated `CLAUDE_CONFIG_DIR` with a git-sourced marketplace served over local smart HTTP
(`claude plugin marketplace add` refuses `file://` and `git://`) measured:

| Step | `installed_plugins.json` record | cached skill |
|---|---|---|
| install at `1.0.0` | `1.0.0` `af3f035…` | `v1` |
| commit a skill change, version unchanged; `marketplace update` (clone now at the new commit); `plugin update` | unchanged — *"probe is already at the latest version (1.0.0)"* | `v1` |
| commit a skill change **and** bump to `1.0.1`; `marketplace update`; `plugin update` | `1.0.1` `7fed8e1…` — *"updated from 1.0.0 to 1.0.1"* | `v3` under `cache/…/1.0.1/` |
| unbumped change again; `marketplace update`; `plugin uninstall` + `plugin install` (user scope) | `1.0.1` `8f9d50b…` (new sha, same version dir) | `v4` |
| `plugin install --scope project` then `plugin uninstall --scope project` | — | `.claude/settings.json` `enabledPlugins` loses the entry |

So `claude plugin update` compares versions only: an unbumped merge never reaches an install
through the update path. A user-scope reinstall does pick it up, but a project-scope uninstall
deletes the project's committed plugin declaration, so it is never the printed remedy.

## Inputs

- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json` — the
  `jplugin@jplugin-agentic-development` records: `scope`, `projectPath`, `version`,
  `gitCommitSha`.
- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/jplugin-agentic-development/` —
  the marketplace clone Claude Code installs from: its `HEAD` and its
  `.claude-plugin/plugin.json`.
- The current repository's remote-tracking refs for any remote whose URL ends in
  `/jplugin-agentic-development` (`.git` optional): `workflow/<branch>` in a synced project,
  which the Workflow Template Drift Check fetches at most once per 24h; `origin/<branch>` in
  the template's own clone, fetched by the user. The branch is the remote's `HEAD` symref when
  recorded, else the drift-check cache's branch for `workflow`, else `master`, else `main`.

No network call is made; only what the last fetch recorded is read.

## Outputs

When at least one relevant record is stale:

```
⬆  PLUGIN UPDATE AVAILABLE — jplugin@jplugin-agentic-development <scope> install is at <version> (<sha7>); the template is at <version> (<sha7>)
    claude plugin marketplace update jplugin-agentic-development
    claude plugin update jplugin@jplugin-agentic-development
    claude plugin update jplugin@jplugin-agentic-development --scope project
    Restart Claude Code afterwards — the banner never runs these (an update swaps skills mid-session).
```

One headline per stale record, one `marketplace update` line, and one `plugin update` line per
stale record's scope (`--scope` omitted for `user`).

When the newer template carries the **same** `version` as the stale record, `plugin update`
would report "already at the latest version", so the block says so instead of printing it:

```
    plugin.json version <v> was not bumped — 'claude plugin update' is a no-op (README § Releasing skills).
    User scope: claude plugin uninstall jplugin@jplugin-agentic-development && claude plugin install jplugin@jplugin-agentic-development
```

A project- or local-scope record in that state gets no reinstall line (it would delete the
project's `enabledPlugins` entry); the note stands alone.

## Edge Cases

- No `installed_plugins.json`, no jplugin record, or a record with no `gitCommitSha`
  (a directory-sourced install from `install.sh`, which loads in place) → silent.
- A project- or local-scope record for a different `projectPath` → ignored. Paths compare after
  `\\`→`/`, a trailing `/` stripped, lowercased; the current path is `pwd -W` when available
  (Git Bash), else `pwd`.
- The record sha is not an object in the current repository (the local ref is older than the
  install) → the repository ref yields no finding; the marketplace clone may still.
- The record sha is ahead of or diverged from the repository ref → not stale.
- The marketplace clone is shallow, so ancestry is not asked there: Claude Code installs from
  that clone and the clone only moves forward, so `record sha ≠ clone HEAD` means behind.
- No marketplace clone and no matching remote → silent.
- The repository is not adopting the workflow (no `.agents/skills/`, plugin not enabled in
  `.claude/settings.json`) → silent: the plugin is installed at user scope and this hook runs in
  every repository the user opens (specs/single-instruction-file.md, D18).
- Malformed `installed_plugins.json` → no record parses → silent; the banner never aborts
  (`set -eo pipefail` stays safe).

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Run the update or warn? | Warn only, print exact commands | user | an update needs a restart and swaps skills mid-session |
| 2 | Staleness signal | record `gitCommitSha` behind the newest known template sha | user | version alone misses unbumped merges; the sha is what was cached |
| 3 | Which records | `user` scope plus every `project`/`local` record whose `projectPath` is the current directory | user | those are the ones that load in this session |
| 4 | Where the template sha comes from | marketplace clone `HEAD` and the matching remote's last-fetched ref, no new fetch | user | the incident had a stale marketplace clone, so the clone alone misses it; the drift check already owns the capped, cached fetch |
| 5 | Does `claude plugin update` pick up unbumped commits? | No — measured (§ Why a bump is required) | user | the cache is keyed by version and update compares versions |
| 6 | How is the bump enforced? | `tests/test-plugin-manifest.sh`: a diff of the plugin payload (`PAYLOAD_PATHS`: `.agents/skills`, `.agents/hooks`, `.agents/references`, `hooks`) against the base requires a `version` greater than the base's; an assertion fails when any `${CLAUDE_PLUGIN_ROOT}/<dir>` read lies outside that list | assumed (`.agents/references` added at the quality gate: skills read it from the plugin root) | CI runs the suite on every PR; the README rule already existed and was not followed (1.1.0 shipped with #177, six payload merges followed unbumped) |
| 7 | Base for that diff | `$PLUGIN_VERSION_BASE`, else `HEAD^1` when HEAD is already on `origin/master` (a push to master), else `merge-base HEAD origin/master` (a PR merge checkout or a local branch); no `origin/master` → skipped with a note | assumed | covers the CI pull_request merge commit, the master push, and a local branch alike |
| 8 | Remedy printed for an unbumped template | the no-op note plus a user-scope reinstall; never a project-scope uninstall | assumed | the probe showed `uninstall --scope project` deletes the committed `enabledPlugins` entry |
| 9 | JSON parsing | `sed`/`tr`, no `jq`/`python` | assumed | the hook's existing rule: an optional binary must not make a banner block vanish |
| 10 | Relation to `/tidy installed` | cite it; this block reads the same record for a different question (freshness, not presence/content) | user | `.agents/skills/tidy/SKILL.md` § `installed` compares installed copies; duplicating it would fork one reading into two |
| 11 | Gate | adopting repositories only, same as the Managed Block Check | assumed | D18 |

## Acceptance Criteria

- A fixture with a user-scope record at sha A and a marketplace clone at a descendant B prints
  `PLUGIN UPDATE AVAILABLE`, `claude plugin marketplace update jplugin-agentic-development` and
  `claude plugin update jplugin@jplugin-agentic-development` exactly once each.
- A project-scope record for the current directory at a stale sha prints the `--scope project`
  update line; a project-scope record for another path prints nothing for that record.
- A fixture whose marketplace clone is at the record's sha but whose repository has a matching
  remote ref ahead of it prints the block (the 2026-09-29 incident).
- The record sha equal to every known template sha prints no `PLUGIN UPDATE` line.
- A record with no `gitCommitSha`, a missing `installed_plugins.json`, a malformed one, or a
  non-adopting repository prints no `PLUGIN UPDATE` line and the banner still completes.
- When the newer template has the record's `version`, the block prints the not-bumped note and
  the user-scope reinstall line, and prints no `claude plugin update` line for that record.
- The hook makes no network call in this block (no `fetch`, `ls-remote` or `curl` added).
- `tests/test-plugin-manifest.sh` fails when a payload path differs from the base while
  `version` does not increase, passes when it increases, and skips with a note when no base
  resolves; it passes on this branch because `plugin.json` is bumped.
- README § Releasing skills states that `claude plugin update` ignores unbumped commits (measured)
  and that the suite enforces the bump.

## Implementation Paths

- `.agents/hooks/session-start.sh` — the Stale Plugin Install block, after the Plugin
  Declaration Check.
- `.claude-plugin/plugin.json` — `version` bumped for this payload change.
- `README.md` — § Releasing skills: the measured behaviour and the enforced rule.
- `tests/test-session-start.sh` — fixtures for every acceptance criterion of the banner block.
- `tests/test-plugin-manifest.sh` — the version-bump guard.

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: 7 ACs — every one is a fixture of the same banner block in one test file; splitting it would split one parser across two sessions.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Stale plugin banner block | the banner prints the update commands for every stale relevant record, silent otherwise | `.agents/hooks/session-start.sh`, `tests/test-session-start.sh` | — | 1–7 | `bash tests/test-session-start.sh` | 2 files · 2 systems · 7 ACs |
| 2 | Plugin version bump guard | the suite fails a payload change without a version bump; README states the measured rule | `.claude-plugin/plugin.json`, `README.md`, `tests/test-plugin-manifest.sh` | — | 8, 9 | `bash tests/test-plugin-manifest.sh` | 3 files · 3 systems · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/plugin-staleness-check.md`.
Plan: `## Plan: plugin-staleness-check` in `tasks/todo.md`, 2 slices, ready set <1, 2>.
Files: .agents/hooks/session-start.sh, .claude-plugin/plugin.json, README.md, tests/test-session-start.sh, tests/test-plugin-manifest.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/plugin-staleness-check.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: never run `claude plugin update` from the hook (D1); no network call in the block (D4); never print a project-scope uninstall (D8); no jq/python in the hook (D9).
```
