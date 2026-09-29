# The simplification lens

What `scripts/signals.py rank` looks for, how it scores a hit, and what it
never reports. The script is the executable form of this page; the constants
named here (`W`, `LINE_BUDGETS`, `CODE_BUDGET`, `ALWAYS_LOADED`,
`EXCLUDED_PREFIXES`) are defined once, in the script.

## The seven signals

| Signal | Fires on | `line` | `lines_saved` |
|---|---|---|---|
| `duplicate-rule` | one Markdown line of at least 60 characters (list marks stripped; headings, table rows and fenced code ignored) that appears in two or more files whose contents differ — byte-identical mirrors count as one home | the first home, by path | homes − 1 |
| `citation-drift` | a `` `<path>.md` § *<Heading>* `` or `` `/<skill>` § *<Heading>* `` citation whose target file exists but holds no `##`/`###` heading or bold label by that name | the citation | 1 |
| `over-budget` | a `SKILL.md` over 150 lines or an `AGENTS.md` over 200 (`LINE_BUDGETS`) | the first line past the budget | lines − budget |
| `doc-script-contradiction` | a Markdown line naming an existing `.py`/`.sh` script and a `--flag` that script's text does not contain — a **cue** | the line | 1 |
| `enforced-prose` | a Markdown line with *must*, *never* or *always* that contains a quoted needle (20+ characters) a `tests/*.sh` file already asserts — a **cue** | the line | 1 |
| `orphan-or-overlap` | a `references/*.md` file whose basename no other tracked file mentions | 1 | its line count |
| `code-red-flag` | a `.py` or `.sh` file over 500 lines (`CODE_BUDGET`) — a **cue** | the first line past the bound | lines − 500 |

A **cue** is a script-level guess. The deep review in `SKILL.md` confirms or
drops every cue before it is shown or filed; the other four signals are facts
about the tree.

One candidate per signal and file: hits of one signal in one file fold into the
first line, their `lines_saved` summed. `key` is `<signal> in <path>` — the
registry title, so the derived id is stable across runs.

## Score

```
score = lines_saved × max(callers, 1) × (W if always_loaded else 1)
```

- `callers` — tracked files, other than the candidate's own, whose text contains its path.
- `always_loaded` — `AGENTS.md`, `CLAUDE.md`, the session banner
  (`.agents/hooks/session-start.sh`), or a line inside a `SKILL.md`
  frontmatter: prose every session pays for.
- `W` — the always-loaded weight, **5** (D24). Revisit it when pick history
  shows always-loaded candidates dominating or never surfacing.

Candidates sort by score descending, then key ascending; `--limit` (default 10)
cuts after the sort.

## Exclusions

- **`tests/fixtures/`** — never read and never ranked. Fixtures are deliberate
  specimens; a `--path` that reaches only fixtures exits 2.
- **What `/tidy` owns** — its nine checks: `suite`, `inventory`, `retired`,
  `installed`, `refs`, `worktrees`, `strays`, `graph`, `registers`. A citation
  whose file does not resolve is `refs`; one naming a skill with no directory is
  `retired`; a flag beside a script that does not exist is `refs` again. The
  lens reports none of them — it looks for bulk, `/tidy` for rot.
