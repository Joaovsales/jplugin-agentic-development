# Automatic bulk-read routing: paired task protocol

2026-09-28. Four fresh, isolated Pi CLI runs use the same installed OpenRouter
`qwen/qwen3-coder-next` parent. Direct and routed arms differ only by
`BULK_READ_GATE=off` versus the post-read extension with the installed
`deepseek/deepseek-v4-flash` worker. Each run receives an identical copy of a generated, non-repository `ledger.py` fixture and the same prompt for its task. No edits are allowed.
The initial native `read` is unbounded to exercise the route. The parent may
inspect cited ranges and related files afterward.

Tasks: (A) enumerate the fixture's public functions, four rule bands, and five exceptional rules;
(B) diagnose the unfinished-marker metadata parsing bug, including its two consumers. The corresponding prompt text is frozen in `prompts.json`.

Blind quality rubric, each axis 0–2: factual correctness, relevant source
coverage, direct cited-range verification, dependency/caller understanding,
and clear unknowns. Ten points total. Grade final answers from neutral IDs
before looking at arm labels. Preserve all failures, retries, and corrections.

For each run retain raw JSONL, elapsed wall time, parent input/output/cache
usage and reported cost, worker usage and reported cost, retry/correction count,
and quality score. Unknown counters stay unknown. Whole-task cost is parent
reported cost plus worker reported cost; context reduction is recorded
separately from savings. No population-level or percentage savings claim follows
from one paired run per task.
