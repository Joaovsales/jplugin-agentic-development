## Plan: layered-config
> Spec: specs/layered-config.md

### Slice 1/1 — Layered loader
- [ ] Layered loader <!-- task-id: plan.specs-layered-config-md.layered-loader --> — Slice 1/1: `load_config`, `Config`, `ConfigError` with layering, environment overrides, gathered problems and typed `get`
  [ ] TDD: tests/test_layered.py § layering — a later file replaces a key of an earlier one and the rest survive; a missing path is skipped and absent from `sources`; names are case-insensitive -> confkit/layered.py (AC 1, 2, 3)
  [ ] TDD: tests/test_layered.py § environment — `APP__DB__PORT` overrides every file; unprefixed variables are ignored; a changed prefix is honoured -> confkit/layered.py (AC 4)
  [ ] TDD: tests/test_layered.py § problems — malformed lines across files and within one file arrive together in one `ConfigError` with `<path>:<line>` origins; `APP__DB` is a problem with origin `env:APP__DB`; a directory path is a problem not an `OSError` -> confkit/layered.py, confkit/parse.py (AC 5, 6, 9)
  [ ] TDD: tests/test_layered.py § typed-get — the four types convert, bool takes nine spellings, an absent key returns the default, a bad value raises `ConfigError` naming `section.key` with the winning origin, an unsupported type raises `TypeError` -> confkit/layered.py (AC 7, 8)
  [ ] TDD: tests/test_layered.py § parse-unchanged — the existing `parse_ini` behavior still holds -> confkit/parse.py (AC 10)
