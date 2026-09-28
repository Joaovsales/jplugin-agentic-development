# Automatic bulk-read routing: paired evaluation

Protocol and prompts are in `protocol.md` and `prompts.json`. The 428-line `ledger.py` fixture was generated for this evaluation; no repository source was sent to the external evaluator. Neutral A–D answers were scored before opening each round's `sealed-arms.json`. Scores and raw transcripts are retained beside this report.

| Round | Direct cost | Routed cost | Direct elapsed | Routed elapsed | Broad quality direct → routed | Bug quality direct → routed | Routed fallbacks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | $0.002882720 | $0.003523158 | 14.84 s | 33.85 s | 5 → 5 | 4 → 4 | 2/2 |
| 2 | $0.002560240 | $0.005435764 | 11.15 s | 46.03 s | 5 → 5 | 4 → 4 | 2/2 tasks; bug task made a second read |
| 3 | $0.002655760 | $0.002776512 | 11.31 s | 19.16 s | 5 → 4 | 4 → 4 | 1/2 |

Cost sums all reported parent message costs and Scout worker costs, including failed maps. Elapsed time sums the two task wall times per arm; it is not a concurrency-adjusted throughput measure. Round 3 direct/routed total tokens were 20,539/30,635, including worker usage; cache reads were 6,528/6,528. Round 2's routed bug task made two reads and two worker calls; the other tasks used one native read each. No transcript showed a direct bounded inspection of cited ranges. Correction/retry counts were zero in rounds 1 and 3 and one extra read in round 2's routed bug task.

Round 3's routed broad read delivered a 1,406-character map in place of the 13,869-character source. Its total cost was $0.001149148 versus $0.001312320 direct, but quality fell from 5/10 to 4/10. Its five exception labels were invented. The routed bug read received the original source after `invalid_map`; its total cost was $0.001627364 versus $0.001343440 direct. Round 3 therefore cost 4.5% more overall and took 69% longer. Earlier rounds also cost more and took longer because maps failed validation and the original read was delivered. No whole-task savings or quality improvement is established.

All three rounds preserve worker metrics, fallbacks, assignments, prompts, answers, and blind grades. A fallback records `usage: unknown` even when a separate worker metrics record supplies usage for evaluation. This does not imply the fallback itself knows worker cost.
