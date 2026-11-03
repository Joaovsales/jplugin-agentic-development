# Answer key and judge rubric

Operator-only; never copied to a candidate. Written before any run. Do not edit it
once the first run has started.

## Part 1 — Judge rubric (fixed before any run)

One judge reads every run's final diff and `tasks/todo.md` end state in a single pass,
under sanitized labels, on a stronger model tier than the candidates. Each criterion
is scored 0, 1 or 2 per run; the sum (0-10) is reported beside, not in place of,
the objective measures. The judge gets the spec, the answer key's pitfall list for
the feature, and the diff. It never gets an arm name, a plugin name or the plan
grammar.

| # | Criterion | 0 | 1 | 2 |
|---|-----------|---|---|---|
| R1 | Interface depth: does one call hide the decisions the spec's § Interfaces lists under Hides? | callers must do the work (pass timestamps, loop themselves, convert themselves) | partly hidden; one leaked decision | every listed decision hidden |
| R2 | Error design: are the spec's edge cases handled by definition rather than by exceptions callers must catch? | extra exception types or raised errors where the spec defines a return | one avoidable raise | errors exist only where the spec says |
| R3 | No pass-through or shallow layers: no class, function or module whose body only forwards to another | two or more | one | none |
| R4 | No leaked internals: public names expose no clock arithmetic, parse state or merge structure beyond the spec's interface | several | one | none |
| R5 | Fit with existing code: reuses `backoff.delays`, `ManualClock`, `parse_ini`; leaves `parse_ini` behaviour unchanged | re-implements or alters an existing unit | reuses some | reuses all that applies |

Disagreement between the judge and the operator's own reading of a run means the
rubric is ambiguous: fix the wording, then re-judge all runs. Never re-judge one run.

## Part 2 — What counts as a `/quality-gate` design finding

A **design finding** is one distinct occurrence, in the candidate's final diff, of a
pitfall below, counted once each. Count the findings the candidate's own
`/quality-gate` Phase 4 (design audit) reports in its transcript as the primary
number; the judge then counts the occurrences left in the final diff from this list,
as a cross-check. Report both. A pitfall already fixed before the gate ran counts in
neither.

Common to both features:

- **Shallow module**: a class or function whose interface is nearly as large as its
  body, such as a `Retrier` class with `should_retry()` / `next_delay()` the caller
  must loop over.
- **Pass-through**: a method or function that only forwards its arguments to another
  of the same signature (a `RetryPolicy.delays()` that only returns `backoff.delays`
  with the same arguments; a `Config.get_raw()` that only returns a dict item).
- **Leaked internals**: public attributes or parameters that expose the refill
  timestamp, the token float, the merged dict, the per-file parse results, or a
  `now` argument.
- **Error handling that could be defined away**: a raise where the spec defines a
  return value (see per-feature lists).
- **Duplicated behaviour of an existing unit**: a second backoff sequence, a second
  INI parser, a private clock.

### retrykit

| # | Pitfall | Where it shows |
|---|---------|----------------|
| P1 | `TokenBucket.try_take` takes a timestamp, or exposes `tokens`, `last_refill` or a `refill()` the caller must call | `retrykit/bucket.py` public surface |
| P2 | `try_take` raises `ValueError` for `count` above capacity or at most zero (the spec defines `False` and `True`) | `bucket.py` |
| P3 | `RetryError.reason` is free text or an exception subclass per reason instead of the three values, or a second exception type exists | `retrying.py` |
| P4 | A `Retrier`/`RetryRunner` class, a `should_retry` or `next_delay` method, or a loop callers must write | `retrying.py` |
| P5 | A private re-implementation of the delay sequence or of sleeping instead of `backoff.delays` and `clock.sleep` | `retrying.py` |
| P6 | `call_with_retry` reads `time.monotonic()` / `time.sleep()` directly instead of the clock | `retrying.py` |
| P7 | `max_attempts <= 0` raises instead of making one attempt | `retrying.py` |
| P8 | `retrykit/__init__.py` gains re-exports or other edits the spec does not ask for (surface creep; count once) | `__init__.py` |

### confkit

| # | Pitfall | Where it shows |
|---|---------|----------------|
| P1 | `Config` exposes the merged dict, or separate `get_int` / `get_bool` / `get_float` methods instead of `get(..., as_type=)` | `layered.py` |
| P2 | `get` raises `KeyError` / `ConfigError` for an absent key instead of returning `default` | `layered.py` |
| P3 | A missing file raises, or a `required=` / `strict=` parameter is added | `layered.py` |
| P4 | More than one error type reaches callers (`ParseError`, `OSError`, `ValueError` leaking out of `load_config` or `get`) | `layered.py` |
| P5 | The loader stops at the first malformed line or first bad file, or raises once per file | `layered.py` |
| P6 | `parse_ini` signature or behaviour changed (tests in `tests/test_parse.py` edited, or case-folding added inside it) | `parse.py` |
| P7 | A second INI parser inside `layered.py` instead of a helper beside `parse_ini` that shares the line grammar | `layered.py`/`parse.py` |
| P8 | `load_config` returns per-file objects or an origin map the caller must pass back to `get` (origin leaks in the signature) | `layered.py` |
| P9 | A pass-through layer: `LayerSource`, `EnvSource` classes whose only job is to forward | `layered.py` |

## Part 3 — Answer key: AC coverage

Grade AC coverage by running **probe scripts** the operator writes from this section
against each run's final tree (never shown to the candidate). A probe file lives
outside the run directory and imports from it. An AC counts as covered when every
probe row for it passes. Report `ACs covered / total` per run.

The probes need only the public interface in each spec's § Interfaces, so a
candidate's private structure does not matter. If an import named in the spec does
not exist, every AC of that module is uncovered.

### retrykit — 9 ACs

Use `ManualClock` from `retrykit.clock`. `fn` is a function that raises `OSError`
for its first `k` calls and then returns `"ok"`; count calls.

| AC | Probe | Expected |
|----|-------|----------|
| 1 | `b = TokenBucket(3, 1.0, ManualClock())`; call `b.try_take()` four times | `True, True, True, False` |
| 2 | drain the bucket; `clock.advance(1.0)`; `try_take()` then `try_take()`; then `clock.advance(1000)`; `try_take(3)` then `try_take()` | `True, False`, then `True, False` (never more than capacity) |
| 3 | bucket with 2 tokens: `try_take(3)` then `try_take(2)`; `try_take(4)` on capacity 3; `try_take(0)` and `try_take(-1)` on a drained bucket | `False, True`; `False` and no exception; `True, True`, tokens unchanged |
| 4 | `call_with_retry(lambda: "ok", clock=c)` | returns `"ok"`, one call, `c.now()` unchanged |
| 5 | `fn` failing twice, defaults, `c = ManualClock()` | returns `"ok"` after 3 calls; `c.now() == 0.3` (0.1 + 0.2), within 1e-9 |
| 6 | `fn` always failing, `RetryPolicy(max_attempts=3)`; and `max_attempts=0` | `RetryError`, `.reason == "attempts"`, `.attempts == 3`, `__cause__` is the last `OSError`; second case calls `fn` once and raises `RetryError` with `attempts == 1` |
| 7 | `fn` raises `KeyError`, `RetryPolicy(retry_on=(OSError,))`, bucket given | the `KeyError` itself escapes; one call; clock unchanged; bucket untouched |
| 8 | always-failing `fn`, `RetryPolicy(max_attempts=10, base=1.0, factor=2.0, deadline=2.5)` | `RetryError` `.reason == "deadline"`; clock never passes 2.5 (sleeps 1.0 then 2.0 would end at 3.0, so only the first sleep happens: `c.now() == 1.0`) and `.attempts == 2` |
| 9 | `budget = TokenBucket(1, 0.001, c)`; always-failing `fn`, `max_attempts=5`, called twice with the same budget | first call: one retry spends the token, the next retry raises `.reason == "budget"` with no sleep for it (`.attempts == 2`); second call: first attempt runs (`fn` called) and its first retry raises `"budget"` (`.attempts == 1`); a first attempt never takes a token |

Edge cases beyond the AC list a thorough run should also satisfy (record separately,
do not add to the count): bucket never above capacity after a long jump (AC 2 covers
it), deadline measured from the first attempt, budget `None` means unlimited.

Expected public interface (names and signatures only):
`retrykit.bucket.TokenBucket(capacity, refill_per_second, clock=None).try_take(count=1) -> bool`;
`retrykit.retrying.call_with_retry(fn, *, policy=RetryPolicy(), budget=None, clock=None)`;
`retrykit.retrying.RetryPolicy` (frozen dataclass, the six fields and defaults of the
spec); `retrykit.retrying.RetryError` with `.reason`, `.attempts`.

### confkit — 10 ACs

Write the INI files into a temp directory. `from confkit.layered import load_config, ConfigError`.

| AC | Probe | Expected |
|----|-------|----------|
| 1 | file1 `[db]\nhost = a\nport = 1`, file2 `[db]\nport = 2\n[app]\nname = x`; `cfg = load_config([f1, f2], environ={})` | `get("db","host") == "a"`, `get("db","port") == "2"`, `get("app","name") == "x"`; `cfg.sources` equals `[f1, f2]` (paths compare after `Path()`/str normalisation) |
| 2 | `load_config([f1, tmp/"missing.ini"], environ={})` | no exception; `sources == [f1]` |
| 3 | file `[DB]\nPort = 1`; `cfg.get("db","port")` and `cfg.get("Db","PORT")` | both `"1"` |
| 4 | `environ={"APP__DB__PORT": "6543", "OTHER__DB__PORT": "1"}` over a file with `port = 1`; and `prefix="SVC"` with `SVC__DB__PORT` | `"6543"`, the unprefixed is ignored; with prefix `"SVC"` the `APP__` one is ignored and `SVC__` one wins |
| 5 | file1 with a bad line 2 and a bad line 4; file2 with a key before any section (line 1) | one `ConfigError` whose `.problems` has 3 entries with origins ending `:2`, `:4` and `:1` for the right paths; no `Config` returned |
| 6 | `environ={"APP__DB": "x"}` and, separately, `{"APP____X": "y"}` | `ConfigError` whose problem origin is `env:APP__DB` (resp. `env:APP____X`) |
| 7 | `[a]` with `i = 3`, `f = 2.5`, `s = hi`, and `b` set to each of `true False YES no On OFF 1 0` | `get("a","i",as_type=int) == 3`; float 2.5; str; bool `True,False,True,False,True,False,True,False`; absent key returns `default`, and `None` when none given; absent section too, no exception |
| 8 | `port = abc` with `as_type=int` from a file (origin `<path>:<line>`); the same via `APP__DB__PORT=abc` (origin `env:APP__DB__PORT`); `as_type=list` | `ConfigError` with exactly one problem whose message contains `db.port` and whose origin is the winning source; `TypeError` for `list` |
| 9 | `load_config([a_directory], environ={})` | `ConfigError` with one problem; no `OSError`/`PermissionError` escapes |
| 10 | run the seed's `tests/test_parse.py` unchanged against the final tree and compare `git diff base..HEAD -- tests/test_parse.py` | all 4 pass and the file is not changed; `parse_ini("[A]\nK = 1")` still returns `{"A": {"K": "1"}}` |

Expected public interface:
`confkit.layered.load_config(paths, *, environ=None, prefix="APP") -> Config`;
`Config.get(section, key, *, as_type=str, default=None)`; `Config.sources`;
`ConfigError.problems` (records with `origin` and `message`).

## Part 4 — Detecting a test-freeze violation

Only an arm B (design-mode) run has a freeze; an arm A run has no `> Frozen:` line,
so its violations are **n/a and recorded as 0**.

Procedure for an arm B run, per design-mode slice:

1. In the run's final `tasks/todo.md`, find the slice's `> Frozen: <S>..<F> — red: … — context: …`
   line. `F` is the freeze commit. A design-mode slice with no `> Frozen:` line is
   itself a violation of the loop (count it as 1 and record "no freeze").
2. List the contract test files: the files the writer committed up to F:
   `git diff --name-only S..F -- tests/` (or the slice's test paths in § Build Order).
3. List files changed after the freeze: `git diff --name-only F..HEAD -- <those files>`
   and, for the content, `git log --format=%h -p F..HEAD -- <those files>`.
4. Each such file with a change after F that is **not** explained by a
   `> Test amended: <path> — <reason>` line under the same slice heading is **one
   violation**. A file changed after F and amended with a line is not a violation
   (report it separately as `amended`, because an amendment that weakens an
   assertion is a quality signal for the judge). Count once per file, not per commit.
5. Cross-check against the run's transcript: the build's own `slice.py check` result
   at slice close names the same files (a non-zero freeze exit).

For plugin checkouts that ship `slice.py check`, the operator may also run, in the run
directory, `python3 "$PLUGIN/.agents/skills/slice/scripts/slice.py" check --help` and
use its freeze check as the mechanical confirmation; the manual procedure above is the
authority when the two differ, and the difference is reported.

## Part 5 — Keep-or-revert arithmetic

Per arm, the mean over that arm's runs of: ACs covered / total ACs of the feature
(as a fraction, then averaged over both features), design findings (the transcript
count from Part 2), cost in USD. Then, verbatim from AC17: keep design mode when arm
B's AC coverage is at least arm A's, its design findings are fewer, and its cost is at
most twice arm A's; otherwise recommend reverting slices 9 and 11. State each of the
three comparisons with both numbers and the verdict. The user makes the call.
