# claude-mem retention: executed runbook and results

Executed 2026-11-20 from a clean worktree at origin/master `5396683c38eb5a40e3847d439b2f591b9750ed3d`.
Starting evidence: [PR #446](https://github.com/Joaovsales/jplugin-agentic-development/pull/446),
audit commit `7946f117f85e386ccb52fefba7fde40f790ddb97`.
The audit was mergeable but absent from master at execution; it was read from its PR ref without merging it.

**Ranks 1, 2 and 4 are done. Rank 3 was not attempted: the owner required Chroma to remain enabled.**
The MCP bridge was repaired in its isolated environment. No Chroma-off trial or index deletion occurred.

All sizes below are exact **bytes**, with no GB/GiB conversions. Allocated storage uses `st_blocks * 512`.
Filesystem inventories are timestamped observations of live files, not an atomic cross-database snapshot.

## Storage accounting

This is the original retention checkpoint; it predates the durability follow-up software installation and test artifacts.

| Scope | Before allocated bytes | After allocated bytes |
|---|---:|---:|
| Live `<HOME>/.claude-mem` tree | 96979128320 | 67356229632 |
| Operation-created state, archives and private evidence | 0 | 11742363648 |
| Retained execution scratch | 0 | 278528 |
| Installed policy files | 0 | 20480 |
| **Owned data and operation artifacts** | **96979128320** | **79098892288** |

**Net reduction in this defined scope: 17880236032 allocated bytes.**
The retained rollback and retention exports are included; moving a file on the same disk is never counted as reclaim.
Shared pre-existing uv and model caches are outside this data-directory scope. No whole-machine attribution is claimed.
Measured filesystem free space changed from 128061882368 to 146284658688 bytes;
other live processes can affect that separate figure.
[sizes.json](sizes.json) lists each path; [measurements.json](measurements.json) holds the complete accounting.

| Rank | Status | Measured effect |
|---|---|---|
| 1 | done | Supported observer exclusion; 0 immediate bytes reclaimed |
| 2 | done | 24337131504 raw text bytes removed; main-file reduction 26509246464; sole full rollback archive costs 11411402752 allocated bytes |
| 3 | not attempted | Chroma enabled; 0 bytes reclaimed; off-state loss and latency not measured |
| 4 | done | 797565935 raw bytes expired; main-file reduction 795901952; 134 logs removed after verified archival, freeing 242987008 allocated bytes; exports cost 321146880 allocated bytes |

Charging the entire rollback archive once to rank 2 gives 15097843712 bytes of main-file reduction after that charge.
Rank 4 gives 717742080 bytes after charging its exports.
These component figures exclude incidental WAL/SHM changes, live Chroma growth, new logs and evidence overhead;
the total-scope figure above includes those changes.

The main-file checkpoints are distinct:

1. Fresh stopped-writer snapshot, including committed WAL: **27687800832** bytes.
2. After rank 2 and its compaction: **1178554368** bytes.
3. After rank 4 and its further compaction: **382652416** bytes, installed live.

Thus the intermediate 1178554368 and installed 382652416 sizes describe successive ranks.
The final inventory records WAL length 4095312 bytes and SHM length 32768 bytes.
The original WAL length was 2092733432 bytes. WAL capacity changed during shutdown/swap;
no manual WAL deletion or explicit rank-5 checkpoint was performed. Live WAL can grow again.

## Executed sequence and rollback proof

The authoritative command ledger is local, outside the repository:
`<HOME>/.local/state/claude-mem-retention/20261120/commands.json`.
It preserves commands in invocation order, including failures and superseded attempts.
`tool-calls.json` retains the enclosing calls; `events.jsonl` records SQL, subprocesses and state transitions.
Executable source for the operation is retained under that directory's `pipeline/`.
[private-evidence.json](private-evidence.json) supplies file digests and paths.
Verbatim evidence is withheld: it contains private session content.

1. Read the existing audit, inventory the store and physical volumes, and inspect the running producer.
2. Freeze `queries.json` before querying; execute the initial Chroma-on requests and retain their raw responses locally.
3. Take an online SQLite backup. The first copy completed but its validation was interrupted;
   it was misleadingly named `interrupted-backup.db`. It was never the proven rollback.
   A second standalone backup passed full `integrity_check`, `foreign_key_check`, and a scratch restore with
   identical SHA-256 plus matching counts in all five tables.
4. Apply rank 1; verify actual excluded hook calls create no rows, and verify ordinary paths remain included.
5. Announce maintenance, pause transcript intake, temporarily rename the worker entrypoint to fence respawn,
   stop the worker, and verify no writable database descriptors or in-flight worker entrypoint processes remain.
6. Take a **fresh** stopped-writer snapshot, preserving writes made after the initial backup.
   On that disposable copy, null only the verified observer-prefix session payloads and remove matching prompt rows.
   Preserve and restore the delete trigger, rebuild the affected FTS table, validate its external content,
   compact, and verify all session metadata, observations, summaries and the entire queue by fingerprints.
   Journaling was disabled only on this disposable offline work copy to avoid another full-size journal;
   the live original and proven backup remained intact. Normal journaling was restored afterward.
7. Run rank 4 on the copy, archive logs before unlinking them, compact again, and validate SQLite and FTS.
   There were zero pending/processing rows at this offline checkpoint; nonempty preservation cases are tested separately.
8. Recheck quiescence; retain the original database **with its WAL and SHM**; install the validated copy.
   Restore the original entrypoint and transcript setting, and restart with the scoped MCP shim.
   The start CLI exited by signal 9, but its daemon started successfully; independent process, HTTP and hook checks
   establish restoration instead of treating that CLI exit as success.
9. Run the fixed queries on the repaired live route; verify new genuine SDK observations and SQL-backed injection.
   Install and execute the recurring policy, then enable its timer.
10. Two partial gzip outputs and the earlier interrupted-validation snapshot were pruned after the owner requested
    headroom recovery. They were never trusted rollback artifacts. Consolidate the latest original family into
    one zstd archive, extract all members to independent scratch files, verify their byte hashes, SQLite checks and
    all five original table counts, and only then prune redundant raw snapshots and scratch restores.

**Exactly one full-database rollback artifact remains:**
`<HOME>/.local/state/claude-mem-retention/20261120/rollback-pre-cleanup.tar.zst`.
It is 11411397439 bytes; SHA-256: `6e342ce0bcf2a569ed5a35e9f69fe153bce9ffbd42f68eb887931fee761babfb`.
It preserves the latest original DB/WAL/SHM family. Each extracted file matched its source byte for byte;
SQLite `quick_check` returned `ok`, `foreign_key_check` returned no rows, and all original counts matched:
12715 sessions, 6799 observations,
23 summaries, 25735 prompts and
68850 queue rows. Free space immediately after pruning was 146279501824 bytes.
Retention exports and private evidence remain separately; they are included in footprint accounting.

### Rollback procedure

Announce a maintenance window and stop the retention timer. Fence the **currently installed** worker entrypoint,
stop it using the renamed entrypoint, and verify no writer or respawning hook process remains, as in the retained
`maintenance.py` and `quiescence.json`. Abort on any remaining writer.

Extract the archive into a new private directory, never over the current store:

```bash
set -euo pipefail
retention_restore=$(mktemp -d "$HOME/.local/state/claude-mem-retention/restore.XXXXXX")
zstd -dc "$HOME/.local/state/claude-mem-retention/20261120/rollback-pre-cleanup.tar.zst" |
  tar -xf - -C "$retention_restore"
```

Compare every member hash with `measurements.json`'s rollback manifest, then open the extracted SQLite family
and repeat the recorded checks and counts. Preserve the **current** live DB/WAL/SHM family in another unique
directory before installing the restored family under `claude-mem.db`, `claude-mem.db-wal` and `claude-mem.db-shm`.
Never discard WAL or overwrite the only current copy. Restore the entrypoint, start the worker, verify health,
injection and a genuine write, then resume the timer. Restoring an old snapshot rolls back later writes;
retain the current family for recovery of those writes. Settings before the operation remain locally in
`settings.before.json`; old log contents remain in verified retention exports. Neither contains public evidence.

## Rank 1 durability and rank 4 policy

Rank 1 uses the supported `CLAUDE_MEM_EXCLUDED_PROJECTS` setting in
`<HOME>/.claude-mem/settings.json`, adding the observer directory and its descendants.
This survives plugin updates; no installed-plugin source patch remains. Real session-init and observation hooks
against the excluded directory created zero rows. A matcher check confirmed that an ordinary project remains included.
All 5513 matching SDK payloads and 5514 matching prompt rows were cleaned;
no session, observation or summary was deleted by rank 2.

[retention.py](retention.py) is installed as `<HOME>/.local/bin/claude-mem-retention.py`.
It exports and verifies expired fields before mutation: failed payloads after 7 days,
initial session/raw prompt text after 90 days, and log files after 30 days.
Failed-at time takes precedence over creation time; pending/processing never match the failed predicate.
Both log filename date and last-write age must exceed the log window, protecting long-running dated logs.
Session IDs and durable observations/summaries are retained. Archive failure rolls back the DB transaction.
Exports are private and retained; the policy does not silently expire backups.

The supplied service/timer are installed under `<HOME>/.config/systemd/user/`.
The timer runs daily at 04:00 local with up to 300 seconds of jitter. It is enabled and active;
a real service execution returned `Result=success`, `ExecMainStatus=0`, with no newly expired payloads.
The program emits no success log line. Disable future runs with:

```bash
systemctl --user disable --now claude-mem-retention.timer
```

## Durable MCP repair and failure-only detection

Production capture identified **chroma-mcp 0.2.6, MCP framework 1.6.0, Pydantic 2.14.4 and ChromaDB 1.5.9**
in the failing uvx environment. Its own startup traceback showed MCP importing the removed
`eval_type_backport` symbol. Shared Python environments were not involved or downgraded.
The initial per-daemon PATH shim restored service, but was temporary; [shim.template.py](shim.template.py)
is retained only as a historical execution artifact. It is no longer needed or used.

### Persistent tool receipt

The current repair is declarative and scoped to the uv-managed `chroma-mcp` tool:

```bash
uv tool install --python 3.13 \
  --with-requirements docs/claude-mem-retention/chroma-mcp.requirements.txt chroma-mcp
```

[chroma-mcp.requirements.txt](chroma-mcp.requirements.txt) records both package and compatibility requirements.
The receipt at `<HOME>/.local/share/uv/tools/chroma-mcp/uv-receipt.toml` persists them independently of the
plugin cache. The unchanged `uvx --python 3.13 chroma-mcp` invocation selects that installed environment.
No global uvx shadow or global constraint is installed; unrelated tools use their own environments.

The live daemon was restarted **normally**, without an augmented PATH or UV constraint environment:

```bash
"$HOME/.bun/bin/bun" \
  "$HOME/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs" restart
```

The new daemon had no old shim directory in PATH, and its actual child interpreter came from
`<HOME>/.local/share/uv/tools/chroma-mcp/bin/`. Its environment resolved Pydantic **2.10.6**.
The restart CLI exited by signal 9, but independent checks confirmed the new daemon, HTTP health,
real semantic results and a fresh connection; a CLI exit alone is not treated as readiness proof.
The detector then exited **0 with zero stdout and stderr**.

Removing this scoped repair is `uv tool uninstall chroma-mcp`, followed by a normal worker restart;
that returns to unconstrained uvx resolution and may reproduce the original failure. The installed
tool receipt survives ordinary restarts and plugin-cache replacement. A future plugin can change its
invocation and bypass it, so the behavioral detector below remains necessary.

### Cause-agnostic detector

[semantic_health.py](semantic_health.py) asserts that the **semantic path answers**, without checking
or requiring a Pydantic version. Each run verifies:

- worker HTTP health and identity before sending the private query;
- a real, nonempty query through `/api/search`, requiring HTTP 200 and hydrated observation results;
- an anchored successful `CHROMA_MCP` connection marker in the current daemon's lifetime;
- no new anchored connection-failure events since the previous probe checkpoint.

The connection window starts at the current daemon's recorded start, rather than an arbitrary 24-hour
age limit: a healthy persistent connection is not failed just because its startup marker is old.
Failure events are compared by time, so log expiry cannot hide them by decreasing a cumulative counter.
Checkpoint corruption fails loudly. Hook text containing marker words cannot satisfy the anchored marker check.
The detector is an availability check, not a relevance grade.

Healthy execution emits **nothing** and exits **0**. Failure emits one structured JSON message on stderr
and exits **1**, naming the failed signal and an action. Backend/transport failure, missing connection
evidence, rising failures and empty results are all errors regardless of their cause. Private query text
and raw response bodies are never printed. MCP/Pydantic repair guidance is conditional, not the detector's remit.

The private known-result query lives in `<HOME>/.local/state/claude-mem-retention/semantic-probe.json`;
the checkpoint contains only times and counters. Its JSON schema is `{"query":"<private known-result text>"}`;
the existing file is owner-only and never committed. The probe sets an explicit all-time range so the normal
90-day search window cannot age its known result out; changes to the retained corpus may require refreshing it. The installed script is
`<HOME>/.local/bin/claude-mem-semantic-health.py`. The supplied service and timer are enabled under
`<HOME>/.config/systemd/user/`, running daily at 04:10 local with at most 300 seconds jitter.
The actual service run succeeded with exit 0. A failed run leaves the unit failed and its actionable stderr
in the user journal; there is no nightly success message.

**After every claude-mem plugin update, run the detector once and confirm it is silent:**

```bash
systemctl --user start claude-mem-semantic-health.service
```

Inspect failures with `journalctl --user -u claude-mem-semantic-health.service`.
Disable scheduling, without altering the worker, with
`systemctl --user disable --now claude-mem-semantic-health.timer`.

### Isolated fault injection and recovery

The installed plugin's startup reaper enumerates and kills other worker/Chroma processes globally;
a separate HOME alone would therefore be unsafe. Unprivileged PID namespaces were unavailable.
The canary used a private clone with only the global startup and orphan-CLI reapers disabled
(16 inserted bytes). Production's installed bundle was unchanged.
HTTP, search, SQLite and Chroma code remained real. Separate HOME, port, tiny synthetic canary database/index,
and UV_TOOL_DIR isolated all test state; no production database was copied or swapped.

Before breaking it, the canary established a real MCP connection, completed backfill, and returned its known
observation through the real API. The detector exited 0 with zero output. A first precondition attempt had
correctly rejected empty results before backfill; the fault was not injected until the known-good run passed.

The working isolated tool environment was snapshotted before mutation. The exact snapshot-restore command
was rehearsed successfully **before** injecting the fault, and ordinary uvx help succeeded against that
restored disposable environment. The receipt matched. That same snapshot restore was used for recovery,
without a dependency reinstall. Exact commands and scripts are retained locally and indexed in
[hardening-evidence.json](hardening-evidence.json).

The isolated tool was then given the original incompatible Pydantic requirement. Its real startup traceback
reproduced the removed-symbol import error. Worker health still answered, while semantic search failed:
the detector exited **1**, produced **0 stdout bytes**, and emitted an actionable failure naming HTTP 500,
missing current-daemon connection evidence and a new failure event. After snapshot restoration,
the real backend reconnected, returned results, and the detector exited **0 with zero stdout/stderr**.

Measured isolated broken window: **2.979464 seconds**.
Production broken window: **0 seconds**. An earlier proof before the all-time query refinement measured
3.142058 seconds; both runs are retained, and the current figure is the final all-time-probe run. Fault-test subprocesses had a 60-second limit;
worker readiness had 30 seconds, shutdown 15 seconds plus a 5-second forced-reap limit, and each probe
HTTP request 30 seconds. No artificial backoff wait was needed. The earlier ordinary-restart helper
had a 180-second subprocess limit and was independently checked for readiness.

Production's worker, uvx parent and Python/MCP identities were unchanged before and after the test,
including process start ticks; 6 intervening samples also checked health and identities.
The raw PID evidence stays private, with matching identity hashes in the public evidence.
The post-test production detector returned 0 with zero output, and no canary processes remained.

Connection markers, with private fields omitted (logger-local time, UTC−03 on this machine):

```text
production ordinary restart: [2026-11-20 12:49:02.019] Connected to chroma-mcp successfully
canary known good:          [2026-11-20 13:18:33.441] Connected to chroma-mcp successfully
canary restored:            [2026-11-20 13:18:38.296] Connected to chroma-mcp successfully
```

Historical anchored logs showed first backoff at `2026-04-27 10:26:39.117`, a last pre-repair successful
connection at `2026-10-06 18:28:36.633`, and completed backfill at `2026-10-06 18:30:33.506`.
Successful semantic-query details used DEBUG while retained settings used INFO: the last historical
successful semantic query is **unknown**. Continuous failure since April or October is not established.

A scratch SQLite-to-Chroma rebuild indexed 8 observation documents and returned the expected self-query result.
The owner accepted that as the rank-3 rebuild rollback precondition; it was not a full-index/ranking restore test.

## Search instrument, relevance and corpus caveat

The original ten-query file was fixed before any request or cleanup:
`<HOME>/.local/state/claude-mem-retention/20261120/queries.json`.
SHA-256 over **every byte**: `844e3b6da9716898bf015b644a6113578be07f03afe52a2a65d719defe0a9e9a`.
Reproduce locally, without displaying the queries:

```bash
sha256sum "$HOME/.local/state/claude-mem-retention/20261120/queries.json"
```

Eight query texts came from the latest observations in eight distinct non-observer projects; two were intended filter controls.
The unfiltered request is invalid, leaving **one valid control out of two**, and nine valid requests out of ten.
The initial ON arm returned transport errors for all eight semantic queries. The repaired ON arm returned three results
for each semantic query because **3 was the explicit API limit**, not a quality measurement.
The same query text was then frozen in a supplemental protocol with limit 10 before running or grading it.
[search.json](search.json) records query hashes, lengths, response hashes, status, counts, latency and grades.
All raw responses and the grading evidence remain private.

The successful arm is **the repaired, post-cleanup corpus**, not a historical working-on arm.
All original observations survived cleanup byte for byte, but fresh observations were added after restart.
The supplemental SQL observation fingerprint stayed unchanged during its run; Chroma was not independently frozen.

The pre-fixed manual rubric labels a record **direct** if it addresses the concrete object/change/failure requested,
**related** if it shares broader context without answering that topic, and **irrelevant** otherwise.
The original source observation is relevant by construction. Judgement used returned titles and narrative excerpts;
full fields were checked for discriminating concepts in the three zero-direct queries. This was self-assessed,
not blinded; duplicate returned records count separately. Private subject matter is withheld.

| Query | Direct / 10 | Related / 10 | Irrelevant / 10 | Known source found | Source position |
|---|---:|---:|---:|---|---:|
| Q01 | 3 | 7 | 0 | yes | 1 |
| Q02 | 2 | 7 | 1 | yes | 3 |
| Q03 | 0 | 0 | 10 | no | absent |
| Q04 | 3 | 7 | 0 | yes | 2 |
| Q05 | 1 | 6 | 3 | yes | 6 |
| Q06 | 2 | 6 | 2 | yes | 8 |
| Q07 | 0 | 1 | 9 | no | absent |
| Q08 | 0 | 0 | 10 | no | absent |

Across 80 records: **11 direct, 34 related, 35 irrelevant**; known-source hit **5/8**;
first-returned direct **2/8**. The source hydrator defaults to date-descending order, so returned order
is not necessarily vector-distance order. The results demonstrate some useful recall and substantial noise.
They do not establish that the entire current Chroma footprint is necessary.

**Chroma remains enabled. No OFF loss or ON/OFF latency difference was measured.**
Per-request timings are in `search.json`; comparing failed-request latency with successful retrieval is not a semantic-search A/B.

### Proposed owner-approved A/B, not executed

1. Pause transcript intake and ordinary capture, drain active work, and record stable SQL-observation and Chroma-ID fingerprints.
2. Freeze a new instrument version retaining the eight query texts and correcting the invalid control;
   freeze the direct/related/irrelevant rubric before running either arm.
3. Warm the route, run three identical ON passes, and retain responses and paired timings privately.
4. Restart with Chroma OFF, repeat the same requests, and verify corpus fingerprints are unchanged.
5. Restore Chroma ON and capture, and verify health, injection and genuine writes.
6. Quantify loss of directly relevant records and source hits per query, unchanged/degraded/empty queries,
   control failures and paired latency. Any useful loss requires explicit owner acceptance before keeping Chroma off.
   Require all valid filter/injection/ID controls to pass. Disabling alone reclaims zero index bytes.

The proposed trial window is 14 days **after** owner approval and acceptance of measured losses;
it has not started. Restore ON if a real task requires missing recall or any preserved-path control fails.
The present recommendation is to keep Chroma enabled pending that controlled decision.

## Validation and publication

The production entrypoint is restored, the fence file is absent, health/stats return HTTP 200,
and genuine session processing has produced new observations. Real-project injection returned HTTP 200 with
5385 bytes at its recorded checkpoint; no fabricated observation was inserted.

`python3 docs/claude-mem-retention/test_retention.py` covers age boundaries, failed-at age,
pending/processing preservation, archive recovery, archive-failure rollback and idempotence.
Measured utility statement coverage is 84 percent. Systemd unit verification and an actual service execution passed.
The semantic detector has 86 percent statement coverage. `tests/test-claude-mem-retention.sh` runs both policies' regression fixtures in CI. Repository-suite results are recorded in the pull request.

All committed files are structural evidence or generic code. No verbatim query, prompt, tool argument/result,
observation body, summary, session title, private identifier or credential is published. Home paths are sanitized.
The runbook and executable policy artifacts live under `docs/`; session bookkeeping lives under `tasks/`.
The manifest's payload paths are
`.agents/skills`, `.agents/hooks`, `.agents/references` and `hooks`.
The plugin version guard therefore requires **no version bump**.
