# Checkpoint — 2026-11-15 — code-graph adoption

## Overall status
- HALTED-NEEDS-USER at slice 8; slices 1–7 implemented, slice 9 blocked.
- Authoritative resume ledger: tasks/code-graph-run.md.
- Current branch: code-graph/treatment; source checkpoint before final bookkeeping: 03d550b.
- Evaluation spend: $0; no protocol, paid model run, measured outcome, or go/no-go verdict.

## Completed
- Phase A merged as PR416 at c7360e4; quality GO b7cfd232, Linux CI43752230413 success; full suite97 files/8217 assertions green.
- Treatment slices5–7 committed locally and unmerged; affected55 files/5331 assertions green.
- Native Codex0.166.0 support established by generated public schema; only fixture configurations were modified by tests.
- File-only AC7 clarification and all other ambiguity choices are recorded under the plan handovers; go-rule bytes unchanged.
- Every slice has a handover;8/9 remain unfinished.

## Blocker and evidence
- Canonical `python3 evals/code-graph/fixture_gen.py --check-runtime` exits2: CLI does not match pin0.9.109; CLI-launcher distribution metadata is0.4.23.
- tasks/eval-results/code-graph/preflight-2026-11-15.json retains UTC, stdout/stderr and distribution/probe evidence.
- D13 forbids agent installation. pipx exists; a person must run the installer offer in a terminal.

## Manual action, not executed
```bash
cd /tmp/harbor-setup-hddf8lis && bash /tmp/harbor-workflow/install.sh
```
Accept the graphify y/N offer. The installer checkout is exact merged Phase A; setup cwd is neutral to preserve both experiment checkouts.

## Resume
1. Read the ledger and these slice handovers; grep learning-store frontmatter for code-graph/codex/hooks.
2. Re-run the canonical runtime guard. Resume only when the pinned CLI is present; then establish exact model id and commit the full protocol before any paid run.
3. Keep N=3, $320 total/$4 per run, fixed go rule, synthetic seeds, C excluded by the spike and Claude Code-only verdict.
4. Finish slice8, then9. No treatment merge without literal go plus full quality, suite and Linux CI; on no-go record results separately and retain the independent banner-pin hygiene correction.
5. The treatment received only partial independent runtime review, not a full merge clearance. Run the required full gate before any treatment merge. Never force-push.
