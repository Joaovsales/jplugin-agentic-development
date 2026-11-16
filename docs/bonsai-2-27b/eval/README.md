# Can a local model be the read-only reviewer? Bonsai 27B v1 against a labelled review set

**Verdict: NOT fit.** The local model does not fit a read-only reviewer role. On the scored arm it
reported 0 of 26 labelled findings strictly, and 1 of 26 under lenient credit (right defect class,
wrong mechanism). It missed **all 9 APPLIED SHOULD-FIX** findings strictly. 26 or 27 of its 27
findings were noise (precision 0–4 %). On the as-merged arm it asserted the refuted hypothesis
**R-2** ("a filled 32K context OOMs the container"). At its default reasoning setting it produced
no review at all. Adoption of any local reviewer persona (issue #405) stays gated on this verdict,
and this verdict is no.

Caveat carried from the label set: all four quality gates ran with Phase 4 INLINE, so their findings
were not corroborated by a second context. The label set is **one reviewer's opinion, not truth**.
That caveat does not rescue the result. Every finding counted as noise below was checked against
the code and is wrong on its own terms, not merely absent from the labels.

## Setup

| Item | Value |
| --- | --- |
| Model | `Bonsai-27B-Q1_0.gguf` (3,803,452,480 bytes), the model we would adopt |
| Runtime | stock llama.cpp `b12420` `llama-server`, bare metal, `127.0.0.1:18081` only |
| Flags | `-c 32768 -ngl 99 -fa on --cache-type-k q4_0 --cache-type-v q4_0 --jinja --no-webui` |
| Fit | loaded fully at `-ngl 99`: the server process held 5,004 MiB on the RTX 3050 6 GB (5,790 MiB free before, nothing else on the GPU). Log: [`raw/server.log`](raw/server.log) |
| Speed | 17.5–17.7 tok/s generation, ~316 tok/s prompt |
| Teardown | server stopped after the last run. Port 18081 is free and GPU use is back to 15 MiB with no compute processes |

## Method

- **Blind.** The model received only [`prompt.txt`](prompt.txt) followed by a unified diff: no PR
  number, no repository history, no mention of a prior gate or of being measured, and never the
  label set. The prompt was byte-identical across every run. [`run_review.py`](run_review.py) sends
  one request and writes the reply verbatim, plus any reasoning and the timings.
- **Which diff.** `gh pr diff <n>` shows the *merged* diff, which already contains every APPLIED fix
  (digest pins, `--cache-ram 4096`, the `shift` guard, the type checks), so APPLIED findings cannot
  be found in it. The **scored arm** therefore reviews the diff the gate itself reviewed: the PR base
  up to the commit before the gate-fix commit (409: `42eb935..2d11b05`; 411: `42eb935..18614aa`;
  419: `d1183c0..79997d3`). PR 410 had no gate-fix commit, so its pre-gate diff is `gh pr diff 410`.
  An **as-merged arm** runs `gh pr diff` as the task specified (409, 411, 419), and only the
  non-APPLIED labels are scorable there.
- **Truncation.** For #411 the generated `docs/bonsai-2-27b/results/` directory was excluded from
  both arms; it is captured output, not authored code. The full PR diff is 1,868 lines / 88,856
  bytes. The as-merged arm keeps 623 lines / 36,693 bytes, dropping 1,245 lines (~52 KB, 30 result
  files). The pre-gate arm is 602 lines. Nothing else was truncated.
- **Configuration search, so the model was not handicapped.** Four settings were tried on #409:
  1. Default (reasoning on), temperature 0: **no review**. 8,192 tokens of reasoning that mostly
     re-transcribes the diff, cut off at the limit after 468 s
     ([`raw/409.pregate.thinking-on.reply.txt`](raw/409.pregate.thinking-on.reply.txt)).
  2. Reasoning off, temperature 0: **degenerate**. It copied the diff's own comments back as
     "defects" (each MUST-FIX at confidence 100), then repeated one line 122 times until the
     8,192-token limit ([`raw/409.pregate.greedy-nothink.reply.txt`](raw/409.pregate.greedy-nothink.reply.txt)).
  3. **Runbook setting: `reasoning_effort: none`, GGUF default sampling, seed 42.** This is the
     setting `docs/bonsai-2-27b/README.md` benchmarked tool calling with. **It is the scored
     setting.**
  4. `reasoning_effort: medium` (the runbook's other tested effort): **no review**, 8,192 reasoning
     tokens, 468 s ([`raw/409.pregate.medium.reply.txt`](raw/409.pregate.medium.reply.txt)).
- **Grading.** Each reported finding was checked against the diff, and where it made a factual
  claim, against the code: `bash -n`, the `run` helper in `tests/lib.sh`, the Dockerfile's
  `&&` ordering, and the compose `environment:` override. **Strict hit** = the same defect as a
  label. **Lenient hit** = same place and defect class but a wrong mechanism. **Noise** = neither a
  label nor a defensible new observation.

## Results — scored arm (pre-gate diff, `reasoning_effort: none`)

| PR | findings | strict hits | lenient hits | APPLIED SHOULD-FIX caught | noise | precision | refuted FPs | wall |
| --- | ---: | --- | --- | --- | ---: | ---: | --- | ---: |
| 409 | 1 | 0 / 5 | 0 | 0 / 2 (409-A, 409-B) | 1 | 0 % | — | 5.1 s |
| 410 | 14 | 0 / 3 | 0 | — (none applied); missed 410-C SHOULD-FIX | 14 | 0 % | — | 71.8 s |
| 411 | 11 | 0 / 13 | 1 (411-D) | 0 / 5 strict, 1 / 5 lenient | 10 | 9 % lenient, 0 % strict | none | 99.3 s |
| 419 | 1 | 0 / 7 | 0 | 0 / 2 (419-A, 419-B) | 1 | 0 % | — | 10.8 s |
| **Total** | **27** | **0 / 26** | **1 / 26** | **0 / 9 strict, 1 / 9 lenient** | **26** | **0 % strict, 4 % lenient** | **0** | |

**Recall by label.** The only lenient hit is **411-D**. The model flagged a wrong-typed tool
argument in `toolcall_harness.py`, but on the `city` argument, which the code already coerces
with `str()`. The real crash sites (`a.get` on a non-object, `x.lower()` on non-string attendees)
went unreported. Every other label was **missed**:

- **409-A**: two copies of the fence parser, in plain sight at lines 57 and 82.
- **409-B**: the false "jq merge would overwrite pins" comment.
- **409-C, 409-D, 409-E**.
- **410-A, 410-B, 410-C**. 410-C sits in the `render_row` hunk the diff shows.
- **411-A**: tag-only base images.
- **411-B**: `--cache-ram` equal to `mem_limit`.
- **411-C**: `shift 3 || true`.
- **411-E, 411-F, 411-G, 411-H, 411-I, 411-J, 411-K, 411-L, 411-M**.
- **419-A**: the equal-versions vacuous assertion.
- **419-B**: the unconditional "after every merge" instruction.
- **419-C, 419-D, 419-E, 419-F, 419-G**.

**Noise, every item** (all checked; none defensible):

- **409 (1).** Line 47 says wrapping the fence in `{…}` "corrupts JSON that doesn't already start
  with `{`". The fence is a fragment, so the wrap is correct; the claim is inverted.
- **410 (14).** Every item is attributed to `registry/index.py`, but lines 296–438 are in
  `tests/test-task-registry-cli.sh`.
  - Module constant `AMBIGUOUS_ARROWS` "fragile global coupling". It sits next to 410-B but names
    a different, non-existent defect.
  - "Unescaped single quote … syntax error", reported 3 times. It is a `'` inside a double-quoted
    string, which is valid.
  - Non-UTF-8 terminal encoding.
  - `cat >` "could corrupt the index".
  - `2>&1` "makes capture impossible", reported twice. `assert_contains` searches the combined
    output by design.
  - Line numbers "may shift", reported 3 times. The heredocs are literal.
  - Output order "may reverse".
  - "Next upsert creates a different task", which is what the test asserts.
  - "Re-filing may append", which is what the test asserts against.
  - The reply also ends with `NO DEFECTS` after 14 defects.
- **411 (10).**
  - "`-ngl 99` question is a false premise".
  - Table header "absent".
  - Partial-offload text "reversed".
  - `tar --wildcards` "will fail". The image built and ran.
  - Confused `USER` directive.
  - "All repeating layers on GPU" contradicts `-ngl 30`. That sentence is about the full-offload
    rows.
  - NBSP/tab regex. The class holds `,`, U+202F, U+00A0 and space; there is no tab.
  - `names[:1]` reported twice. The check also scans every call for `get_file_info`.
  - `a.get("date")` "assumes a string … APIs often return a string". The claim contradicts itself.
  - Format violation: none of the 11 lines carries the required severity or confidence fields.
- **419 (1).** Line 214 says "a syntax error prevents the new assertion from running".
  `bash -n` is clean at `79997d3`. The model pointed at the very assertion that 419-A is about,
  but named a defect that does not exist and missed the real one: equal versions make it vacuous.

## Results — as-merged arm (`gh pr diff`, `reasoning_effort: none`)

APPLIED fixes are already in these diffs, so only `left` labels are findable.

| PR | findings | hits (left labels) | noise | refuted FPs | notes |
| --- | ---: | --- | ---: | --- | --- |
| 409 | 7 | 0 / 3 (409-C/D/E) | 7 | — | It claims the guard *fails* when the live file is absent; it prints a NOTE (409-C says the opposite). `KeyError` "unhandled", but it is caught. "Passes three args", but it passes `check` plus two. `$output` "undefined", but `run` sets it. 33.6 s |
| 410 | identical diff to the scored arm | | | | |
| 411 | 20 unique + 75× repeated line | lenient: 411-K (model filename in both files; "compose is ignored" is wrong, compose `environment:` overrides), 411-H partial (`0.0.0.0` exposure rests on compose) | 17 | **R-2** | **Hit the 8,192-token limit after 610 s in a repetition loop.** False claims: `ARG LLAMA_SHA256` "not defined" (line 7 of the Dockerfile defines it); `curl` "installed in runtime" (fetch stage only); the runtime image "lacks nvidia-container-toolkit" (host-side). |
| 419 | 5 | 0 / 3 (419-E/F/G) | 5 | — | `version` missing would raise `TypeError` (`.get("version", "")` returns `""`). `newline=""` "breaks parsers on Windows". README line "duplicated". All rated MUST-FIX at confidence 95–100. 24.3 s |

### False-positive arm (REFUTED hypotheses)

- **R-2: asserted** (as-merged #411, README:152): "`mem_limit: 8g` … insufficient for the 27B
  model's KV cache at 32K context … causing a predictable OOM", at MUST-FIX, confidence 90. The gate
  refuted this: the KV cache is preallocated on the GPU, so host memory does not grow with context.
- **R-1: not asserted verbatim**, but a sibling false claim against the same sha256 pin appeared
  (as-merged #411, README:351): the archive is "not verified before extracting". The Dockerfile
  chains `sha256sum -c - && … tar`, so extraction never runs on a mismatch.
- **R-3: not asserted.**
- Scored arm: none of R-1/R-2/R-3.

## Behavioural findings beyond the numbers

- **Unusable at the default setting.** With reasoning on (the template default) or at `medium`, it
  spends the whole budget re-reading the diff and returns nothing: 0 of 2 runs produced a reply.
- **Repetition loops.** 2 of 10 replies ended in a loop at the token limit (greedy no-think #409,
  as-merged #411).
- **Severity and confidence carry no signal.** Most findings are MUST-FIX at confidence 85–100,
  including every syntax-error claim that `bash -n` disproves. A gate that auto-applies at
  `confidence >= 75` (`.agents/references/finding-model.md`) would act on noise.
- **Misattribution and format drift.** Findings were attached to the wrong file (#410), the
  required severity and confidence fields were dropped (#411), and the reply contradicted itself
  ("NO DEFECTS" after 14 defects).

## Raw evidence

Every reply is verbatim under [`raw/`](raw/): `<pr>.pregate.reply.txt` (scored),
`<pr>.final.reply.txt` (as-merged), and the configuration-search replies on #409. Each file starts
with a META block (tokens, timings, finish reason). The exact diffs sent are next to them
(`<pr>.pregate.diff`, `<pr>.final.diff`, `410.diff`), with the server log in `raw/server.log`.
To rerun, start the server as in § Setup, then run
`python3 run_review.py raw/<diff> <out> [none|medium]`.
