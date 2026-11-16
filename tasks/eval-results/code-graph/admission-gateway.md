# Admission gateway — operational draft, not a registered protocol

`admission_gateway.py` is a one-attempt, localhost-only guard. No paid upstream
request was used to develop or verify it. Native integration and independent
review remain prerequisites to registering the experiment protocol.

## Admission invariant

Under the input-bound and pricing assumptions below, settled accounted upper
cost plus every outstanding/unknown reservation never exceeds $4. A lock covers
reservation and settlement. Every retry requires a fresh reservation before
forwarding; insufficient headroom returns an explicit error without forwarding.
A run uses one gateway process and a new audit path. Existing audit paths refuse
startup, preventing a restart from silently resetting an attempt's reservations.

For a UTF-8 JSON request, reserve:

```
input_bound = full_wire_JSON_bytes + 65536 + 256 * JSON_container_nodes
reserved_USD = 1.1 * (input_bound * 10 + max_tokens * 25) / 1000000
```

JSON containers are dictionaries/lists, including schema nodes. Depth is bounded
at 32, messages at 256, tools at 128, content arrays at 512, request bytes at
2,000,000, and requested output at 4096 tokens. Duplicate JSON keys and non-UTF-8
JSON refuse. Unknown top-level fields, nonstandard speed/tier, unknown cache TTL/scope,
server tools, images/documents and unsupported blocks refuse before forwarding.
Only standard custom tools and text/thinking/tool-use/tool-result blocks admit.
`output_config` supports only effort low/medium/high/max. Native metadata allows
only string user_id, including the native JSON-encoded identity string; identity
content is never parsed or logged. Diagnostics supports only previous_message_id
with null or a 1–256 character ASCII [A-Za-z0-9_-] value, covering provider msg_
IDs and UUIDs. Pinned native source at byte314439856 adds that diagnostic only;
its text/structure is covered by the same request bound. Thinking display supports the observed updates and the
pinned-native omitted mode. Context management supports only the observed
clear_thinking_20251015 edit with keep=all; other edits refuse. Fifteen observed OAuth/cache/provenance/thinking beta
names from transport-probe-receipt.json are explicitly allowed; unknown betas
refuse, including across duplicate header instances. Native integration must not
broaden this shape without a supported billing/input-bound explanation. The
first-party per-turn control message requires role=system and content,
permits only optional output_config, and its content is plain text or a text-only block list (with validated
cache_control) and output_config, when present, uses the same known effort enum. The observed
cache scope=global is admitted only with the existing ephemeral/5m-or-1h modes;
other scope values refuse, with worst-case cache pricing unchanged. Other system
message fields or nontext blocks refuse; all control bytes/nodes remain included
in the conservative reservation.

**Explicit bound assumption:** ordinary byte-level model text tokens consume at
least one input byte. Counting the whole wire JSON conservatively includes text,
escaping, keys and schema content. The additional 65,536 tokens plus 256 per
container cover provider-side protocol scaffolding for the admitted shapes.
This structural allowance is deliberately generous; it is not a published hard
Anthropic billing guarantee. Independent review must accept this assumption.
The gateway does not claim to protect against a provider violating max_tokens,
returning unreported charges, changing prices or exceeding that structural bound.
No `count_tokens` estimate is represented as an exact billing guarantee.

## Pricing provenance

Installed Claude Code 2.1.325 native catalog, binary hash retained by
`preflight-after-install-2026-11-15.json`:

| Evidence | Native binary byte offset |
|---|---:|
| Opus 5.5 model record, tier_4_20_cache_read_0_20 | 301196952 |
| Opus 4.8 model record, tier_5_25 | 301194932 |
| tier_5_25 rates | 301182644 |
| nKt token cost and v$ US geo multiplier | 304504855 |
| b_n fast-tier selection | 304506034 |

The known normal-rate union per million tokens is input $5, output $25,
5m cache-write $6.25, 1h cache-write $10, and cache-read $0.50. Neither model/tier
has a long-prompt price tier. All token costs are multiplied by the conservative
US geo maximum 1.1. Admission treats all possible input as the most expensive
1h cache write. Settlement uses input/cache-write/cache-read/output rates
5/10/0.5/25, still multiplied by 1.1; this is an **accounted upper cost**, separate
from the native runner's nominal model cost and any actual provider discount.

The only requested model is the exact `claude-opus-5-5`; supported served IDs are
that model and the locally evidenced `claude-opus-4-8` mapping. Fast requests,
priority tiers and fast/priority/batch beta headers refuse. Run the native client
with `CLAUDE_CODE_DISABLE_FAST_MODE=1` and
`CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096`. Unknown served model, usage speed, inference
geo or nonzero server-tool usage retains the reservation and blocks new requests.
Known normal geo values are global/us, with absent metadata treated as standard.
Unknown usage fields, priority service tiers, advisor iterations and inconsistent
cache breakdowns also retain the reservation and block new requests. Advisor
beta modes refuse before forwarding. Native model-tool traffic with additional
billable modes must never obtain a refund from the four ordinary token counters.

## Settlement and transport

Full JSON usage or complete SSE message_start/message_delta/message_stop usage
permits reconciliation. SSE accounting requires exactly one start and stop, at
least one message_delta containing a cumulative output count, nondecreasing token
and cache counters, and no event after the terminal stop. Unknown pricing seen
in any intermediate event cannot be erased by a later event. Duplicate starts,
duplicate stops, decreasing counters and post-terminal events retain the entire
reservation and block subsequent requests. Truncated/incomplete streams retain
reservations; malformed streams also block. The forwarded bytes remain unchanged;
settlement occurs only after parsing the bounded complete wire response. Input, creation, read and output counts must be
nonnegative integers; input sum must fit input_bound and output must fit
max_tokens. Missing/partial usage, an interrupted stream, transport error or
malformed response keeps the entire reservation. Every failed/unknown attempt's
held amount contributes to the program budget until stronger evidence exists.

The listener binds only 127.0.0.1 with a random capability path. The only model
route is `/v1/messages`, optionally `?beta=true`. Upstream is fixed to
`https://api.anthropic.com`; redirects refuse and request timeout is 120 seconds.
Other paths, including batches, return errors. Production has no upstream-host
flag. Only the constructor's test-controlled transport injection avoids network.
The production default does not inject a fake response or a fake success.

Auth and necessary native SDK headers pass in memory only to that fixed host.
Audit records contain request hashes, token bounds, reservation IDs and costs,
settled upper costs, held totals and denials. They contain neither request bodies
nor credential headers. SSE bytes pass through unchanged. Responses carry their
upstream status; gateway denial/failure carries an explicit error response.

Example (no upstream request is made merely by starting the listener):

```
python3 tasks/eval-results/code-graph/admission_gateway.py --audit /private/new-run-audit.jsonl
```

The first stdout line is the ephemeral local base URL. Keep that capability out
of committed artifacts while the listener runs. One fresh attempt must not share
or reset another attempt's audit/budget. Parent orchestration still must reserve
this attempt's $4 against the program's $320 before launch.

## Verification and remaining integration

`python3 tasks/eval-results/code-graph/test_admission_gateway.py` is offline.
It first failed because the gateway implementation was absent, then passed after
implementation. A native-shaped request regression failed before native context
management/thinking-display support and passed afterward. Native request examples
in native-request-shape.json contain synthetic text/identity only; their keys,
tool names and harmless modes match the unpaid transport metadata. The complete
observed beta header is snapshotted in native-beta-header.txt. Ten streaming
scenarios in stream-order-cases.json cover ordinary success and malformed replay,
ordering and usage histories. The retained proof records the final command, source hashes and
output. Tests cover exact boundary, concurrent reservations, partial/retry holds,
unknown model/modes/server tools, cache pricing, secrets, unchanged SSE bytes,
reconciliation, canonical routing/redirect refusal and audit-reset refusal.

Not finished: independent review of the structural assumption; final native
request-shape compatibility; parent-owned transport/Bash prerequisite; confirming
all graph navigation commands avoid separately billed backends; official protocol
registration; real N=3 runs and results. No paid call or protocol freeze occurred.
