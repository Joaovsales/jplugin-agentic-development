# Full /eval Run — All Skills

Copy-paste prompt for a fresh pi session. Run on the `skill/eval-playbook`
branch (PR #70) so the `/eval` skill is loaded. Report lands in `tasks/evals/`.

Budget note: ~25 Phase-1 runs + 32 Phase-2 runs on build tier (qwen3-coder-next),
8 judges on reasoning tier (deepseek-v4-pro). Abort / downscope if spend looks wrong.

---

/eval Run the full evaluation across .agents/skills/ and generate a report at tasks/evals/skill-report-<date>.md

Follow the /eval playbook exactly. This is a two-phase eval:

PHASE 1 — TRIGGERABILITY AUDIT (all 25 skills, cheap)
For every skill in .agents/skills/, test whether the harness actually fires it
under progressive disclosure. For each skill, compose an organic user request
that a real user would type and that the skill's description claims to cover
(e.g. for verify: "is my work actually done? run what's needed before I commit").
Spawn one candidate per request in its own sanitized worktree (worktree: true).
The candidate sees ONLY the organic request. Grade from its session transcript:
did the agent load the skill file, and did it follow it — or did it freestyle?
Sanitize: no eval vocabulary in any directory name, worktree name, or prompt.
Name worktrees after project-shaped slugs a user might pick.

PHASE 2 — PAIRED LIFT (top 8 skills by Phase-1 relevance, paired A/B)
For each of the 8 highest-stakes skills (pick: plan, build, verify, quality-gate,
debug, wrap-up-session, receive-review, tdd — adjust if Phase 1 shows others
matter more), run the paired design:
- Variant A: candidate runs with the skill present in .agents/skills/
- Variant B: candidate runs in a worktree where that skill's directory is removed
- Same organic prompt to both, one prompt per skill, composed per the blinding
  non-negotiables: organic, no meta, no chain-eliciting, no eval terms anywhere
  the candidate can see, candidates unaware of each other.
- N=2 repetitions per variant per skill (32 candidate runs total). Do not exceed
  this without asking me.
- One judge per skill, model family different from the candidate tier (candidates
  on qwen3-coder-next, judge on deepseek-v4-pro), single pass, one scale, sees
  outputs by sanitized label only, never model or variant names. Two variants'
  outputs must be interleaved in one judge prompt, not judged separately.
- Write the rubric (3-6 concrete criteria) BEFORE spawning anyone. Hold it back
  from candidates. Judge only.

VERIFICATION
Do not trust candidate self-report. Read each candidate's transcript under
.pi/agent/sessions/: which files did it actually open, what commands did it
actually run, what does the code shape look like. Grade chain-following from
evidence. Then read every candidate output yourself end to end; note every
place your read disagrees with the judge.

REPORT
tasks/evals/skill-report-<date>.md with, per skill:
- triggerability verdict (fired / fired-but-ignored / never fired) with transcript evidence
- lift table (A vs B pass rate, wall-clock, tokens) — report cost alongside lift
- judge verdict vs your synthesis, including disagreements
- one-line recommendation per skill: promote / keep / rewrite / delete
End with: overall stats, total spend, skills that never fired at all (deletion
candidates), and any rubric ambiguities you had to resolve mid-run.
