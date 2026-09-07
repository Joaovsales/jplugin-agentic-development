# Sub-Agent Resilience

How to dispatch sub-agents so a failure surfaces as a **degraded result you can act on** instead of
a phase that sits dead until a human notices.

Applies to every skill that dispatches sub-agents: `/build`, `/yolo`,
`/auto-push`, `/quality-gate`, `/debug`.

---

## The failure that matters: a hang is not an error

An agent that **crashes** returns null and your fallback catches it. An agent that **hangs**
returns nothing at all — no result, no error, no event. Every null-check fallback is downstream of
a return that never happens, so none of them fire.

This is worse under parallel dispatch, because "wait for all to return" is a **barrier**: one hung
agent holds the whole phase, including its own fallback, forever.

> **Field incident.** Three agents dispatched in parallel; two returned in ~5 minutes, the third
> hung. The phase sat dead for ~20 minutes. The orchestrator had a `.filter(Boolean)` fallback *and*
> automatic retry — neither fired, because both live downstream of a return. The user was the only
> liveness detector in the system.

### Rule 1 — Give every agent a tool-call budget with an escape hatch

This is the single highest-value line you can add to a sub-agent prompt. It converts a hang into a
degraded return, which your existing fallbacks *can* see:

```
You have ~35 tool calls. If you approach that limit, STOP exploring and write your artifact
immediately with what you have, listing what you could not verify under a "## Not verified"
heading. A partial, honest artifact is SUCCESS. Hanging is the only failure.
```

Tune the number to the task (15 for a focused edit, 50 for a broad audit). The number matters less
than the explicit permission to return incomplete work.

**Budget for the return, not just the work.** Writing the artifact and returning the structured
result are two separate costs, and the return is the one that gets dropped. Say so explicitly:

```
The moment you write your artifact, STOP — your next action must be returning the result.
Do no further exploration after the write.
```

> **Field incident.** An agent given a ~35-call budget used 41, wrote a complete and correct 18 KB
> artifact, then died before emitting its structured result. The orchestrator saw no return, treated
> it as a failure, and redid the entire job twice. The work was never the problem; the last turn was.

**Watch which tools drain the budget.** The same agent spent **29 of its 41 calls on `Bash`**. It
had been told not to `Read` large files and complied — then substituted shell `grep`/`sed` loops,
which are correct but no cheaper. Name the tools you want it to *use*, not only the ones to avoid.

### Rule 1b — Generated size is the real budget, and never return the artifact twice

Tool-call counts are a proxy. The thing that actually kills an agent is **how many tokens it must
generate**, and the return is always last in line.

Two rules follow, and they matter more than the call budget:

**Cap the artifact, or don't use an agent at all.** An agent asked to emit a large document spends
its whole budget transcribing and dies before returning. Give a concrete size target in the prompt
("200–300 lines, hard cap 400; terse table rows, not prose").

If the output is a *mechanical* transform of existing text — merging, concatenating, reformatting,
de-duplicating — **do it with a script, not an agent.** An LLM re-emitting text verbatim is the
most expensive way to run `cat`, and the volume is exactly what makes it fail.

> **Field incident.** A "merge these two documents" agent had to emit ~40 KB (~12K output tokens)
> of near-verbatim transcription. It produced a correct, complete document — and then had nothing
> left to return, so the orchestrator retried the whole job. The task never needed a model.

**Never ask for the artifact back in the return schema.** If the agent writes a table to a file and
your schema also demands that table as structured output, it emits everything **twice**, and the
second emission lands at the moment its context is tightest. Have the return be a receipt:

```
PATH:    <file written>
COUNTS:  have=<n> partial=<n> missing=<n>
VERDICT: <2-3 sentences>
```

Then read the file yourself for detail. A rich schema is a liability on any agent producing a large
artifact — keep the payload to identifiers, counts, and a verdict.

### Rule 2 — Never put a risky agent inside a barrier

Barrier (`parallel` / "wait for all to return") is correct only when the next step genuinely needs
every prior result at once — dedup across a full set, an early-exit on a zero count, a merge.

If a step only needs results *individually*, pipeline them so each flows on as it lands. When a
barrier is genuinely required, keep the highest-risk agent (usually the one reading the most
source) **outside** it, and let the barrier close on the predictable agents.

### Rule 3 — Retry must vary the strategy, not repeat the prompt

Retry helps **transient** faults: rate limits, network blips, provider errors. It does nothing for a
**deterministic** one — an identical prompt against an identical environment fails identically, and
three attempts cost 3× for the same outcome.

Before retrying, ask: *what will be different this time?* If the answer is "nothing", change the
approach instead — narrower scope, different tools, split into two agents.

### Rule 4 — Monitor **progress**, not activity

The harness already notifies on **completion** and **error**. Polling "is it done yet?" is
redundant and burns tokens. The uncovered case is silence — so arm a monitor at dispatch time that
stays quiet while healthy and speaks only on trouble.

**The trap: a retry loop is indistinguishable from healthy work if you watch file activity.**

> **Field incident.** A monitor watched "has any agent transcript been written recently?" with a
> 240s idle threshold. It ran its full 23-minute window and never fired once — while the workflow
> was stuck retrying the same agent three times. Each retry wrote constantly, so idle time never
> rose. The heartbeat was perfect and nothing was progressing.

Measure **results landed** and **retries started**, not bytes written:

```bash
D=<transcript-dir>
EXPECTED=<number of agents the workflow defines>
lastres=-1; since=$(date +%s); warned=0; retrywarn=0
for i in $(seq 1 90); do
  res=$(grep -c '"type":"result"' "$D"/journal.jsonl 2>/dev/null || echo 0)
  errs=$(grep -c '"type":"error"'  "$D"/journal.jsonl 2>/dev/null || echo 0)
  started=$(ls -1 "$D"/agent-*.jsonl 2>/dev/null | wc -l)
  now=$(date +%s)
  [ "$res" != "$lastres" ] && { lastres=$res; since=$now; warned=0; }
  # no NEW RESULT in 6 min - activity is not progress
  [ $((now-since)) -gt 360 ] && [ "$warned" -eq 0 ] && \
    { echo "NO-PROGRESS: ${res}/${EXPECTED} results for $((now-since))s"; warned=1; }
  # more agents started than the workflow defines => something is failing to return
  [ "$started" -gt "$EXPECTED" ] && [ "$retrywarn" -eq 0 ] && \
    { echo "RETRYING: $started started, $EXPECTED expected"; retrywarn=1; }
  [ "$errs" -gt 0 ] && { echo "ERROR entries: $errs"; exit 0; }
  [ "$res" -ge "$EXPECTED" ] && { echo "all agents returned ($res/$EXPECTED)"; exit 0; }
  sleep 20
done
```

- **Retry detection is the highest-value signal** — `started > EXPECTED` catches a silently
  looping agent within one cycle, long before any timeout would.
- **~360s on results** — coarser than an idle threshold, because a single agent legitimately runs
  for minutes. Progress is the thing with a deadline, not activity.
- **Latch each flag** so one episode emits once. A monitor that fires every tick gets auto-stopped
  for noise, which silently removes your only detector.
- Exit on completion so the monitor doesn't outlive the run.
- Use an event-driven monitor, **not** a cron/wakeup poll — polling harness-tracked work is waste.

### Rule 5 — Report what was dropped

A degraded run that reports "done" is indistinguishable from a clean one. Whenever a fallback fires,
say so explicitly: which agent failed, what artifact is missing, what the downstream step ran
without. Silent truncation reads as full coverage.

---

## Conflicts with compaction and compression layers

Many setups run token-optimizing layers — output compressors, MCP proxies, harness autocompact.
They are cheap for the orchestrator and hostile to sub-agents that read a lot of source.

**The mechanism.** A large tool result is replaced by a placeholder such as
`[N items compressed to M. Retrieve more: hash=…]`. The agent calls the retrieval tool to recover
the text; retrieval can fail (`"Content not found. It may have expired or the hash may be
incorrect."`); the agent retries; it loops until it is killed. It never errors — it **hangs**,
which is exactly the case Rule 1 exists to catch.

**It is not uniform.** The failure selects agents doing heavy *text* reads. Agents reading images
(not text-compressed) or web results (small) are unaffected. So the agent that dies is usually the
one doing the most load-bearing work, and the phase looks "mostly fine".

> **Field incident.** A capabilities-documenting agent burned 17, then 22, then 4 retrieval calls
> across three attempts and never returned, while its image-reading and web-searching siblings both
> completed normally.

**Do not fix this by disabling the layer.** It is the user's environment and it is saving them real
tokens. Fix it by never generating a result large enough to trip it:

| Instead of | Use |
|---|---|
| `Read` on a 2000-line source file | `mcp__serena__get_symbols_overview` (compact symbol map) |
| `Read` to find one function | `mcp__serena__find_symbol` with `include_body` |
| `Read` to understand file structure | `smart_outline` (signatures, bodies folded) |
| `grep -r` across the repo | The `Grep` tool with a specific pattern |
| Reading a file "to be safe" | `sed -n '1,120p'` on the range you actually need |

Put these rules **verbatim** in the sub-agent prompt. They are never inferred:

```
- NEVER use Read on a file longer than ~400 lines. Use symbol-level tools or explicit line ranges.
- NEVER call retrieval/decompression tools. If a result looks like a compression placeholder, do
  NOT try to retrieve it — re-issue the SAME read at narrower scope. Retrieval will fail and burn
  your budget.
- NEVER grep generated index directories unscoped (graph/AST/embedding caches). A single unscoped
  grep there can exhaust your context.
```

**Corollary — keep artifacts on disk, not in the reply.** Have each agent write its output to a
file and return only a short summary plus a structured result. The orchestrator's context then holds
pointers and deltas rather than file bodies, which keeps the whole run below the threshold that
triggers compaction in the first place.

---

## Dispatch checklist

Before dispatching any sub-agent:

- [ ] Tool-call budget with an explicit "write partial work and stop" escape hatch
- [ ] Compaction-layer rules pasted verbatim if the agent will read source
- [ ] Artifact written to disk; only a summary + structured result returned
- [ ] Risky agents kept out of barriers; barriers used only where all results are genuinely needed
- [ ] Retry (if any) varies the strategy rather than repeating the prompt
- [ ] Stall monitor armed for anything running unattended
- [ ] Fallback path reports what was dropped instead of failing silently
