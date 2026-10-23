---
implementation_paths:
  - confkit/layered.py
  - confkit/parse.py
  - tests/test_layered.py
---

# Layered configuration

## Behavior

An application reads settings from several INI files (defaults, then a system file,
then a user file) and from environment variables. Later sources override earlier
ones one key at a time. The caller gets one `Config` object and asks it for values;
it never learns which file a value came from unless something is wrong with it.

The existing `confkit/parse.py` parses one document (`parse_ini`, `ParseError`) and
must keep working exactly as it does. The new module `confkit/layered.py` adds
`load_config` and `Config`, and `ConfigError`.

## Inputs

- `load_config(paths, *, environ=None, prefix="APP")`: `paths` is a list of file
  paths (str or `pathlib.Path`) from lowest to highest priority; `environ` is a
  mapping of environment variables (default `os.environ`); `prefix` names the
  variables that count.
- Environment variables are named `<PREFIX>__<SECTION>__<KEY>`, for example
  `APP__DB__PORT=6543` sets `[db] port`. Names of sections and keys are
  case-insensitive everywhere: they are stored lower-case.
- `Config.get(section, key, *, as_type=str, default=None)` where `as_type` is one of
  `str`, `int`, `float`, `bool`.

## Outputs

- `load_config` returns a `Config`. `Config.sources` lists, in order, the paths that
  existed and were read.
- `Config.get` returns the value converted with `as_type`, or `default` when the
  section or key is absent.
- Booleans accept `true`, `false`, `yes`, `no`, `on`, `off`, `1`, `0`, in any case.
- `ConfigError` is the one error type callers catch. It has `.problems`, a list of
  `Problem(origin, message)` records where `origin` reads `<path>:<line>` for a file
  and `env:<VARIABLE>` for an environment variable.

## Edge Cases

- A path that does not exist is skipped; it is not an error and not in `sources`.
- A path that exists but cannot be read as text (a directory, bad encoding) is
  reported as a problem, not skipped.
- Every malformed line in every file is reported in one `ConfigError` raised after
  all files were read, so a user fixes them in one pass. The first bad line in a
  file does not hide the later ones in it or in other files.
- A key before any section header is a problem; an unparseable line is a problem.
- An environment variable that starts with `<PREFIX>__` but does not name both a
  section and a key (`APP__DB`, `APP____X`) is a problem, reported with its origin.
  Variables without the prefix are ignored.
- A value that cannot be converted (`port = abc` with `as_type=int`) raises
  `ConfigError` from `get`, with one problem naming `section.key` in its message and
  the origin of the winning value.
- `get` of an absent key never raises.
- A repeated key within one file: the later one wins.
- An unsupported `as_type` (anything but the four) raises `TypeError`; that is a
  programming error, not a configuration problem.

## Interfaces

### Layered loader

- **Path:** `confkit/layered.py`
- **Hides:** reading and parsing each file, the merge order, case folding, where each
  value came from, the environment naming scheme, and how problems are gathered.
- **Interface:** `load_config(paths, *, environ=None, prefix="APP") -> Config` and
  `Config.get(section, key, *, as_type=str, default=None)`.
- **Alternative considered:** `Config` exposing the merged dicts and separate
  `get_int`, `get_bool` helpers; it lost because callers would re-derive conversion
  and missing-key handling in every call site.
- **Depth:** one call reads, validates and merges every source; one `get` call finds,
  converts and defaults; the caller handles one error type and no missing-file or
  missing-key exception.

## Decisions

| # | Question | Decision | Source | Why |
|---|----------|----------|--------|-----|
| 1 | Missing file? | skipped silently, absent from `sources` | user | optional layers are the normal case |
| 2 | Missing key? | `get` returns `default`; no exception | user | callers should not wrap lookups in try |
| 3 | Several malformed lines? | all reported together in one `ConfigError` | user | fix everything in one pass |
| 4 | Name case? | case-insensitive, stored lower-case | user | users mistype case |
| 5 | Env naming? | `<PREFIX>__<SECTION>__<KEY>` | user | unambiguous split on the `__` separator |
| 6 | Does `parse_ini` change? | no; its signature, errors and case-keeping stay; new parsing support needed by the loader may be added beside it in `parse.py` | user | other callers exist |
| 7 | Typed access? | `as_type` one of str, int, float, bool | user | covers the settings in use |

## Acceptance Criteria

- AC1: Two files layered in order: a key in the later file replaces the same key in the earlier file, other keys of both survive, and `Config.sources` lists both paths in order.
- AC2: A path that does not exist is skipped without error and is not in `Config.sources`.
- AC3: Section and key names are case-insensitive: `[DB] Port = 1` is read by `get("db", "port")`.
- AC4: `APP__DB__PORT=6543` in `environ` overrides the value from every file; a variable without the prefix is ignored; `prefix` is honoured when changed.
- AC5: Malformed lines across two files and several lines in one file are all reported in one `ConfigError`, whose `.problems` each carry an `origin` of `<path>:<line>` and a message; no partial `Config` is returned.
- AC6: An environment variable `APP__DB` (prefix but no key) is reported as a problem with origin `env:APP__DB`.
- AC7: `get` converts with `as_type` for `int`, `float`, `bool` (the nine accepted spellings, any case) and `str`; an absent section or key returns `default`.
- AC8: A value that cannot be converted raises `ConfigError` from `get` with one problem whose message names `section.key` and whose origin is that of the winning value (`<path>:<line>` or `env:<VARIABLE>`); an unsupported `as_type` raises `TypeError`.
- AC9: A path that exists but cannot be read (a directory) is a problem in the `ConfigError`, not a crash with an `OSError`.
- AC10: `confkit.parse.parse_ini` and `ParseError` behave as before: the existing parse tests still pass unchanged.

## Implementation Paths

- `confkit/layered.py` (new), `tests/test_layered.py` (new)
- `confkit/parse.py` (may gain a helper the loader needs; `parse_ini` itself unchanged)

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Layered loader | `load_config`, `Config`, `ConfigError` with layering, environment overrides, gathered problems and typed `get` | `confkit/layered.py`, `confkit/parse.py`, `tests/test_layered.py` | — | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `python scripts/run_tests.py` | 3 files · 1 system · 10 AC |
