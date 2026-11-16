# Usage-stream compatibility repair

This is a post-smoke operational compatibility repair, not a protocol change or
paid-retry authorization. The original failed attempt, audits and charges remain
untouched: nominal USD 0.14927200000000002; accounted held USD 1.660241.

The exact original SSE event was not retained. The native source establishes
legitimate variants that the previous gateway rejected, but does not prove one
unique cause for that paid failure. See usage-debug-receipt.json.

## Supported normalization

Pinned Claude Code 2.1.325 Jwe at byte314531014 and SDK xc at306234834 support the
following narrowly admitted shapes:

- Only message_delta input/cache counters use None or actual integer0 as absent
  updates, retaining prior validated values. False, 0.0 and other falsey values
  are rejected; positive nonzero declines still reject.
- Null/all-zero cache breakdown placeholders retain the prior breakdown. A
  positive known breakdown can supply the missing/placeholder aggregate count.
  Positive child declines and final aggregate/breakdown inconsistencies reject.
- Null known pricing metadata retains its previously validated mode; unknown
  fields, fast/priority modes, additional billed iterations and server tools
  remain rejected. Nullable handling never drops an unknown field.
- Known output_tokens_details accepts only nonnegative integer thinking_tokens;
  None means no update. The largest observed thinking count must fit final
  cumulative output. Output counters remain integer/nondecreasing whenever
  present, and terminal completion requires valid cumulative delta output
  evidence. Metadata-only deltas cannot manufacture completion evidence.
- fallback_credit is accepted only as null/absence. Numeric zero, nonzero or
  unknown credits do not introduce discounts or billing support.

Text, thinking, redacted_thinking and custom tool_use output block starts are
supported. Explicit fallback, server_tool_use and other unknown block types
retain the full reservation and block reconciliation. A known mapped4.8 model
at message_start remains supported; no midstream fallback billing is invented.

## Preserved enforcement and diagnostics

The $4 attempt limit, output4096 cap, conservative JSON-byte/structural bound,
normal pricing union times1.1, fixed canonical upstream, authentication handling
and reservation locking are unchanged. No protocol, initial manifest, execution
state or prior paid-attempt audit is edited by this repair.

Future parser failures record only a bounded static reason, known event type,
known usage-key names/types and unknown-key count. Prompt/model text, unknown
field names/values, credentials and identity content are excluded. The redaction
regression includes synthetic secret values in both content and usage fields.
Diagnostics are operational evidence, never verdict inputs.

## Verification

Sixteen offline tests pass, including native null/zero cache/input placeholders,
nullable pricing and output detail variants, cache-total derivation, strict bool
and float rejection, genuine positive declines, credit denial, SSE ordering and
post-terminal protection, mapped-model starts, fallback/server-tool rejection,
monetary concurrency and credential/prompt redaction. New compatibility and
fallback regressions failed before their corresponding implementation fixes.

Limitations: this proves the enumerated source-supported variants, not the lost
paid event or every future API shape. Inconsistent cache totals, initial nullable
pricing not supported by the prior contract, and unknown modes still fail closed.
No network model generation, paid diagnostic, new selected sample or retry ran.
A separate reviewed/versioned manifest migration must preserve every earlier
charge and the same planned-slot retry limit before any subsequent payment.
