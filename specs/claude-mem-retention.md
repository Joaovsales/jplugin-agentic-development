---
implementation_paths:
  - specs/claude-mem-retention.md
---

# Spec: claude-mem consumption, retention and workflow producer

**Status:** investigation and proposal; no cleanup or routine implemented.
**Observed:** 2026-11-18, starting 17:51:52 UTC.
**Repository base:** origin/master `887e95930fab2edf68197e6386d49fef8df2cf71`.
**Refs:** [read-shunt research](read-shunt.md), [baseline contract](read-shunt-baseline.md).
**Authority:** owner requested this one spec and one PR, no registry issues, no changes
under `<HOME>/.claude-mem`, no stopped processes, no helper agents.

## Behaviour

### Recommendation

Keep the useful SQL-backed context mechanism while stopping observer self-capture.
Do not treat 91 GB as the price of a useful vector index: most bytes are duplicated
observer prompts and text search structures, not vectors. Retention and configuration
are the first interventions; discontinuation is a reversible later decision after a
measured trial. All maintenance commands below are proposals, **not executed**.

The existing read-shunt work already chose measurement before gating and anchored
excerpts over prose. Its baseline found no justification for a new project read gate.
This proposal preserves that decision. Installed claude-mem independently registers
a file-context gate; it is not this repository's proposed shunt.

The requested `.agents/skills/build/references/subagent-resilience.md` is absent
at this origin/master revision. The installed copy at
`<HOME>/.agents/skills/build/references/subagent-resilience.md` was read.
It documents retrieval-placeholder loops and correctly advises narrow reads.
The installed evidence identifies **Headroom**, rather than claude-mem's Chroma,
as the hash-based recovery path in those incidents.

### A. Consumption: registration, execution and measured use

Paths and command literals below use `<HOME>`; expand it to your home directory
before running any example.

Paths in this section use:

- `P = ~/.claude/plugins/cache/thedotmack/claude-mem/12.1.6` (running bundle).
- `U = ~/.claude/plugins/marketplaces/thedotmack` (readable source,
  revision `53622b59e987bc9cd652d7e11ff9fa352dd7a856`).
- `M = ~/.claude-mem`.

Readable source helps locate functions; runtime conclusions were cross-checked
against P's bundle. Its SHA-256 is
`ac3ac20d9da9c1f2c5f8ba48a2dcb82ba552b83ed4db9bb5c5a4d6492e35c4b5`
for `scripts/worker-service.cjs`, and
`0d5762869b29e4df2b28d33e60723cc444795fc5d95133dcf7cf15747aea8da3`
for `scripts/mcp-server.cjs`. Offsets below are Python string character offsets,
not byte offsets or fabricated source line numbers.

| Consumer | Registration and actual path | What reaches the model |
|---|---|---|
| Claude Code session context | `~/.claude/settings.json`: `"claude-mem@thedotmack": true`; P/hooks/hooks.json SessionStart matcher `startup\|clear\|compact` executes `worker-service.cjs hook claude-code context` | Recent SQL observations and summaries, through SessionStart `additionalContext` |
| Explicit historical search | P/.mcp.json registers `"mcp-search": {"type":"stdio","command":"bun","args":["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-server.cjs"]}` | `search` → `/api/search`; `timeline` → `/api/timeline`; `get_observations` → POST `/api/observations/batch`; SQL hydration of selected IDs |
| File-context recall | P/hooks/hooks.json PreToolUse matcher `Read` executes `hook claude-code file-context` | Queries `/api/observations/by-file`; can supply observation titles and replace a whole-file Read with `limit=1` |
| Codex workspace context | M/transcript-watch.json watches `~/.codex/sessions/**/*.jsonl`, `startAtEnd:true`, `context: {mode:"agents", updateOn:["session_start","session_end"]}` | Watcher obtains `/api/context/inject` and writes a context block into workspace AGENTS.md; configuration proves the route, not that every Codex workspace contains such a block |
| Code tools bearing the plugin name | MCP `smart_outline`, `smart_unfold`, `smart_search` | Reads current source via filesystem/tree-sitter; those calls do **not** justify retaining historical Chroma data |

The SessionStart handler at U/src/cli/handlers/context.ts:44–90 contains:

```typescript
const apiPath = `/api/context/inject?projects=${encodeURIComponent(projectsParam)}&platformSource=${encodeURIComponent(platformSource)}`;
const [response, colorResponse] = await Promise.all([
  workerHttpRequest(apiPath),
  showTerminalOutput ? workerHttpRequest(colorApiPath).catch(() => null) : Promise.resolve(null)
]);
// ...
hookSpecificOutput: {
  hookEventName: 'SessionStart',
  additionalContext
}
```

P's bundle contains that handler near `iR={async execute`, and
`handleContextInject=` at offset 1884155. ContextBuilder queries the SQL
ObservationCompiler, not Chroma:

```sql
FROM observations o
LEFT JOIN sdk_sessions s ON o.memory_session_id = s.memory_session_id
WHERE o.project = ?
ORDER BY o.created_at_epoch DESC
LIMIT ?
```

The full query also filters observation type, concepts and platform. See
U/src/services/context/ObservationCompiler.ts:25 and
ContextBuilder.ts:150. Worktrees combine parent and child project names.
M/settings.json sets:

```json
{
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "50",
  "CLAUDE_MEM_CONTEXT_FULL_COUNT": "0",
  "CLAUDE_MEM_CONTEXT_SESSION_COUNT": "10",
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY": "true",
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_MESSAGE": "false",
  "CLAUDE_MEM_CONTEXT_SHOW_TERMINAL_OUTPUT": "true",
  "CLAUDE_MEM_SEMANTIC_INJECT": "false",
  "CLAUDE_MEM_CHROMA_ENABLED": "true",
  "CLAUDE_MEM_EXCLUDED_PROJECTS": ""
}
```

Thus session injection uses at most 50 observation index entries and up to ten
summary timeline entries, plus rendering and possibly the latest full summary.
Zero full observations does not mean zero injected tokens. Terminal output is a
second colored fetch for display; it must not automatically be charged as a second
model-context injection.

**Observed frequency and budget.** A structural scan of all 430 local Claude JSONL
files (825,383,432 bytes at discovery; 170,199 lines) found 354 valid claude-mem
context hook results across 320 distinct transcript files: 313 startup, six clear,
35 compact; all 354 were nonempty and none of the selected hook stdout payloads
failed JSON parsing. Injected strings were 82–6,636 characters, median 5,938;
UTF-8 bytes were 82–6,904, median 6,217; total 2,058,526 bytes.

With `tiktoken cl100k_base` as an explicitly named **proxy, not Claude's billing
tokenizer**, these strings occupy 29–1,905 tokens, median 1,754, total 583,979.
Median share is about 0.88% of a 200,000-token window or 0.18% of a 1,000,000-token
window; the actual session window is not inferred from those examples.
A simple characters/4 estimate gives median 1,485 tokens. System prompt/tool
schema overhead and cache billing are separate and were not measured. Automatic
recall is real and routine; these measurements do not establish that each injected
entry helped a task or that its text persisted unchanged after compaction.

Structured PostToolUse records in 157 dated plugin logs, April 17–November 18,
show **18 get_observations calls, one search, zero timeline**, plus 70
smart_outline, 69 smart_unfold and one smart_search. The latest logged
get_observations was October 18; the one search was August 13. Logs are an
incomplete observation channel and hooks can be skipped, so these are observed
counts, not a complete lifetime request ledger. Generic route strings inside
queued Bash commands were explicitly excluded as ingestion text, not API calls.
The independent local transcript scan found one actual get_observations tool-use
block and no actual search/timeline block, versus 16 Headroom retrieval calls in
five transcripts. These populations cover different retained history and are not
combined into a single denominator.

**The compaction distinction is consequential.** `~/.claude.json` registers
`headroom mcp serve`; Codex config sets `model_provider = "headroom"` and a
Headroom MCP server. Installed
`venv/lib/python3.12/site-packages/headroom/ccr/mcp_server.py:390` imports
`get_compression_store` from `headroom.cache.compression_store`; its
`_retrieve_content` checks the local compression store and then the proxy.
Line 529 returns the same error quoted in the resilience guide:

```text
Content not found. It may have expired or the hash may be incorrect.
```

The compression store describes in-memory TTL storage; its default CCR TTL is
1,800 seconds, and MCP compression uses a 3,600-second session TTL. No
claude-mem reference was found in the installed Headroom CCR Python sources.
Plugin logs separately contain 690 `mcp__headroom__headroom_retrieve` calls.
This is positive evidence of a separate retrieval implementation, not a claim
that all compression failures have one cause. Retiring Chroma will not repair
Headroom expiration, and the resilience guide's bounded reads remain appropriate.

For Codex, U/src/services/transcripts/processor.ts:342–366 says:

```typescript
if (!watch.context) return;
if (watch.context.mode !== 'agents') return;
// ...
const agentsPath = expandHomePath(watch.context.path ?? `${cwd}/AGENTS.md`);
writeAgentsMd(agentsPath, content);
```

The target checkout and audit worktree's AGENTS.md had no claude-mem context block
at inspection. Configuration proves potential injection, not universal delivery.
Orca's journal and vault are separate stores; their already-established
references to claude-mem are not evidence that Orca queries this vector collection.

The investigation emits these single-witness findings; none was auto-applied:

- [SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: human]
  M/claude-mem.db — internal observer prompts occupy 24,337,131,504 raw
  bytes across two fields; continued observer ingestion multiplies storage.
- [SHOULD-FIX | confidence: 100 | autofix_class: advisory | owner: human]
  M/chroma/chroma.sqlite3 — the retained collection repeats document text in
  several structures despite sparse observed historical queries and stale updates.
- [SHOULD-FIX | confidence: 75 | autofix_class: manual | owner: human]
  U/src/services/sqlite/PendingMessageStore.ts — 67,470 failed messages persist
  without an age policy; indefinite failed ingestion consumes space without recall.

### B. Storage accounting

All exact sizes below are bytes. Decimal GB and binary GiB must not be conflated:
the initial allocation was **96,967,327,744 bytes, approximately 90.31 GiB**,
consistent with a rounded “91 GB” report. Logical regular-file lengths totaled
96,966,046,761 bytes. The before inventory has 181 entries and records path,
length, allocated blocks, inode and mtime; it includes directory allocation.

| Path | Regular-file bytes | Allocated bytes including directory entries | Files |
|---|---:|---:|---:|
| chroma | 66,914,465,714 | 66,914,516,992 | 6 |
| claude-mem.db | 27,677,945,856 | 27,677,958,144 | 1 |
| claude-mem.db-shm | 32,768 | 32,768 | 1 |
| claude-mem.db-wal | 2,092,733,432 | 2,092,740,608 | 1 |
| corpora | 0 | 4,096 | 0 |
| logs | 279,613,979 | 280,784,896 | 157 |
| observer-sessions | 8,673 | 16,384 | 3 |
| settings.json | 2,431 | 4,096 | 1 |
| supervisor.json | 250 | 4,096 | 1 |
| transcript-watch-state.json | 481,600 | 487,424 | 1 |
| transcript-watch.json | 3,212 | 4,096 | 1 |
| watchdog.log | 751,878 | 757,760 | 1 |
| watchdog.py | 6,890 | 8,192 | 1 |
| worker.pid | 78 | 4,096 | 1 |
| Root directory itself | 0 | 4,096 | 0 |

Only one Chroma collection exists: **cm__claude-mem**,
ID `0c6f41b6-4f02-4706-a72a-4bf63eb0955f`, dimension 384, 66,004 embedding rows.
Its vector segment is `05a34ee5-938a-44b2-b3da-0ed7d6554349`, metadata segment
`eda84454-6e1b-4cac-8e26-35a4929ee2e9`. IDs classify into 41,672 observation
field documents, 24,206 prompt documents and 126 summary field documents.
There are no other collections to divide shared SQLite metadata among.
The collection's data/index directory totals 114,935,730 regular-file bytes:

| Segment file | Bytes |
|---|---:|
| data_level0.bin | 110,931,088 |
| header.bin | 100 |
| index_metadata.pickle | 3,155,370 |
| length.bin | 264,752 |
| link_lists.bin | 584,420 |

Chroma SQLite occupies 66,799,529,984 bytes. Its mtime was October 9 at 09:54
local time, whereas the primary store remained live in November. Thus even the
vector history is stale, not a successful mirror of all current ingestion.
The standalone HNSW files are only about 115 MB. Chroma stores exactly
12,525,097,167 document-text bytes in both `embedding_metadata` under
`chroma:document` and `embedding_fulltext_search_content`; its string-value
index repeats those documents again, before the 28.57 GB trigram index. The bulk is text repeated in
metadata, a string-value B-tree index, a separate FTS content copy and a trigram
FTS index.

#### Exact SQLite object allocation

The following tables list every allocated table and index returned by `dbstat`,
including SQLite's schema object. Bytes are physical pages, not approximate
lengths of values; payload and page slack have different meanings. FTS virtual
table declarations have no separate pages: the listed shadow tables own their
storage, so they must not be counted twice.

Queries used `mode=ro&immutable=1`: main-file state excludes the current WAL.
Live writer changes mean these are observations of main-file state, not an atomic
transactional snapshot across both databases. Chroma was stable at its old mtime.
No checkpoint, VACUUM or live write was issued by the investigator.

**claude-mem.db**

| Object | Pages | Bytes |
|---|---:|---:|
| user_prompts | 3,067,393 | 12,564,041,728 |
| sdk_sessions | 3,007,679 | 12,319,453,184 |
| user_prompts_fts_data | 553,248 | 2,266,103,808 |
| pending_messages | 118,695 | 486,174,720 |
| observations | 4,298 | 17,604,608 |
| observations_fts_data | 1,632 | 6,684,672 |
| user_prompts_fts_idx | 959 | 3,928,064 |
| idx_pending_messages_claude_session | 856 | 3,506,176 |
| idx_user_prompts_lookup | 333 | 1,363,968 |
| idx_user_prompts_claude_session | 317 | 1,298,432 |
| idx_pending_messages_status | 278 | 1,138,688 |
| idx_pending_messages_session | 201 | 823,296 |
| idx_user_prompts_created | 172 | 704,512 |
| sqlite_autoindex_sdk_sessions_1 | 155 | 634,880 |
| idx_sdk_sessions_claude_id | 155 | 634,880 |
| idx_sdk_sessions_project | 94 | 385,024 |
| idx_observations_sdk_session | 92 | 376,832 |
| idx_sdk_sessions_started | 84 | 344,064 |
| sqlite_autoindex_sdk_sessions_2 | 81 | 331,776 |
| idx_sdk_sessions_sdk_id | 81 | 331,776 |
| user_prompts_fts_docsize | 66 | 270,336 |
| idx_user_prompts_prompt_number | 64 | 262,144 |
| idx_observations_content_hash | 59 | 241,664 |
| idx_sdk_sessions_status | 54 | 221,184 |
| idx_observations_project | 54 | 221,184 |
| idx_sdk_sessions_platform_source | 49 | 200,704 |
| idx_observations_created | 45 | 184,320 |
| observations_fts_docsize | 32 | 131,072 |
| idx_observations_type | 31 | 126,976 |
| session_summaries | 17 | 69,632 |
| session_summaries_fts_data | 12 | 49,152 |
| observations_fts_idx | 8 | 32,768 |
| sqlite_schema | 5 | 20,480 |
| user_prompts_fts_config | 1 | 4,096 |
| sqlite_sequence | 1 | 4,096 |
| sqlite_autoindex_schema_versions_1 | 1 | 4,096 |
| session_summaries_fts_idx | 1 | 4,096 |
| session_summaries_fts_docsize | 1 | 4,096 |
| session_summaries_fts_config | 1 | 4,096 |
| schema_versions | 1 | 4,096 |
| observations_fts_config | 1 | 4,096 |
| idx_session_summaries_sdk_session | 1 | 4,096 |
| idx_session_summaries_project | 1 | 4,096 |
| idx_session_summaries_created | 1 | 4,096 |
| Free pages | 0 | 0 |
| Unattributed file overhead | 1 | 4,096 |
| **File total** | **6,757,311** | **27,677,945,856** |

**chroma/chroma.sqlite3**

| Object | Pages | Bytes |
|---|---:|---:|
| embedding_fulltext_search_data | 6,973,892 | 28,565,061,632 |
| embedding_metadata_string_value | 3,078,934 | 12,611,313,664 |
| embedding_metadata | 3,073,462 | 12,588,900,352 |
| embedding_fulltext_search_content | 3,064,855 | 12,553,646,080 |
| sqlite_autoindex_embedding_metadata_1 | 4,405 | 18,042,880 |
| embedding_fulltext_search_idx | 1,731 | 7,090,176 |
| embeddings | 1,363 | 5,582,848 |
| embedding_metadata_int_value | 1,304 | 5,341,184 |
| sqlite_autoindex_embeddings_1 | 1,063 | 4,354,048 |
| embedding_fulltext_search_docsize | 175 | 716,800 |
| embeddings_queue | 6 | 24,576 |
| migrations | 4 | 16,384 |
| sqlite_schema | 3 | 12,288 |
| tenants | 1 | 4,096 |
| sqlite_autoindex_tenants_1 | 1 | 4,096 |
| sqlite_autoindex_segments_1 | 1 | 4,096 |
| sqlite_autoindex_segment_metadata_1 | 1 | 4,096 |
| sqlite_autoindex_migrations_1 | 1 | 4,096 |
| sqlite_autoindex_max_seq_id_1 | 1 | 4,096 |
| sqlite_autoindex_maintenance_log_1 | 1 | 4,096 |
| sqlite_autoindex_databases_2 | 1 | 4,096 |
| sqlite_autoindex_databases_1 | 1 | 4,096 |
| sqlite_autoindex_collections_2 | 1 | 4,096 |
| sqlite_autoindex_collections_1 | 1 | 4,096 |
| sqlite_autoindex_collection_metadata_1 | 1 | 4,096 |
| segments | 1 | 4,096 |
| segment_metadata | 1 | 4,096 |
| max_seq_id | 1 | 4,096 |
| maintenance_log | 1 | 4,096 |
| embeddings_queue_config | 1 | 4,096 |
| embedding_metadata_float_value | 1 | 4,096 |
| embedding_metadata_array_key_string | 1 | 4,096 |
| embedding_metadata_array_key_int | 1 | 4,096 |
| embedding_metadata_array_key_float | 1 | 4,096 |
| embedding_metadata_array_id_key | 1 | 4,096 |
| embedding_metadata_array | 1 | 4,096 |
| embedding_fulltext_search_config | 1 | 4,096 |
| databases | 1 | 4,096 |
| collections | 1 | 4,096 |
| collection_metadata | 1 | 4,096 |
| acquire_write | 1 | 4,096 |
| Free pages | 107,253 | 439,308,288 |
| Unattributed file overhead | 1 | 4,096 |
| **File total** | **16,308,479** | **66,799,529,984** |


The primary store held 12,612 sdk_sessions (9,056 Claude, 3,556 Codex), 25,582
user_prompts, 6,799 observations, 23 summaries, and 67,627 queued messages.
Session statuses were active 570, completed 4,627, failed 7,415.
Observation timestamps span April 19–November 14; summaries April 20–October 29.
`relevance_count` is zero on every observation, but its installed bundle only
initializes the field, so zero must **not** be interpreted as proof of no reads.

**Observer self-capture dominates the primary database.** These are byte lengths
of text fields, separate from physical table sizes:

| Field/category | Rows | UTF-8 payload bytes |
|---|---:|---:|
| sdk_sessions.user_prompt, prefix “You are a Claude-Mem” | 5,513 | 12,168,559,607 |
| sdk_sessions.user_prompt, observed-session tag, excluding that prefix | 3,074 | 128,820,505 |
| sdk_sessions.user_prompt, other | 4,025 | 1,143,426 |
| user_prompts.prompt_text, same observer prefix | 5,514 | 12,168,571,897 |
| user_prompts.prompt_text, observed-session tag, excluding prefix | 11,554 | 342,491,878 |
| user_prompts.prompt_text, other | 8,514 | 22,957,070 |

There are 8,592 sessions filed under project `observer-sessions`.
U/src/services/worker/SDKAgent.ts:129–145 launches the observer with
`cwd: OBSERVER_SESSIONS_DIR`, explicitly isolating it from resume lists.
The normal session hooks still persist its observer prompts:
U/src/cli/handlers/session-init.ts checks configured cwd exclusions,
currently empty; U/src/services/sqlite/sessions/create.ts:88–94 stores
`user_prompt` when creating sessions. ChromaSync.ts:417–431 then copies each
prompt as `id: prompt_<id>, document: prompt.prompt_text`.
The measured prefixes and project counts support self-capture; no claim is made
that every large prompt is an identical duplicate or that the full causal history
has been reconstructed. A single stored prompt reaches 9,306,101 bytes.

**Do not delete observer sessions wholesale:** 3,243 observations and 22 of the
23 summaries reference memory_session_ids belonging to that project. Cascading
deletion would destroy material the useful context path can read.

Failed queue messages account for 430,879,909 input/response bytes over 67,470
rows; 157 pending rows contain 1,040,108 such bytes. Keeping retryable work is
different from retaining failures indefinitely. Source PendingMessageStore.ts
deletes successful messages at `confirmProcessed`, and offers manual
`clearFailed()` and `clearAll()`; it defines no age retention.
The installed API exposes DELETE `/api/pending-queue/failed` and
`/api/pending-queue/all`. The latter would discard pending work and is not
recommended.

#### Retention and WAL findings

- Session and prompt retention: none found in the inspected installed settings
  or implementation. DatabaseManager.ts explicitly comments:
  `cleanupOrphanedSessions - violates "EVERYTHING SHOULD SAVE ALWAYS"`.
- Chroma has `embeddings_queue_config = {"automatically_purge":true,...}`,
  only five queued operations and no maintenance_log rows. Its ingestion queue is
  bounded/purged; this is **not** retention of indexed documents. The full
  collection remains retained.
- Logs rotate by date but the logger appends and has no expiry policy. There are
  157 dated files, April 17–November 18, 279,613,979 logical bytes initially.
- The installed user systemd watchdog timer runs every 15 minutes; watchdog.py
  reaps leaked worker processes. It has no data-retention or checkpoint policy.
  No matching storage-maintenance cron was found in the inspected user crontab
  and systemd service/timer files. Other uninspected scheduler scopes are unknown.
- SQLite `auto_vacuum=0` on both main files. Primary freelist is zero;
  Chroma has 107,253 free pages = **439,308,288 bytes**. A vacuum without pruning
  has little to reclaim: roughly 0.44 GB in Chroma, not 66 GB.
- Worker constructors enable WAL and NORMAL synchronous mode. No explicit
  `wal_checkpoint`, `wal_autocheckpoint` or VACUUM policy appears in the
  installed worker bundle. A fresh audit connection's default 1,000-page
  autocheckpoint value is not evidence of the writer's setting. Immutable
  connections reporting journal_mode=delete are likewise not the live mode.
- WAL length is **2,092,733,432 bytes**, room for 507,945 4,120-byte frames.
  Reading the WAL/SHM headers, without touching SQLite locks, found an active
  wal-index `mxFrame=828`, `nBackfill=0`, database-page count 6,757,434.
  That is only about 3.41 MB of frames in the current generation; the 2 GB file
  is mostly previously allocated capacity. These header reads are non-atomic
  and advisory, but they refute an inference of 2 GB of active unchecked work.
  The WAL header sequence was 10,122, consistent with repeated recycling.
  **A large WAL alone does not prove that checkpoints never run.**
- /proc fd inspection confirmed bun PID 27714 holding the DB and WAL open
  (several connections). Read-only audit Python processes held only the DB.
  No process was stopped.

### C. Ranked interventions and owner runbook

| Rank | Proposal | Reclaim / cost | What changes or breaks |
|---|---|---|---|
| 1 | Exclude the observer cwd before hooks persist it; add an explicit internal-session guard upstream, with bounded payloads | No immediate disk reclaim; stops the measured source of about 24.34 GB in duplicated prompt fields and future FTS/vector multiplication | Observer-generated internal prompts no longer appear as user memories; ordinary session observations must continue |
| 2 | On an offline backup copy, null the verified observer-prefix sdk prompt payloads and delete matching observer-prefix user_prompt rows, preserving all session IDs, observations and summaries; rebuild affected FTS and compact the copy | Removes exactly 24,337,131,504 measured raw text bytes, plus associated FTS/index pages; final filesystem reclaim requires replacing the live DB after validation | Old observer boilerplate is no longer searchable; no cascade deletion; orphaned vector prompt IDs must not remain queryable |
| 3 | Disable Chroma for a two-week trial; archive its entire directory on a separate verified volume, then remove the local copy; optionally rebuild an observation-only, bounded collection later | Up to 66,914,516,992 allocated directory bytes after external archival/removal; copying to the same disk reclaims zero | Current unified query-text search can return no results without Chroma, despite “SQLite-only” log wording. Date/filter recall, timeline/ID hydration, automatic context and local code tools remain separate paths |
| 4 | Expire failed queue payloads after seven days, logs after 30, ordinary raw prompts after 90; keep pending/processing intact and export durable observations/summaries before age pruning | Failed payload ceiling here about 431 MB; logs older than 30 days here 251,640,498 bytes across 135 files; ordinary prompts are small compared with self-capture. Costs archival and a recurring policy | Historical raw tool replay outside the window requires the archive; proposals cannot use deleted payloads as primary evidence |
| 5 | One owner-controlled WAL TRUNCATE checkpoint in a maintenance window, then monitor active frames and busy results | Up to 2,092,733,432 allocated logical bytes now; file can grow again | Requires writer/client coordination; never remove WAL manually and never loop through a busy checkpoint |
| 6 | Discontinue claude-mem only if a measured trial shows no task benefit | Up to the entire local store after verified external archival; stops ingestion expense | Loses automatic historical context, mem-search and plugin-provided code tools; does not repair Headroom; remove stale watcher-written context blocks deliberately |

Rank 3 is a trial, not a claim of safe semantic-search parity:
U/src/services/worker/SearchManager.ts:257–266 explicitly says
`ChromaDB not initialized - semantic search unavailable` and sets observations,
sessions and prompts to empty for a query-text request. Filter-only requests use
SQLite. The acceptance tests below must exercise the actual route before any
permanent Chroma removal. Do not enable a fresh default collection and backfill
all original user prompts, which would recreate the multiplication.

Proposed bounds for later implementation: reject/externally reference raw
individual payloads above 32 KiB, retain no more than 1 GB of raw prompts,
10,000 failed queue items or 1 GB of failed payloads, and 30 days of logs.
For pending/processing saturation, pause ingestion loudly rather than discard
work. Initially keep the existing 6,799 observations and 23 summaries; introduce
a 365-day reviewed export policy and a 250 MB warning threshold for durable
memory only after useful retrieval is measured. These are chosen limits,
not already-configured behavior.

#### Exact owner commands — NOT RUN

The owner must schedule a maintenance window, close clients that can respawn
hooks, pause transcript ingestion, and verify no writer remains before changing
database files. The investigation does not grant authorization to execute any
block below. Paths are this machine's verified paths; the owner chooses
`CLAUDE_MEM_ARCHIVE_ROOT` on a separate volume with room for at least the full
96.97 GB archive plus work copies. Uncompressed copies require substantial space.

1. Back up settings externally, apply the observer exclusion and Chroma trial
   configuration, and stop the worker after all clients are quiescent:

```bash
set -euo pipefail
: "${CLAUDE_MEM_ARCHIVE_ROOT:?Set an existing backup directory on a separate volume}"
test -d "$CLAUDE_MEM_ARCHIVE_ROOT"
cp -p <HOME>/.claude-mem/settings.json "$CLAUDE_MEM_ARCHIVE_ROOT/settings.before.json"
python3 - <<'PY'
import json
from pathlib import Path
p = Path('<HOME>/.claude-mem/settings.json')
d = json.loads(p.read_text())
patterns = [x.strip() for x in d.get('CLAUDE_MEM_EXCLUDED_PROJECTS', '').split(',') if x.strip()]
observer = '<HOME>/.claude-mem/observer-sessions'
if observer not in patterns:
    patterns.append(observer)
d['CLAUDE_MEM_EXCLUDED_PROJECTS'] = ','.join(patterns)
d['CLAUDE_MEM_CHROMA_ENABLED'] = 'false'
d['CLAUDE_MEM_TRANSCRIPTS_ENABLED'] = 'false'  # temporary maintenance pause
p.write_text(json.dumps(d, indent=2) + '\n')
PY
<HOME>/.bun/bin/bun <HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs stop
lsof -nP <HOME>/.claude-mem/claude-mem.db <HOME>/.claude-mem/claude-mem.db-wal
```

The installed stop command exists, but its success message is not sufficient:
any remaining writer or respawning client blocks the next step. The watchdog
normally reaps processes rather than starting workers, but its scheduled runs
must not interfere with the maintenance window. No service is stopped by this spec.

2. With no clients or writers, archive the whole store and verify the archive
   before considering removal. This copy includes WAL; do not copy only a live DB.

```bash
set -euo pipefail
test ! -e "$CLAUDE_MEM_ARCHIVE_ROOT/store"
cp -a <HOME>/.claude-mem "$CLAUDE_MEM_ARCHIVE_ROOT/store"
diff -qr <HOME>/.claude-mem "$CLAUDE_MEM_ARCHIVE_ROOT/store"
```

Build the working copy with SQLite backup API so committed WAL frames are
included. Never remove a WAL to force a main-file-only copy to appear current:

```python
import os, sqlite3
from pathlib import Path
source = sqlite3.connect('file:<HOME>/.claude-mem/claude-mem.db?mode=ro', uri=True)
work_path = Path(os.environ['CLAUDE_MEM_ARCHIVE_ROOT']) / 'work.db'
assert not work_path.exists()
target = sqlite3.connect(work_path)
source.backup(target)
target.close()
source.close()
```

The investigator did not use this live read-only mode because immutable reads
avoid SHM participation. The owner uses it only in the later maintenance window.

3. Sanitize and compact **the working copy only**, preserving primary/foreign
   keys and all durable rows; compare the exported IDs and content before/after:

```python
import os, sqlite3
from pathlib import Path
root = Path(os.environ['CLAUDE_MEM_ARCHIVE_ROOT'])
c = sqlite3.connect(root / 'work.db')
c.execute('PRAGMA foreign_keys=ON')
c.execute('PRAGMA busy_timeout=5000')
before_obs = c.execute('SELECT * FROM observations ORDER BY id').fetchall()
before_summaries = c.execute('SELECT * FROM session_summaries ORDER BY id').fetchall()
before_sessions = c.execute('SELECT id,content_session_id,memory_session_id FROM sdk_sessions ORDER BY id').fetchall()
with c:
    c.execute("UPDATE sdk_sessions SET user_prompt=NULL WHERE user_prompt LIKE 'You are a Claude-Mem%'")
    c.execute("DELETE FROM user_prompts WHERE prompt_text LIKE 'You are a Claude-Mem%'")
    c.execute("DELETE FROM pending_messages WHERE status='failed' AND created_at_epoch < (unixepoch('now')-7*86400)*1000")
    c.execute("DELETE FROM user_prompts WHERE created_at_epoch < (unixepoch('now')-90*86400)*1000")
    c.execute("UPDATE sdk_sessions SET user_prompt=NULL WHERE started_at_epoch < (unixepoch('now')-90*86400)*1000")
    c.execute("INSERT INTO user_prompts_fts(user_prompts_fts) VALUES('rebuild')")
assert c.execute('SELECT * FROM observations ORDER BY id').fetchall() == before_obs
assert c.execute('SELECT * FROM session_summaries ORDER BY id').fetchall() == before_summaries
assert c.execute('SELECT id,content_session_id,memory_session_id FROM sdk_sessions ORDER BY id').fetchall() == before_sessions
assert not c.execute('PRAGMA foreign_key_check').fetchall()
assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
compact = root / 'compact.db'
assert not compact.exists()
c.execute('VACUUM INTO ?', (str(compact),))
c.close()
```

This is a concrete candidate migration, not an already-tested maintenance tool.
Test on a disposable fixture first, then the copy; record row counts, FTS search
results and exact compacted bytes. Fail closed on missing triggers or schema
drift. Keep the original archive and do not reuse an old working-copy filename.

4. A standalone WAL trim, if selected, is one bounded owner action while clients
   are paused; the return tuple must show no busy result:

```python
import sqlite3
c = sqlite3.connect('<HOME>/.claude-mem/claude-mem.db', timeout=5)
c.execute('PRAGMA busy_timeout=5000')
result = c.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
c.close()
print(result)
if result[0] != 0:
    raise SystemExit('checkpoint busy; leave WAL intact and diagnose readers')
```

5. Installing the validated compact DB and reclaiming the disabled vector store
   is a separate explicit owner action after backup verification and an empty
   holder check. Do not issue these commands against a live worker:

```bash
set -euo pipefail
test ! -e <HOME>/.claude-mem/claude-mem.db-wal
test ! -e <HOME>/.claude-mem/claude-mem.db-shm
cp -p "$CLAUDE_MEM_ARCHIVE_ROOT/compact.db" <HOME>/.claude-mem/claude-mem.db.new
mv <HOME>/.claude-mem/claude-mem.db.new <HOME>/.claude-mem/claude-mem.db
diff -qr <HOME>/.claude-mem/chroma "$CLAUDE_MEM_ARCHIVE_ROOT/store/chroma"
rm -r -- <HOME>/.claude-mem/chroma
```

If WAL/SHM sidecars remain after shutdown, use the bounded checkpoint in step 4
and verify all connections close; a failed sidecar test stops installation.
Never delete sidecars manually.

These destructive commands are shown solely to make the review concrete; neither
has been run. Retain `CLAUDE_MEM_CHROMA_ENABLED=false` until a bounded replacement
has been built, otherwise startup can backfill unbounded history again.
Restore transcript watching deliberately after verification, keeping the observer
exclusion. Restart with the installed worker's `start` command, open one client,
and exercise startup context, filter-only search, timeline and selected-ID fetch.
A rollback requires clients paused again and restoring the **complete matching
DB/WAL/SHM set** from the verified archive, not mixing old DB with a new WAL.

6. Log expiry is an optional owner action only after the verified full archive.
This script selects dated logs, compares each with its archived copy, and removes
only logs older than 30 calendar days; it does not touch the active daily file:

```python
import datetime, hashlib, os
from pathlib import Path
live = Path('<HOME>/.claude-mem/logs')
archive = Path(os.environ['CLAUDE_MEM_ARCHIVE_ROOT']) / 'store/logs'
cutoff = datetime.date.today() - datetime.timedelta(days=30)
for path in sorted(live.glob('claude-mem-????-??-??.log')):
    day = datetime.date.fromisoformat(path.stem.removeprefix('claude-mem-'))
    if day >= cutoff:
        continue
    saved = archive / path.name
    assert saved.is_file()
    assert hashlib.file_digest(path.open('rb'), 'sha256').digest() == hashlib.file_digest(saved.open('rb'), 'sha256').digest()
    path.unlink()
```

If the owner chooses discontinuation instead: `claude plugin disable
claude-mem@thedotmack`, stop the worker as above, turn transcript watching off,
archive and verify the whole directory before any local removal. Keep Headroom
configuration unchanged. Review only the watcher-generated AGENTS.md context
blocks; never overwrite project instructions wholesale.

## Inputs

- Repository architecture, read-shunt baseline, resilience guidance and existing
  producer contracts; the canonical task vocabulary and Finding Model.
- Installed plugin registration/settings, exact installed bundle and source
  revision; structural Claude transcript hook and tool-use events.
- Immutable read-only SQLite schema, dbstat, row aggregates, collection IDs and
  WAL/SHM headers; file metadata and directory allocation.
- Owner-selected retention windows and archive destination; an explicit later
  authorization for any maintenance action. This PR supplies no such execution.
- For the proposed routine: a bounded completed-session interval, repository SHA,
  transcript provenance, and prior sweep records/task evidence for deduplication.

## Outputs

- This single evidence-backed spec and one PR carrying it, with Refs linkage only.
- Exact file/object/collection accounting, measured consumption and limits of the
  measurement, a ranked owner runbook, and the proposed routine contract.
- No registry issue, cleanup, changed setting, rebuilt vector, new scheduler or
  product-code implementation in this investigation.

## Edge Cases

- A writer is live: immutable main-file reads are permitted, but do not claim
  atomic freshness or take a checksum equality as a safety test while it writes.
  A changing mtime from the writer does not imply the investigator wrote data.
- A large WAL may be recycled capacity; inspect active generation before diagnosing
  checkpoint starvation. A busy checkpoint is a stop, not a retry/delete loop.
- Observer sessions own useful rows: preserve session keys and durable rows.
- Vector and SQL retention differ: retained vector IDs must hydrate existing SQL
  rows; partial cross-store pruning is not accepted.
- Disabled Chroma does not guarantee text-search fallback. Fail the trial if a
  required query route breaks without an explicitly accepted cost.
- Compression markers are not original tool output. Reissue a bounded read or
  consult the original transcript; do not retry expired retrieval indefinitely.
- Logs contain commands mentioning URLs and tool names. Count parsed event
  fields, not substrings in command payloads or copied tool definitions.
- Transcript API-request blobs can repeat a whole conversation. Count canonical
  hook/tool records once, not every copied request payload.
- Secrets and user text remain local. Publish aggregates, code/config excerpts
  without credentials, hashes and minimal redacted evidence only.
- Missing/rotated/malformed transcripts are coverage gaps; no numeric zero that
  hides missing coverage. Open sessions are skipped until a settled boundary.
- A same-day producer rerun and duplicate finding follow the existing producer
  spine and registry's derived-ID rules, rather than opening a second task/PR.

## Decisions

| ID | State | Decision | Reason |
|---|---|---|---|
| D1 | settled by owner | Investigate and propose only; one spec, one PR, no issues or live-store mutation | Live user data has an attached writer |
| D2 | recommended | Preserve useful SQL startup recall initially; exclude observer ingestion and bound raw retention | Automatic consumption is proved; dominant bytes are internal prompt capture |
| D3 | recommended | Preserve all session keys, observations and summaries during first reclamation | 3,243 observations and 22 summaries link to observer-session rows |
| D4 | recommended | Two-week Chroma-off trial with explicit query-text-search cost, then bounded observation-only rebuild if justified | Only one logged historical search; 66.8 GB mainly repeats text, while HNSW is small |
| D5 | recommended | Seven-day failed queue, 30-day logs, 90-day ordinary prompts; review/export durable memory before 365-day pruning | Finite growth without silently dropping pending work |
| D6 | settled by evidence | Do not equate Headroom recovery with claude-mem consumption | Different configuration, tool names and retrieval implementation |
| D7 | recommended | New producer lens named workflow, weekly and initially manual | Extends the existing verified-finding producer architecture |
| D8 | settled by scope | claude-mem is an optional candidate locator for workflow analysis, never the sole raw-evidence source | Summaries/vector history lose per-call timing, usage and complete causal order |
| D9 | open for owner review | Retention constants, archive destination, acceptance of temporary query-text-search loss and permanent Chroma retirement | Implementation and maintenance require the owner's decision after this PR |
| D10 | open for owner review | Enable scheduled workflow producer only after a manual run and reviewed finding quality | No new routine or tracker write is authorized here |

## Acceptance Criteria

These distinguish completed investigation evidence from future implementation gates.
The latter are **not claimed passed** by writing this proposal.

| AC | Required evidence | State in this proposal |
|---|---|---|
| AC1 | Trace installed registration → hook/tool → query → context, with concrete quotes | Recorded in A |
| AC2 | Count actual context injections and historical search calls; name token estimator and coverage limits | Recorded in A |
| AC3 | Exact bytes for every directory, SQLite storage object, Chroma collection and segment file; corpora inventory | Recorded in B |
| AC4 | Inspect retention and active WAL state without live write, checkpoint, vacuum or process stop | Recorded in B and safety receipt |
| AC5 | Ranked alternatives state reclaim, cost, failure modes and exact unexecuted owner commands | Recorded in C |
| AC6 | Existing read-shunt and producer architecture reflected in proposal; no duplicate transcript ingestion/index | Recorded in A and routine design |
| AC7 | Disposable-fixture migration preserves keys/observations/summaries, FTS and foreign-key integrity, retries idempotently | Future implementation gate |
| AC8 | Offline real-copy rehearsal reports final exact reclaimed bytes and rollback proof; no live cleanup on this PR | Future owner gate |
| AC9 | Chroma trial explicitly exercises query-text and filter-only routes, startup context, file-context, timeline and ID fetch | Future owner gate |
| AC10 | Producer dry run cites canonical source events, verifies recurrence or reproduction, and files nothing under review threshold | Future implementation gate |
| AC11 | Before/after path inventory plus command ledger demonstrates investigation used no mutating store operations | Safety receipt below |
| AC12 | Only this spec changes; one PR, Refs only, no registry issue, no helper agents | PR verification |

## Implementation Paths

This PR changes only `specs/claude-mem-retention.md`.
Later work requires a separate approved build plan; this is not a build prompt.

| Future surface | Responsibility |
|---|---|
| claude-mem upstream `src/cli/handlers/session-init.ts`, `observation.ts`, `file-context.ts`; `SDKAgent.ts` | Internal observer guard and exclusion behavior, verified against installed bundle |
| claude-mem upstream `src/services/sqlite/`, `src/services/sync/ChromaSync.ts` | Bounded retention, preserving relational keys and cross-store document IDs; reviewed offline migration |
| Owner `~/.claude-mem/settings.json` and maintenance runbook | Observer cwd exclusion, trial Chroma setting and finite retention; not repository defaults |
| `.agents/skills/sweep/SKILL.md`, new `references/lens-workflow.md` | Shared producer spine with workflow engine and evidence bar |
| `.agents/skills/task-registry/lanes/workflow.md`, routine_branch catalogue mirrors, routine config templates and tests | Register producer vocabulary before scheduling; do not merely add an unsupported name to a prompt |
| `.agents/skills/eval/scripts/read_transcript.py`, read-incidence/grade-read-shunt CLIs | Reuse existing Claude parser/metrics; add explicit Codex adapter only if approved, no duplicate store |
| `tasks/sweeps/<YYYY-MM-DD>-workflow.md` and registry via /task-registry | Future verified findings and coverage gaps; no files or issues created now |

## Proposed routine: workflow producer

**Name:** `workflow`; **lens:** agent workflow efficiency and reliability.
It belongs beside janitor (bugs), architect (design), and tidy (harness hygiene),
rather than a new transcript collector or a consumer that changes code.

**Cadence and scope:** weekly, first a manual review of seven days of completed
sessions, then an opt-in scheduled producer. Bound a run initially to 50 sessions,
20 minutes and a configured model/token budget; retain a cursor plus source digest
and report unexamined coverage when capped. Do not silently advance past unread
files. A new cursor is tiny producer bookkeeping, not re-ingestion of text.

**Inputs:** canonical transcript tool-use/results and model-usage/compact-boundary
events; repository SHA; existing read-incidence and read-shunt grader outputs;
handover/retry evidence; open backlog read through /task-registry for dedupe.
Include Codex only with a tested schema adapter and explicit coverage statement.
Orca's retained journal can locate the original session when necessary, but its
references do not establish equivalence to raw provider events.

**Engine:** reuse the existing parser to rank repeated denied calls, expired
retrieval loops, duplicated reads, forgotten handovers, repeated full suites,
observer-on-observer capture and excessive fixed context. Keep parent and
sub-agent accounting separate. Token savings require actual model usage and
context evidence, not bytes guessed from a log line. Do not infer task failure
from long duration or unfinished live sessions.

**Evidence bar:** shared /sweep doctor → backlog → engine → verify → file →
session-record → wrap-up. Each candidate needs a verbatim minimal file:line or
session/event anchor, source SHA/digest, observed/expected behavior, and the four
Finding Model axes. Confidence at least 75, no NITPICK, no confidence boost for
single-agent agreement. For a repeat-pattern optimization, show at least two
distinct completed sessions and reproduce the mechanism against current source;
a correctness defect can instead meet janitor's executed failing-reproduction
bar. For a claimed cost improvement, use /eval Mode C's blinded paired comparison,
quality checks and measured model usage before calling savings proven.
A useful hypothesis below that bar stays Unverified.

**Filed output:** after separate authorization, use /task-registry only, stable
derived IDs and existing-finding dedupe. Reproduced reliability defects are
`bug`; proven waste is `task` + `tech-debt`; a tradeoff needing an owner is
`decision`. Include reproduction, minimal sanitized transcript excerpt,
expected behavior, proposed fix, checkable acceptance criteria and
`discovered: sweep/workflow <date> @ <sha>`. Human-owned escalations remain
human-owned. The producer edits no product code, retains mandatory step rows and
coverage gaps, and opens a docs-only record PR with Refs for verified tasks.
Current registry refuses an unregistered producer; lane/catalogue/test changes
must precede enabling it. This investigation files **nothing**.

**Can it consume claude-mem instead of transcripts?** Partially. It can query
date/project-filtered SQL or use search → timeline → selected-ID hydration to
find candidate sessions. The data is genuinely queryable: observation IDs,
memory/content session IDs, project/platform, timestamps, narrative/facts and
queued tool names/JSON all exist. It does not need a second vector index.

It cannot prove per-call optimization claims from that store alone: only 6,799
summarized observations and 23 summaries survived versus 25,582 prompts;
processed tool queue entries are deleted, failed entries are biased, vectors
stopped updating in October, and raw per-call usage/parent linkage/compactions
are not retained as equivalent structured fields. The 67,470 failed queue items
are evidence of backlog, not a complete tool-call ledger. Use claude-mem as an
optional locator, then reopen the original transcript for proof with the existing
parser. That reuses existing ingestion without trusting a lossy secondary index
as the authority or creating another 91 GB store.

## Safety receipt and reproduction ledger

Inspection ended 2026-11-18T18:07:10.391231+00:00. Both inventories contain 181 entries;
no path was created, deleted, moved or replaced in the store. The primary DB
and Chroma DB retained the same length, inode and mtime throughout this audit.

| Database | Before/after bytes | Before/after inode | Before/after mtime_ns |
|---|---:|---:|---:|
| claude-mem.db | 27,677,945,856 | 4198918 | 1795023605007863354 |
| chroma/chroma.sqlite3 | 66,799,529,984 | 4354277 | 1791550483157484276 |

Existing writers changed six paths; none is evidence of an investigator write.
The audit never opened these writable or called the plugin to request data.

| Path | Before bytes → after bytes | Before mtime_ns → after mtime_ns |
|---|---:|---:|
| claude-mem.db-shm | 32,768 → 32,768 | 1795024300162860967 → 1795024395638427577 |
| claude-mem.db-wal | 2,092,733,432 → 2,092,733,432 | 1795024300162860967 → 1795024395638427577 |
| logs/claude-mem-2026-11-13.log | 6,458,168 → 6,466,513 | 1795024307207902016 → 1795025214422545141 |
| logs/claude-mem-2026-11-18.log | 322,360 → 322,709 | 1795024300160860956 → 1795024395657427692 |
| transcript-watch-state.json | 481,600 → 481,602 | 1795024312145930864 → 1795025229955765001 |
| watchdog.log | 751,878 → 751,964 | 1795023406641703114 → 1795024362783230171 |

Before manifest SHA-256: `d49e4abb8a93d955cd4e6d0fdecc749877f878ff5c33d1cdbb57b8571568e686`.
After manifest SHA-256: `820da30d68883bc7820cfe5e321106f2d6329c884bbb30c656ad59fcf36a25a9`.
The full local metadata manifests are `/tmp/claude-mem-audit-20261118/before.json`
and `after.json`; the command below reconstructs their shape. Hashes identify
the metadata manifests, **not checksums of a changing live database**.
The investigator modified nothing under `~/.claude-mem`; all SQLite opens in
the investigation used `mode=ro&immutable=1`, and the live bun process was left running.

The appendix records exact investigation shell commands, including failed path
probes and bounded output views. Python audit queries use SQLite immutable URIs;
grouping/dbstat may create temporary files outside the store. Temporary artifacts
were written only beneath `/tmp/claude-mem-audit-20261118` (and SQLite's temporary
area), while repository output is only this spec. No plugin hook/CLI was invoked
to query data: those handlers may log or open writable DB connections. In
particular, none of the maintenance examples above was executed.

### Repository validation

Required section checks, Bash syntax checks and Python AST parsing passed for
all embedded examples, without running maintenance code. The affected-test
selector returned `affected: none` for this spec-only diff. The staged diff
passed `git diff --cached --check`; no runtime behavior was changed and no
runtime/e2e or migration result is claimed. No helper reviewer was dispatched
because the owner required this investigation to be performed by this worker.

### Exact inspection commands

Commands retain the original structure with home prefixes replaced by `<HOME>`,
including path-probe failures and repeated reads; run them with `<HOME>` expanded. Initial skill reads ran in the dispatched worktree; repository investigation
commands used the new audit worktree. Some commands write **only audit artifacts**
under /tmp; none writes the store. Large results were consumed in bounded views.
The git fetch and Orca worktree creation changed only checkout metadata:

```bash
git -C <HOME>/jplugin-agentic-development fetch origin master
orca worktree create --name claude-mem-retention-audit --no-parent --base-branch origin/master --json
```

<details><summary>Inspection 1</summary>

```bash
cat <HOME>/.agents/skills/orchestration/SKILL.md
```

</details>

<details><summary>Inspection 2</summary>

```bash
cat <HOME>/.agents/skills/orca-cli/SKILL.md
```

</details>

<details><summary>Inspection 3</summary>

```bash
cat .agents/skills/memory-maintain/SKILL.md; cat tasks/todo.md
```

</details>

<details><summary>Inspection 4</summary>

```bash
head -80 <HOME>/.agents/skills/orchestration/SKILL.md
```

</details>

<details><summary>Inspection 5</summary>

```bash
head -75 <HOME>/.agents/skills/orca-cli/SKILL.md; printenv ORCA_CLI_COMMAND ORCA_DEV_REPO_ROOT; command -v orca; head -100 .agents/skills/memory-maintain/SKILL.md
```

</details>

<details><summary>Inspection 6</summary>

```bash
orca skills get orchestration
```

</details>

<details><summary>Inspection 7</summary>

```bash
orca skills get orca-cli
```

</details>

<details><summary>Inspection 8</summary>

```bash
git -C <HOME>/jplugin-agentic-development status --short; git -C <HOME>/jplugin-agentic-development remote -v
```

</details>

<details><summary>Inspection 9</summary>

```bash
mkdir -p /tmp/claude-mem-audit-20261118; wc -l specs/read-shunt-baseline.md .agents/skills/build/references/subagent-resilience.md .agents/skills/sweep/SKILL.md .agents/skills/wrap-up-session/references/routines.md; sed -n '1,180p' .agents/skills/build/references/subagent-resilience.md; rg -n -C 4 'claude-mem|Decision|Result|baseline|compaction' specs/read-shunt-baseline.md; sed -n '460,480p' README.md
```

</details>

<details><summary>Inspection 10</summary>

```bash
test ! -e /tmp/claude-mem-audit-20261118/transcripts.json || python3 -c 'import json; d=json.load(open("/tmp/claude-mem-audit-20261118/transcripts.json")); print({k:v for k,v in d.items() if k not in ["injections","examples"]}); print(d["injections"][:6]); print(d["examples"][:3])'
```

</details>

<details><summary>Inspection 11</summary>

```bash
wc -l specs/claude-mem-retention.md; git status --short; df -B1 /tmp
```

</details>

<details><summary>Inspection 12</summary>

```bash
cat /tmp/claude-mem-audit-20261118/content-stats.json | head -50; git diff --check; bash tests/affected.sh --run origin/master
```

</details>

<details><summary>Inspection 13</summary>

```bash
cat specs/read-shunt.md specs/read-shunt-baseline.md .agents/skills/build/references/subagent-resilience.md
```

</details>

<details><summary>Inspection 14</summary>

```bash
cat .agents/skills/sweep/SKILL.md .agents/skills/wrap-up-session/references/routines.md
```

</details>

<details><summary>Inspection 15</summary>

```bash
rg -n 'claude-mem|read.shunt' README.md; rg -n '^(problem_type|module|tags):.*(shunt|claude.mem|retriev|compaction)' tasks/solutions; head -55 tasks/todo.md; rg -n 'Sweep:|claude-mem|shunt|producer' tasks/concepts.md; rg -l '^needs_review: true' tasks/solutions/*/; rg -c '^(### \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]|## [0-9]{4}-[0-9]{2}-[0-9]{2})([[:space:]]|$)' tasks/history.md
```

</details>

<details><summary>Inspection 16</summary>

```bash
rg --files <HOME>/jplugin-agentic-development <HOME>/.agents <HOME>/.claude/plugins | rg '(subagent-resilience|claude-mem.*/(hooks.json|plugin.json|settings.json|package.json)|claude-mem.*/.*(context|search|retention|chroma|Database))' | head -90
```

</details>

<details><summary>Inspection 17</summary>

```bash
python3 - <<'PY'
import pathlib,json,os,datetime
p=pathlib.Path('<HOME>/.claude-mem')
def listing():
 return [{'path':str(x.relative_to(p)),'bytes':s.st_size,'blocks_bytes':s.st_blocks*512,'mtime_ns':s.st_mtime_ns,'inode':s.st_ino} for x in sorted(p.rglob('*')) if (s:=x.lstat())]
r=listing();pathlib.Path('/tmp/claude-mem-audit-20261118/before.json').write_text(json.dumps(r,indent=2));print('UTC',datetime.datetime.now(datetime.timezone.utc).isoformat());print('entries',len(r));print('top',[(x['path'],x['bytes']) for x in r if '/' not in x['path']]);print('allocated',sum(x['blocks_bytes'] for x in r))
s=json.loads(pathlib.Path('<HOME>/.claude/settings.json').read_text());print('enabledPlugins',s.get('enabledPlugins'));print('mem hooks',json.dumps({k:v for k,v in s.get('hooks',{}).items() if 'mem' in json.dumps(v)},indent=2));print('mcp names',s.get('mcpServers',{}).keys())
PY
```

</details>

<details><summary>Inspection 18</summary>

```bash
du -B1 --max-depth=2 <HOME>/.claude-mem; lsof <HOME>/.claude-mem/claude-mem.db <HOME>/.claude-mem/claude-mem.db-wal; df -B1 /tmp; git rev-parse HEAD
```

</details>

<details><summary>Inspection 19</summary>

```bash
cat <HOME>/.agents/skills/build/references/subagent-resilience.md
```

</details>

<details><summary>Inspection 20</summary>

```bash
cat .agents/skills/sweep/SKILL.md
```

</details>

<details><summary>Inspection 21</summary>

```bash
sed -n '1,210p' .agents/skills/wrap-up-session/references/routines.md
```

</details>

<details><summary>Inspection 22</summary>

```bash
cat <HOME>/.claude-mem/settings.json <HOME>/.claude-mem/transcript-watch.json; cat <HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/hooks/hooks.json; ls -la <HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6; df -B1 /tmp
```

</details>

<details><summary>Inspection 23</summary>

```bash
python3 - <<'PY'
import pathlib,json,sqlite3,collections
p=pathlib.Path('<HOME>/.claude-mem');a=collections.defaultdict(lambda:[0,0,0]);big=[]
for x in p.rglob('*'):
 s=x.lstat();k=x.relative_to(p).parts[0];a[k][0]+=s.st_size;a[k][1]+=s.st_blocks*512;a[k][2]+=1
 if x.is_file():big.append((s.st_size,str(x.relative_to(p))))
print(json.dumps(dict(a),indent=2));print('largest files',sorted(big,reverse=True)[:30]);
for f in [p/'claude-mem.db',p/'chroma/chroma.sqlite3']:
 if not f.exists():continue
 c=sqlite3.connect(f.as_uri()+'?mode=ro&immutable=1');print('DATABASE',str(f));print(c.execute('select type,name,tbl_name,sql from sqlite_master where type in (\'table\',\'index\')').fetchall());print('pragmas',[(k,c.execute('pragma '+k).fetchall()) for k in ['page_count','page_size','freelist_count','auto_vacuum','journal_mode','wal_autocheckpoint']]);c.close()
PY
```

</details>

<details><summary>Inspection 24</summary>

```bash
python3 - <<'PY'
import json,pathlib
p=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6')
print((p/'.mcp.json').read_text());print((p/'.claude-plugin/plugin.json').read_text());h=json.loads((p/'hooks/hooks.json').read_text());
for event,groups in h['hooks'].items():
 for g in groups:
  for x in g['hooks']:print(event,g.get('matcher'),x['command'])
print('scripts',*[x.name for x in (p/'scripts').iterdir()])
PY
```

</details>

<details><summary>Inspection 25</summary>

```bash
sed -n '210,325p' .agents/skills/wrap-up-session/references/routines.md; sed -n '1,110p' specs/read-shunt-baseline.md
```

</details>

<details><summary>Inspection 26</summary>

```bash
python3 - <<'PY'
import sqlite3,pathlib,json,time
out={}
for rel in ['claude-mem.db','chroma/chroma.sqlite3']:
 p=pathlib.Path('<HOME>/.claude-mem')/rel;c=sqlite3.connect(p.as_uri()+'?mode=ro&immutable=1');t=time.time()
 rows=c.execute('select name,count(*),sum(pgsize),sum(payload),sum(unused) from dbstat group by name order by sum(pgsize) desc').fetchall();r={'objects':rows,'page_count':c.execute('pragma page_count').fetchone()[0],'freelist':c.execute('pragma freelist_count').fetchone()[0],'page_size':4096};out[rel]=r
 print(rel,json.dumps(r), 'seconds',time.time()-t,flush=True)
pathlib.Path('/tmp/claude-mem-audit-20261118/dbstat.json').write_text(json.dumps(out,indent=2))
PY
```

</details>

<details><summary>Inspection 27</summary>

```bash
python3 - <<'PY'
import pathlib,re
p=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts')
for fn,patterns in {'worker-service.cjs':['/api/context/inject','SessionStart','wal_autocheckpoint','journal_mode','wal_checkpoint','VACUUM','DELETE FROM pending_messages','CLAUDE_MEM_CONTEXT_OBSERVATIONS','CLAUDE_MEM_SEMANTIC_INJECT','relevance_count','embeddings_queue','purge','retention','prune'],'mcp-server.cjs':['name:','/api/search','/api/timeline','get_observations']}.items():
 s=(p/fn).read_text();print('FILE',fn)
 for pat in patterns:
  matches=list(re.finditer(re.escape(pat),s));print('PATTERN',pat,'count',len(matches))
  for m in matches[:3]:print(s[max(0,m.start()-150):m.end()+300].replace('\n',' ')[:700])
PY
```

</details>

<details><summary>Inspection 28</summary>

```bash
cat <HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/skills/mem-search/SKILL.md; sed -n '1,180p' <HOME>/.claude-mem/watchdog.py; ls -l <HOME>/.claude-mem/chroma
```

</details>

<details><summary>Inspection 29</summary>

```bash
python3 - <<'PY'
import pathlib,re,json,collections
p=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts');s=(p/'worker-service.cjs').read_text()
for pat in ['async execute(t){if(!await or())','totalObservationCount','fullObservationCount','file-context','Chroma','chroma-mcp','markSessionComplete','clearFailed','/api/pending-queue','get_observations','/api/observations/batch','semantic']:
 m=list(re.finditer(re.escape(pat),s));print('TERM',pat,'occurrences',len(m))
 for a in m[:2]:print('offset',a.start(),s[max(0,a.start()-100):a.end()+900].replace('\n',' ')[:1100])
logs=pathlib.Path('<HOME>/.claude-mem/logs');print('recentlogs',[(x.name,x.stat().st_size) for x in sorted(logs.glob('*'))[-8:]])
PY
```

</details>

<details><summary>Inspection 30</summary>

```bash
python3 - <<'PY'
import pathlib,collections,re,json
root=pathlib.Path('<HOME>/.claude-mem/logs');counts=collections.Counter(); examples={};routes=collections.Counter();dates={};
for p in sorted(root.glob('*.log')):
 day=collections.Counter()
 for l in p.open(errors='replace'):
  for key in ['Context injected','Context generation','Context generated','Context fetch','/api/context/inject','/api/search','/api/timeline','/api/observations/batch','CHROMA','Chroma connection','Failed to connect','context/inject']:
   if key in l:counts[key]+=1;day[key]+=1;examples.setdefault(key,l[:900].rstrip())
  for m in re.findall(r'(?:GET|POST)\s+(/api/[^\s?]+)',l):routes[m]+=1
 if day:dates[p.name]=dict(day)
print('counts',dict(counts));print('routes',routes.most_common(30));print('examples',json.dumps(examples,indent=2));print('latestdays',list(dates.items())[-10:]);pathlib.Path('/tmp/claude-mem-audit-20261118/log-counts.json').write_text(json.dumps({'counts':dict(counts),'routes':dict(routes),'dates':dates,'examples':examples},indent=2))
PY
```

</details>

<details><summary>Inspection 31</summary>

```bash
python3 - <<'PY'
import pathlib,sqlite3,json
for f in ['claude-mem.db','chroma/chroma.sqlite3']:
 c=sqlite3.connect('file:<HOME>/.claude-mem/'+f+'?mode=ro&immutable=1');print('FILE',f)
 qs=(['select status,count(*) from pending_messages group by status','select status,count(*) from sdk_sessions group by status','select platform_source,count(*) from sdk_sessions group by platform_source','select count(*),min(created_at),max(created_at),sum(relevance_count),max(relevance_count) from observations','select count(*),min(created_at),max(created_at) from session_summaries'] if f=='claude-mem.db' else ['select id,name,dimension from collections','select * from segments','select count(*) from embeddings','select count(*) from embeddings_queue','select * from embeddings_queue_config','select * from maintenance_log','select * from max_seq_id'])
 for q in qs:
  try:print(q,c.execute(q).fetchall(),flush=True)
  except Exception as e:print(type(e).__name__,str(e),flush=True)
PY
```

</details>

<details><summary>Inspection 32</summary>

```bash
python3 - <<'PY'
import sqlite3,json
for f in ['claude-mem.db','chroma/chroma.sqlite3']:
 c=sqlite3.connect('file:<HOME>/.claude-mem/'+f+'?mode=ro&immutable=1');print('FILE',f)
 qs=(['select status,count(*) from pending_messages group by status','select status,count(*) from sdk_sessions group by status','select platform_source,count(*) from sdk_sessions group by platform_source','select count(*),min(created_at),max(created_at),sum(relevance_count),max(relevance_count) from observations','select count(*),min(created_at),max(created_at) from session_summaries'] if f=='claude-mem.db' else ['select id,name,dimension from collections','select * from segments','select count(*) from embeddings','select count(*) from embeddings_queue','select * from embeddings_queue_config','select * from maintenance_log','select * from max_seq_id'])
 for q in qs:
  try:print(q,c.execute(q).fetchall())
  except Exception as e:print(type(e).__name__,str(e))
PY
```

</details>

<details><summary>Inspection 33</summary>

```bash
python3 - <<'PY'
import pathlib,re
s=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs').read_text()
for pat in ['totalObservationCount','fullObservationCount','file-context','chroma-mcp','clearFailed','/api/pending-queue','/api/observations/batch']:
 a=s.find(pat);print('TERM',pat,'offset',a,s[max(0,a-70):a+900].replace('\n',' '))
PY
```

</details>

<details><summary>Inspection 34</summary>

```bash
python3 - <<'PY'
import pathlib,re,collections,json
p=pathlib.Path('<HOME>/.claude-mem/logs');tags=collections.Counter();cm=collections.Counter();examples={}
for f in p.glob('*.log'):
 for l in f.open(errors='replace'):
  m=re.match(r'^\[([^]]+)\] \[([^]]+)\] \[([^]]+)\] (.*)',l)
  if not m:continue
  tag=m[3].strip();tags[tag]+=1
  if tag.startswith(('CONTEXT','SEARCH','CHROMA','HOOK','MCP')):
   msg=m[4];k=(tag,re.sub(r'[0-9]+','#',msg.split('{')[0].split('|')[0])[:110]);cm[k]+=1;examples.setdefault(str(k),l[:550].rstrip())
print('tags',tags);print('selected',cm.most_common(40));
for k,n in cm.most_common(20):print(n,examples[str(k)])
PY
```

</details>

<details><summary>Inspection 35</summary>

```bash
python3 - <<'PY'
import pathlib,re,json
p=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs');s=p.read_text()
for pat,n in [('async execute(t){if(!await or())',1500),('lR=',1700),('async generateContext',1200),('totalObservationCount)',1000),('totalObservationCount,',900),('handleClearFailedQueue=',700),('handleSearch=',800)]:
 a=s.find(pat);print('TERM',pat,'offset',a,s[max(0,a-50):a+n].replace('\n',' '))
for f in ['<HOME>/.claude.json','<HOME>/.pi/agent/settings.json','<HOME>/.codex/config.toml']:
 p=pathlib.Path(f)
 if not p.exists():continue
 txt=p.read_text();print('CONFIG',f)
 if p.suffix=='.json':
  d=json.loads(txt);print('mcp',json.dumps(d.get('mcpServers',{}))[:1500]);print('mem-matching keys',[(k,str(v)[:1000]) for k,v in d.items() if 'claude-mem' in str(v)][:4])
 else:
  for l in txt.splitlines():
   if any(k in l.lower() for k in ['claude-mem','mcp','compress','ccr']):print(l[:250])
PY
```

</details>

<details><summary>Inspection 36</summary>

```bash
python3 - <<'PY'
import pathlib,re,collections
root=pathlib.Path('<HOME>/.claude-mem/logs');c=collections.Counter();samples={}
for p in root.glob('*.log'):
 for l in p.open(errors='replace'):
  if re.match(r'^\[[^]]+\] \[[^]]+\] \[HTTP\s*\]',l):
   x=l.split('] ',3)[-1].strip();k=re.sub(r'\d+','#',x.split('{')[0])[:180];c[k]+=1;samples.setdefault(k,l[:600].rstrip())
  elif re.match(r'^\[[^]]+\] \[[^]]+\] \[HOOK\s*\] → PostToolUse: mcp__',l) and ('mem' in l or 'headroom' in l):
   key=l.split('PostToolUse: ')[1].split('(')[0].strip();c[key]+=1
print(c.most_common(25));print('examples');
for k,n in c.most_common(8):print(n,samples.get(k,k))
PY
```

</details>

<details><summary>Inspection 37</summary>

```bash
rg -l 'mcp__.*(mcp-search|claude.mem).*(__search|__timeline|__get_observations)|<claude-mem-context>|Claude-Mem Context Loaded' <HOME>/.claude/projects --glob '*.jsonl' | head -30; rg -n 'ccr|headroom|compress' <HOME>/.claude/settings.json <HOME>/.codex/config.toml | cut -c 1-220; ls -lh /tmp/claude-mem-audit-20261118; ps -eo pid,etime,pcpu,comm | rg 'python3|bun' | head -15
```

</details>

<details><summary>Inspection 38</summary>

```bash
python3 - <<'PY'
import pathlib,re,collections,json
p=pathlib.Path('<HOME>/.claude/projects');files=list(p.rglob('*.jsonl'));print('transcripts',len(files),'bytes',sum(f.stat().st_size for f in files));
for f in sorted(files,key=lambda p:p.stat().st_mtime,reverse=True)[:8]:
 n=0
 for l in f.open(errors='replace'):
  if 'claude-mem-context' not in l and 'Claude-Mem' not in l:continue
  d=json.loads(l);m=d.get('message',{});print(f.name,d.get('type'),str(m.get('content',d.get('content','')))[:650]);n+=1
  if n>=2:break
PY
```

</details>

<details><summary>Inspection 39</summary>

```bash
python3 - <<'PY'
import pathlib,re,collections
s=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs').read_text()
for a,b in [(1063850,1065150),(1075500,1077400),(1093150,1094050)]:print('BYTES',a,b,s[a:b].replace('\n',' '))
for pat in ['contextInjected:','context/inject",','chroma_query_documents','chroma_delete_documents','CLAUDE_MEM_CHROMA_ENABLED','deleteObservations','deleteSession','readFileSync(t.transcript','transcript_path']:
 m=list(re.finditer(re.escape(pat),s));print('TERM',pat,'count',len(m))
 for a in m[:1]:print('offset',a.start(),s[max(0,a.start()-120):a.end()+550].replace('\n',' '))
PY
```

</details>

<details><summary>Inspection 40</summary>

```bash
python3 - <<'PY'
import pathlib,json,collections,re,hashlib
root=pathlib.Path('<HOME>/.claude/projects');tools=collections.Counter();sessions=collections.defaultdict(set);inject=[];types=collections.Counter();examples=[];malformed=0;total=0
for f in root.rglob('*.jsonl'):
 for line in f.open(errors='replace'):
  total+=1
  if not any(x in line for x in ['claude-mem','headroom_retrieve','hook_additional_context','hookAdditionalContext']):continue
  try:d=json.loads(line)
  except ValueError:malformed+=1;continue
  typ=d.get('type');types[typ]+=1
  if typ=='assistant':
   for b in d.get('message',{}).get('content',[]):
    if isinstance(b,dict) and b.get('type')=='tool_use' and any(x in b.get('name','') for x in ['claude-mem','headroom_retrieve']):
     n=b['name'];tools[n]+=1;sessions[n].add(str(f))
  if typ=='attachment':
   a=d.get('attachment',{});s=json.dumps(a)
   if 'claude-mem' in s.lower():
    inject.append({'file':str(f.relative_to(root)),'timestamp':d.get('timestamp'),'attachment_type':a.get('type'),'keys':list(a),'chars':len(s),'sample':s[:200]})
  if typ not in ['user','assistant','api-request-blob'] and len(examples)<8:examples.append((typ,str(d)[:450]))
out={'lines':total,'malformed_candidates':malformed,'types':dict(types),'tools':dict(tools),'tool_sessions':{k:len(v) for k,v in sessions.items()},'injections':inject,'examples':examples};pathlib.Path('/tmp/claude-mem-audit-20261118/transcripts.json').write_text(json.dumps(out,indent=2));print('lines',total,'types',types);print('tools',tools);print('tool_sessions',out['tool_sessions']);print('attachment_count',len(inject));print('attachments',inject[:6]);print('examples',examples[:4])
PY
```

</details>

<details><summary>Inspection 41</summary>

```bash
python3 - <<'PY'
import sqlite3,pathlib,json,time
out={}
for f,queries in {'claude-mem.db':[
"select count(*),sum(length(cast(user_prompt as blob))),max(length(cast(user_prompt as blob))) from sdk_sessions",
"select count(*),sum(length(cast(prompt_text as blob))),max(length(cast(prompt_text as blob))) from user_prompts",
"select case when user_prompt like 'You are a Claude-Mem%' then 'observer-system-prompt' when user_prompt like '%<observed_from_primary_session>%' then 'observed-session' else 'other' end,count(*),sum(length(cast(user_prompt as blob))),min(started_at),max(started_at) from sdk_sessions group by 1",
"select case when prompt_text like 'You are a Claude-Mem%' then 'observer-system-prompt' when prompt_text like '%<observed_from_primary_session>%' then 'observed-session' else 'other' end,count(*),sum(length(cast(prompt_text as blob))),min(created_at),max(created_at) from user_prompts group by 1",
"select status,count(*),sum(coalesce(length(cast(tool_input as blob)),0)+coalesce(length(cast(tool_response as blob)),0)),min(created_at_epoch),max(created_at_epoch) from pending_messages group by status",
"select platform_source,count(*),sum(length(cast(user_prompt as blob))) from sdk_sessions group by platform_source"
], 'chroma/chroma.sqlite3':[
"select case when embedding_id like 'obs_%' then 'observation' when embedding_id like 'prompt_%' then 'prompt' when embedding_id like 'summary_%' then 'summary' else 'other' end,count(*) from embeddings group by 1",
"select key,count(*),sum(length(cast(string_value as blob))),max(length(cast(string_value as blob))) from embedding_metadata group by key",
"select count(*),sum(length(cast(c0 as blob))),max(length(cast(c0 as blob))) from embedding_fulltext_search_content",
"select count(*),sum(length(vector)),sum(length(cast(metadata as blob))) from embeddings_queue"
]}.items():
 c=sqlite3.connect('file:<HOME>/.claude-mem/'+f+'?mode=ro&immutable=1');out[f]={}
 for q in queries:
  try:r=c.execute(q).fetchall();out[f][q]=r;print(f,q,json.dumps(r),flush=True)
  except Exception as e:print(type(e).__name__,str(e),flush=True)
pathlib.Path('/tmp/claude-mem-audit-20261118/content-stats.json').write_text(json.dumps(out,indent=2))
PY
```

</details>

<details><summary>Inspection 42</summary>

```bash
python3 - <<'PY'
import pathlib,json,collections,math,statistics,importlib.util
root=pathlib.Path('<HOME>/.claude/projects');events=[];counts=collections.Counter();sessions=set();bad=0
for f in root.rglob('*.jsonl'):
 for l in f.open(errors='replace'):
  if 'SessionStart' not in l or 'claude-mem' not in l:continue
  d=json.loads(l);a=d.get('attachment',{});
  if a.get('type')!='hook_success' or a.get('hookEvent')!='SessionStart' or 'hook claude-code context' not in a.get('command',''):continue
  try:o=json.loads(a.get('stdout',''));s=o.get('hookSpecificOutput',{}).get('additionalContext','')
  except ValueError:bad+=1;continue
  typ=a.get('hookName');counts[typ]+=1;sessions.add(str(f));events.append({'timestamp':d.get('timestamp'),'hook':typ,'chars':len(s),'bytes':len(s.encode()),'tokens_chars4':math.ceil(len(s)/4),'file':str(f.relative_to(root)),'prefix':s[:100]})
print('events',len(events),'sessions',len(sessions),'malformed',bad,'hooks',dict(counts));print('nonempty',sum(x['chars']>0 for x in events));
for key in ['chars','bytes','tokens_chars4']:
 ns=sorted(x[key] for x in events);print(key,'min',min(ns),'median',statistics.median(ns),'max',max(ns),'total',sum(ns))
print('sample',events[:2]);print('tiktoken',importlib.util.find_spec('tiktoken'));pathlib.Path('/tmp/claude-mem-audit-20261118/context-sizes.json').write_text(json.dumps(events,indent=2))
PY
```

</details>

<details><summary>Inspection 43</summary>

```bash
python3 - <<'PY'
import pathlib,re
for f in [pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs'),pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/mcp-server.cjs')]:
 s=f.read_text();print('FILE',f.name,'sha256',__import__('hashlib').sha256(f.read_bytes()).hexdigest())
 for pat in ['smart_outline','smart_unfold','smart_search','handleContextInject=','CLAUDE_MEM_CHROMA_ENABLED===','chromaEnabled','getChromaEnabled']:
  a=s.find(pat)
  if a>=0:print('OFFSET',a,s[max(0,a-90):a+650].replace('\n',' '))
print('headroom script',pathlib.Path('<HOME>/venv/bin/headroom').read_text()[:600])
PY
```

</details>

<details><summary>Inspection 44</summary>

```bash
rg --files <HOME>/.claude/plugins/marketplaces/thedotmack | rg '(Context|context|SessionStore|PendingMessage|ChromaSync|retention|prune|cleanup)' | head -55; rg -n 'headroom_retrieve|def retrieve|Content not found|storage_dir|cache_dir|sqlite|CCR' <HOME>/venv/lib/python3.12/site-packages/headroom/mcp* <HOME>/venv/lib/python3.13/site-packages/headroom/mcp* <HOME>/venv/lib/python3.14/site-packages/headroom/mcp* 2>/dev/null | head -35
```

</details>

<details><summary>Inspection 45</summary>

```bash
python3 - <<'PY'
import pathlib,struct,json,os
p=pathlib.Path('<HOME>/.claude-mem/claude-mem.db-wal');s=p.stat()
with p.open('rb') as f:h=f.read(32)
print('WAL size',s.st_size,'header',struct.unpack('>8I',h),'frames',(s.st_size-32)//(4096+24),'mtime',s.st_mtime_ns)
p=pathlib.Path('<HOME>/.claude-mem/claude-mem.db-shm')
with p.open('rb') as f:h=f.read(136)
print('SHM wal-index first header native',struct.unpack('=12I',h[:48]));print('checkpoint nBackfill native',struct.unpack('=I',h[96:100])[0]);print('readmarks',struct.unpack('=5I',h[100:120]))
for q in pathlib.Path('/proc').glob('[0-9]*/fd'):
 try:
  for fd in q.iterdir():
   try:t=os.readlink(fd)
   except OSError:continue
   if t in ['<HOME>/.claude-mem/claude-mem.db','<HOME>/.claude-mem/claude-mem.db-wal']:
    pid=q.parent.name;print('holder',pid,pathlib.Path('/proc',pid,'cmdline').read_bytes().replace(b'\0',b' ').decode()[:230],t)
 except (FileNotFoundError,PermissionError):continue
PY
```

</details>

<details><summary>Inspection 46</summary>

```bash
git -C <HOME>/.claude/plugins/marketplaces/thedotmack rev-parse HEAD; rg -n 'retention|VACUUM|wal_checkpoint|auto_vacuum|deleteOlder|prun|DELETE FROM|clearFailed|CLAUDE_MEM_CHROMA_ENABLED|observer|skip.*session|exclude' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sqlite/PendingMessageStore.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sqlite/SessionStore.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sync/ChromaSync.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/transcripts* <HOME>/.claude/plugins/marketplaces/thedotmack/src/cli/handlers/context.ts | head -90; rg -n 'headroom_retrieve|Content not found|def retrieve|storage_dir|cache_dir|sqlite' <HOME>/venv/lib/python3.12/site-packages/headroom/mcp -g '*.py' | head -40
```

</details>

<details><summary>Inspection 47</summary>

```bash
sed -n '1,150p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/cli/handlers/context.ts; sed -n '1,170p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/context/ContextBuilder.ts; rg -n 'watch|observer|exclude|AGENTS|context|skip' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/transcripts -g '*.ts' | head -60
```

</details>

<details><summary>Inspection 48</summary>

```bash
rg --files <HOME>/venv/lib/python3.12/site-packages/headroom | rg '(mcp|store|cache|ccr|retriev)' | head -45; sed -n '333,375p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/transcripts/processor.ts; sed -n '1,110p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/context/ObservationCompiler.ts; sed -n '455,488p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sqlite/PendingMessageStore.ts
```

</details>

<details><summary>Inspection 49</summary>

```bash
python3 - <<'PY'
import pathlib,collections,re,json
p=pathlib.Path('<HOME>/.claude-mem/logs');byday=collections.defaultdict(collections.Counter);errors=collections.Counter();samples=[]
for f in sorted(p.glob('*.log')):
 for l in f.open(errors='replace'):
  m=re.match(r'^\[([^]]+)\] \[([^]]+)\] \[HOOK\s*\] → PostToolUse: (mcp__[^\s(]+)',l)
  if m and ('claude-mem' in m[3] or 'headroom_retrieve' in m[3]):byday[f.name][m[3]]+=1
  if re.match(r'^\[[^]]+\] \[ERROR\] \[(?:CHROMA|CHROMA_MCP)\s*\]',l):
   k=l.split('] ',3)[-1].split('{')[0].strip();errors[k]+=1
   if len(samples)<5:samples.append(l[:450].strip())
print('consumption_byday',json.dumps(byday,indent=2));print('chroma_errors',errors.most_common(8));print('samples',samples)
PY
```

</details>

<details><summary>Inspection 50</summary>

```bash
rg -n -m 3 'You are a Claude-Mem|CLAUDE_MEM.*DISABLE|DISABLE.*HOOK|observer.*session|internal.*session|settingSources|settings.*hooks|CLAUDE_MEM_EXCLUDED_PROJECTS' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker <HOME>/.claude/plugins/marketplaces/thedotmack/src/cli/handlers <HOME>/.claude/plugins/marketplaces/thedotmack/src/sdk -g '*.ts' | head -65; rg -n 'headroom_retrieve|Content not found|def retrieve' <HOME>/venv/lib/python3.12/site-packages/headroom -g '*.py' | head -40
```

</details>

<details><summary>Inspection 51</summary>

```bash
python3 - <<'PY'
import pathlib,json,collections,statistics,math
import tiktoken
enc=tiktoken.get_encoding('cl100k_base');results=[]
for f in pathlib.Path('<HOME>/.claude/projects').rglob('*.jsonl'):
 for l in f.open(errors='replace'):
  if 'SessionStart' not in l or 'claude-mem' not in l:continue
  d=json.loads(l);a=d.get('attachment',{})
  if a.get('type')!='hook_success' or a.get('hookEvent')!='SessionStart' or 'hook claude-code context' not in a.get('command',''):continue
  try:s=json.loads(a.get('stdout','')).get('hookSpecificOutput',{}).get('additionalContext','')
  except ValueError:continue
  results.append(len(enc.encode(s,disallowed_special=())))
print('cl100k_base proxy only (not Claude billing tokenizer)',len(results),min(results),statistics.median(results),max(results),sum(results));pathlib.Path('/tmp/claude-mem-audit-20261118/token-proxy.json').write_text(json.dumps({'encoding':'cl100k_base','count':len(results),'min':min(results),'median':statistics.median(results),'max':max(results),'sum':sum(results)}))
PY
```

</details>

<details><summary>Inspection 52</summary>

```bash
sed -n '90,180p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/SDKAgent.ts; rg -n 'function isProjectExcluded|CLAUDE_MEM_CHROMA_ENABLED|settingSources|disable.*hook' <HOME>/.claude/plugins/marketplaces/thedotmack/src -g '*.ts' | head -40; sed -n '1,100p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/utils/project-exclusion.ts; rg -n 'Content not found|def.*retrieve|store|SQLite|sqlite|TTL' <HOME>/venv/lib/python3.12/site-packages/headroom/ccr/mcp_server.py | head -40; rg -n 'claude-mem' <HOME>/venv/lib/python3.12/site-packages/headroom/ccr -g '*.py'
```

</details>

<details><summary>Inspection 53</summary>

```bash
sed -n '1,60p' AGENTS.md; sed -n '1,90p' .agents/skills/verify-evidence/SKILL.md; sed -n '1,110p' .agents/skills/wrap-up-session/SKILL.md; rg -n -C 2 'doc|spec|skip' .agents/skills/wrap-up-session/SKILL.md | head -40; sed -n '1,70p' tests/affected.sh
```

</details>

<details><summary>Inspection 54</summary>

```bash
cat <HOME>/.claude/plugins/marketplaces/thedotmack/src/utils/project-filter.ts; sed -n '1,100p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/DatabaseManager.ts; sed -n '380,410p' <HOME>/venv/lib/python3.12/site-packages/headroom/ccr/mcp_server.py; sed -n '460,485p' <HOME>/venv/lib/python3.12/site-packages/headroom/ccr/mcp_server.py; rg -n 'sqlite|persist|storage|path|TTL|default_ttl|ttl=' <HOME>/venv/lib/python3.12/site-packages/headroom/cache/compression_store.py | head -35
```

</details>

<details><summary>Inspection 55</summary>

```bash
python3 - <<'PY'
import pathlib,re
s=pathlib.Path('<HOME>/.claude/plugins/cache/thedotmack/claude-mem/12.1.6/scripts/worker-service.cjs').read_text()
for pat in ['CLAUDE_MEM_CHROMA_ENABLED!=="false"','OBSERVER_SESSIONS_DIR','observer-sessions','case"stop"','case"restart"','async stop','handleContextInject=']:
 a=s.find(pat);print('TERM',pat,'OFFSET',a)
 if a>=0:print(s[max(0,a-120):a+600].replace('\n',' '))
print('AGENTS context files');
for p in [pathlib.Path('<HOME>/jplugin-agentic-development/AGENTS.md'),pathlib.Path('AGENTS.md')]:
 s=p.read_text();print(str(p),'claude-mem-context' in s,'claude-mem' in s)
PY
```

</details>

<details><summary>Inspection 56</summary>

```bash
python3 - <<'PY'
import json,collections,pathlib
r=json.load(open('/tmp/claude-mem-audit-20261118/before.json'));a=collections.defaultdict(lambda:[0,0,0]);dirs={'chroma','chroma/05a34ee5-938a-44b2-b3da-0ed7d6554349','corpora','logs','observer-sessions'}
for x in r:
 k=x['path'].split('/')[0];a[k][0]+=x['bytes'] if x['path'] not in dirs else 0;a[k][1]+=x['blocks_bytes'];a[k][2]+=int(x['path'] not in dirs)
print(json.dumps(dict(a),indent=2));print('sum',sum(v[0] for v in a.values()),sum(v[1] for v in a.values())+4096)
print('chroma files',[(x['path'],x['bytes']) for x in r if x['path'].startswith('chroma/') and x['path'] not in dirs]);print('logdates',min(x['path'] for x in r if x['path'].startswith('logs/')),max(x['path'] for x in r if x['path'].startswith('logs/')))
PY
```

</details>

<details><summary>Inspection 57</summary>

```bash
rg -n 'observer-sessions|You are a Claude-Mem|systemPrompt|user_prompt|prompt_text' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/SDKAgent.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/cli/handlers/session-init.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sqlite/sessions/*.ts | head -45; rg -n 'under_test|specs/|markdown|frontmatter' tests/test-doc-conventions.sh | head -25; cat .agents/references/finding-model.md | head -65; git config --get core.hooksPath
```

</details>

<details><summary>Inspection 58</summary>

```bash
python3 - <<'PY'
import pathlib,time
for pid in ['994558','1022455']:
 p=pathlib.Path('/proc')/pid
 if p.exists():print(pid,(p/'io').read_text(),(p/'stat').read_text().split(') ')[1].split()[:16])
print('time',__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat())
PY
```

</details>

<details><summary>Inspection 59</summary>

```bash
python3 - <<'PY'
import sqlite3
c=sqlite3.connect('file:<HOME>/.claude-mem/claude-mem.db?mode=ro&immutable=1')
for q in ["select project,count(*) from sdk_sessions group by project order by count(*) desc limit 8","select name,sql from sqlite_master where type='trigger'","select count(*) from observations where memory_session_id in (select memory_session_id from sdk_sessions where project='observer-sessions')","select count(*) from session_summaries where memory_session_id in (select memory_session_id from sdk_sessions where project='observer-sessions')"]:
 print(q,c.execute(q).fetchall())
PY
```

</details>

<details><summary>Inspection 60</summary>

```bash
sed -n '1,130p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sqlite/sessions/create.ts; rg -n 'syncUserPrompt|prompt_text|document:|collectionName|syncObservation' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sync/ChromaSync.ts | head -45; rg -n 'chromaSync|searchObservations|fallback|SQLite' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/search/*.ts <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/SearchManager.ts | head -35
```

</details>

<details><summary>Inspection 61</summary>

```bash
sed -n '245,275p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/SearchManager.ts; rg -n 'Chroma disabled|SQLite-only|chromaSync' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/worker/search/SearchOrchestrator.ts | head -20; sed -n '150,200p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/context/ContextBuilder.ts; sed -n '405,435p' <HOME>/.claude/plugins/marketplaces/thedotmack/src/services/sync/ChromaSync.ts; rg -n 'retention|unlink|rotate|max.*file|log.*day' <HOME>/.claude/plugins/marketplaces/thedotmack/src/utils/logger.ts; rg -n '^(##|###).*Producer|janitor.*architect|Read the backlog' .agents/skills/wrap-up-session/references/routines.md
```

</details>

<details><summary>Inspection 62</summary>

```bash
crontab -l 2>/dev/null | rg -n 'claude-mem|watchdog|vacuum|checkpoint'; rg -n 'claude-mem|watchdog|VACUUM|wal_checkpoint' <HOME>/.config/systemd/user --glob '*.service' --glob '*.timer' --glob '*.conf' 2>/dev/null | head -40; sed -n '343,409p' .agents/skills/wrap-up-session/references/routines.md; head -65 <HOME>/.claude/plugins/marketplaces/thedotmack/src/utils/logger.ts
```

</details>

<details><summary>Inspection 63</summary>

```bash
python3 - <<'PY'
import pathlib,json
for fn in ['dbstat.json','token-proxy.json','content-stats.json']:
 p=pathlib.Path('/tmp/claude-mem-audit-20261118')/fn;print(fn,p.exists(),p.stat().st_size if p.exists() else '')
PY
```

</details>

<details><summary>Inspection 64</summary>

```bash
python3 - <<'PY'
import pathlib,json,hashlib,collections,datetime
p=pathlib.Path('<HOME>/.claude-mem');r=[{'path':str(x.relative_to(p)),'bytes':s.st_size,'blocks_bytes':s.st_blocks*512,'mtime_ns':s.st_mtime_ns,'inode':s.st_ino} for x in sorted(p.rglob('*')) if (s:=x.lstat())];dest=pathlib.Path('/tmp/claude-mem-audit-20261118');raw=json.dumps(r,indent=2);(dest/'after.json').write_text(raw);before=json.loads((dest/'before.json').read_text());a={x['path']:x for x in before};b={x['path']:x for x in r};changes=[{'path':k,'before':a.get(k),'after':b.get(k)} for k in sorted(a.keys()|b.keys()) if a.get(k)!=b.get(k)];out={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'before_entries':len(before),'after_entries':len(r),'before_manifest_sha256':hashlib.sha256((dest/'before.json').read_bytes()).hexdigest(),'after_manifest_sha256':hashlib.sha256(raw.encode()).hexdigest(),'changes':changes};(dest/'safety.json').write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2));print('dbstat-reconcile');d=json.loads((dest/'dbstat.json').read_text());
for k,v in d.items():print(k,'object bytes',sum(x[2] for x in v['objects']),'free bytes',v['freelist']*4096,'file bytes',v['page_count']*4096,'accounted',sum(x[2] for x in v['objects'])+v['freelist']*4096)
logs=[x for x in before if x['path'].startswith('logs/') and x['path'].split('/')[-1]<'claude-mem-2026-10-19.log'];print('logs-older-30days',len(logs),sum(x['bytes'] for x in logs))
PY
```

</details>
