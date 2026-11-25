# Project-owned visual validator

Issue: #490. Startup ownership filtering shipped in #491. The automated mirror is tracked in #492.

## Behavior

A project can declare one project-relative Python script in
`.claude/visual-validator`. The shared `validate --output` CLI runs that
script with the same arguments and returns its status. An absent declaration
selects generic manifest validation. An invalid or incomplete declaration
fails validation. The Python capture API is unchanged.

## Acceptance criteria

- AC-1. The standard CLI reads the generic manifest without a declaration.
- AC-2. A declared project script receives the existing arguments and its exit status is propagated.
- AC-3. Missing, outside and empty declarations fail with a diagnostic.

## Build Order

One slice. Add and document CLI opt-in, prove the default and explicit
contracts, then bump the plugin manifest.
