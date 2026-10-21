# read-shunt suite

Eleven cases for `claude plugin eval`: eight force a large read, three are
controls that stay under the threshold (bytes >= 32768 or lines >= 800).

| Case | Tag | Fixture the scaffold generates |
|---|---|---|
| billing-client-zero-total | large | generated API client of about 5,000 lines with a three-line bug |
| nightly-pipeline-failure | large | CI log of 20,000+ lines with one traceback near the end |
| catalog-currency-field | large | small model file plus a catalog JSON over 256 KB |
| orders-extract-tax | large | module of about 3,000 lines with 15 callers |
| pipeline-checks-intermittent | large | about 2,000 lines of checks, one of them order-dependent |
| settings-loader-port | large | reference loader of about 1,500 lines to port |
| load-record-callers | large | 40 small modules, 23 still on the old name |
| changelog-release-notes | large | changelog of about 900 lines |
| readme-typo | control | 60-line README |
| timeparse-coverage | control | 200-line module |
| ratelimit-clock-skew | control | one file of about 25 KB |

Fixtures are generated into the run workspace by `fixture_gen.py` from a fixed
seed per case and are never committed. Each `fixture.sh` is the thin call
`python3 fixture_gen.py <case> --out .`. No case name, prompt or generated path
contains the blinding words of `/eval` (see `.agents/skills/eval/SKILL.md`).

## Layout

Cases sit directly under this directory because the runner discovers
`<eval dir>/**/prompt.md` and `case.yaml`; point `--eval-dir` here.

```
<case>/prompt.md           frontmatter + the prompt a user would type
<case>/case.yaml           tags (large | control) and the scaffold script
<case>/fixture.sh          scaffold: runs fixture_gen.py into the workspace
<case>/graders/outcome.md  deterministic grader (regex or file_exists)
<case>/graders/judge.md    llm grader applying rubric.md
<case>/graders/parent-read.md   large cases only: indicator of whole-file parent reads
rubric.md                  judge axes, written before any run
```

## Run

`--scaffold` is mandatory (without it no fixture exists), and every run
carries a cost ceiling. Start with one control and one run:

```
claude plugin eval . --eval-dir evals/read-shunt --scaffold --allow-tools Bash Edit Write --runs 1 --max-cost-usd 2 --case 'readme-typo' --json
```

Full suite, one run per case:

```
claude plugin eval . --eval-dir evals/read-shunt --scaffold --allow-tools Bash Edit Write --runs 1 --max-cost-usd <n> --json
```

Results land in `evals/read-shunt/results/<timestamp>/`. Grade them from the
transcripts with `grade-read-shunt.py`, not from what the run said.

Before any paid run: `bash tests/test-read-shunt-evals.sh` checks the case
shapes, the blinding words and the promised fixture sizes.
