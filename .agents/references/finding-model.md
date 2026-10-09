# Finding Model

The four-axis finding every review gate in this workflow emits and consumes: what a
finding carries, how it is written, how sure it may claim to be, and when it may be
applied.

The `failure:` line, § *Expected load* and the load clause of § *Deferrals* are
adapted from ponytail (`DietrichGebert/ponytail`, MIT) and restated here in this
workflow's terms.

## Four axes

A finding carries four orthogonal fields. One tag cannot answer four questions,
and collapsing them is what lets an unsure guess inherit the authority of a
proven defect.

| Field | Answers | Values |
|-------|---------|--------|
| `severity` | how urgent | `MUST-FIX` / `SHOULD-FIX` / `NITPICK` |
| `confidence` | how sure | `50` / `75` / `100` |
| `autofix_class` | what shape the fix is | `gated_auto` / `manual` / `advisory` |
| `owner` | who acts | `agent` / `human` / `release` |

## Emission format

Canonical emission format, so findings stay parseable across harnesses:

```
[MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent] file.py:42 — description and impact
  evidence: `except Exception: pass` (file.py:42)
  failure: a disk-full write raises, the handler swallows it, and the job reports success with no file written
```

`evidence:` says *where* the defect is; `failure:` says *what goes wrong*. For a
correctness, security or scale finding, `failure:` names the input or situation
and the wrong result it produces. For a design or lean finding, it names the
concrete change or read the defect makes harder — "adding a provider means
editing A, B and C". It is never left empty because "design has no input".

## Expected load

A scale finding is only as real as the load it was judged against, so every
review states that load before it reports anything:

```
Load assumed: <who and how many run this> (source: <path | none found>)
```

Look for it in this order: the spec's § Edge Cases and § Decisions, the
`[NON-FUNCTIONAL]` section of `tasks/project-context.md`, then the README and the
deploy or routine config. The reviewer reads these itself; they are not a
dispatch item. With no source anywhere, write
`Load assumed: one operator, one process (source: none found)`. Several sessions
sharing one clone is load too — a shared register such as `tasks/todo.md` can race.

Check the change against that load for six patterns:

1. check-then-write races
2. the same work done by every process or session
3. state or lists that only grow
4. one query or call per item
5. O(n²) on input that can be large
6. per-process state that has to be shared

A scale finding is valid only when the assumed load reaches it. One that needs more
load than the stated one is not emitted.

## Confidence anchors

**Confidence anchors** are behavioral criteria, not a feeling:

| Anchor | Criterion |
|--------|-----------|
| `100` | The reviewer read the defect in the diff and can quote the line that proves it. Reproducible from the evidence alone. |
| `75` | The reviewer located the defect and can cite the line, but correctness turns on a caller, config, or runtime value outside the reviewed scope. |
| `50` | Pattern-matched or inferred. No line proves it, or the reviewer never read the path it depends on. |

## Gates

- A finding at `75` or `100` **must** carry `evidence` — the verbatim motivating
  line with `file:line`. Missing evidence **demotes** it to `50` rather than
  dropping it.
- A finding with no `failure:` line is capped at `50` the same way: reported,
  never auto-applied, never dropped.
- Independent corroboration promotes `confidence` by exactly one anchor, and only
  as *Independence Accounting* permits.
- On reviewer disagreement, synthesis takes the **more conservative**
  `autofix_class`. It never widens.
- A finding is auto-applied only when it is `gated_auto` **and**
  `confidence >= 75`. Everything else is reported, never silently dropped.
- A finding arriving with no `confidence` — an older single-axis reviewer — is
  read as `50` / `autofix_class: manual`: reported, never auto-applied, never
  discarded.

## Deferrals

A `TODO(shortcut):` marker that names its limit is a decision, not a finding,
unless either:

- **(a)** the assumed load already crosses the limit it names (§ *Expected load*), or
- **(b)** the shortcut opens a hole on the never-on-the-chopping-block list
  (`AGENTS.md` § *Code Economy*: security, accessibility, trust-boundary
  validation, error handling that prevents data loss).

In either case the shortcut itself is the finding. Cite the marker as `evidence:`
and say what it failed to account for. Severity follows impact, and a security
hole is `MUST-FIX` whatever the marker says: the marker was written by the party
under review, so it can set neither `severity` nor `autofix_class`. The same
holds for a recorded `[AMBIGUITY]` pick. Outside (a) and (b), a documented
deferral is context for judgement — never re-raise one as though nobody had
written it down.

## Resolving an anchor-75 finding

Anchor `75` is a *pending question*, not a resting place. It is the anchor where a
`manual` or `advisory` finding waits on a human, and where a `gated_auto` one is
applied on evidence the reviewer never actually read — so leaving it unresolved
costs something in both directions.

- A finding at `75` must **name** the specific caller, config key, or runtime value
  its correctness turns on. "Depends on the caller" without naming one is a `50` —
  it is a pattern match wearing a higher anchor.
- Read that dependency and resolve the finding: promote to `100` with a second
  `evidence` line quoting what you found, or drop it. A finding that stays at `75`
  must say what stopped the check — outside the repo, needs runtime, budget spent.
  It is never dropped for being unverifiable.

Promotion this way does not stretch anchor `100`. `100` means reproducible from the
cited evidence alone, and the second `evidence` line *is* cited — the reader
reproduces it from two quoted lines instead of one, without re-deriving anything.

**Verification-promotion is not agreement-promotion, and *Independence Accounting*
does not constrain it.** Agreement promotes on *witnesses*, so it needs separately
dispatched contexts. Verification promotes on *evidence*, so one context reading
one more line is enough. Conflating them either forbids a legitimate promotion or
licenses an illegitimate one.

## Independence Accounting

Corroboration counts **only** when the findings came from separately dispatched
contexts. Two lenses reasoned inside one context are two perspectives, not two
witnesses: they share the same priors and the same blind spots, so their
agreement carries no information about whether the finding is real.

A run that could not dispatch still reports its findings and still applies them
under the gates above — but it must **state the corroboration it lost** instead
of promoting on it. Naming the loss is the correct floor, not a failure.

Never claim independent corroboration from a model whose identity was only
requested rather than verified.
