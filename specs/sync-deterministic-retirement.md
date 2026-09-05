---
implementation_paths:
  - .agents/skills/sync/**
  - .claude/skills/sync/**
  - tests/test-sync-retirement.sh
---

# Spec: Deterministic Retirement in `/sync`

> Issue: [#89](https://github.com/Joaovsales/jplugin-agentic-development/issues/89)
> Task: `sync.deterministic-retirement`

## Behavior

`/sync` copies a fixed set of harness paths from this template into a downstream
project. Additions and modifications already arrive mechanically, through
`git checkout workflow/$BRANCH -- <paths>`. **Deletions do not.** A file that
exists in the project but not in the template is either *retired upstream* or
*project-specific*, and today nothing in either repository answers which — so the
answer is re-derived by a model on every run. Two runs against the same template
commit can therefore produce different trees.

This feature replaces that judgement with recorded data.

A downstream project owns a `.claude/sync-keep` file: newline-delimited glob
patterns naming the paths under syncable roots that belong to the project. A
script computes the retirement set as pure set arithmetic —

```
retire = (project paths under syncable roots)
       − (template paths under the same roots)
       − (paths matching a sync-keep pattern)
```

— reports it in full, and with `--apply` deletes exactly that set. Nothing is
classified at run time. Given the same template revision, the same project tree,
and the same `sync-keep`, the retirement set is identical on every run and from
every project branch.

A project with no `.claude/sync-keep` is in **bootstrap** state, where that
subtraction cannot run: nothing has recorded what is project-specific. Bootstrap
is not therefore empty, because the template's history answers a narrower
question on its own —

```
retire (bootstrap) = { p ∈ (project − template)
                     : hash(project file at p) ∈ (blobs the template ever
                                                  held at p) }
```

A file that is **byte-identical** to something the template once shipped at that
same path was retired upstream: it is template content, not this project's, so
deleting it needs no human classification. That is a record, not a judgement,
which is the same standard the `sync-keep` arithmetic meets.

The comparison is on **content, not on the path**, and the difference is not
academic. `.claude/hooks/` is a syncable root and `pre-commit.sh` is a name a
template and a project both reach for, so path membership alone would delete a
file this project wrote itself and never synced. It also protects the case git
cannot: a synced file the project later **edited** hashes to something no
template commit produced, so it falls out of the retirement set — including when
the edit is still uncommitted, which `git checkout` could never bring back.

Hashing the working tree rather than the index is what makes that last case work.

This matters because the mechanism being replaced — a hardcoded
`for retired in tdd deslop simplify verify-e2e` loop — deleted unconditionally.
Without provenance, a project that never promotes its candidate would keep every
retired skill forever, making the new design strictly weaker than the old one for
exactly the projects least likely to notice.

Everything the template **never** carried is held back: the script retires none of
it and emits a candidate allowlist for a human to review. Confirming that
candidate is the single point at which intent gets written down; after that it is
data.

`.claude/sync-keep` is never synced. It needs no new exclusion mechanism to
achieve that, and the reason is structural rather than a list to keep in step:
every syncable root under `.claude/` is a subdirectory, while `sync-keep` is a
file directly under `.claude/`, so it lies outside all of them by shape. This
spec documents that property rather than adding one.

### Scope boundary

Only the **deletion** half of `/sync` becomes mechanical. Additions and
modifications keep their existing `git checkout` path, which is already
deterministic. The interactive choices `/sync` already offers — the file-picking
menu, the `.claude/commands/` legacy migration, the Deployment Targets migration —
are human decisions, not model guesses, and are unchanged.

The retirement pass is deliberately **not** part of the file-picking menu. It runs
in dry-run during the change summary so its output is visible before any write,
and applies in full for both *all changes* and *pick files*. Retirement is defined
by `sync-keep`, not by picking; a user who wants to keep a path adds it to
`sync-keep`, which is the entire point of the mechanism. *Preview only* and
*abort* apply nothing.

## Inputs

- `--from-ref <ref>` — template inventory read from a git ref
  (`git ls-tree -r --name-only <ref> -- <roots>`). The git-remote mode.
- `--from-dir <path>` — template inventory read from a local checkout: through
  `git ls-files` when the checkout is a repository, which is how `/sync` obtains
  it, and by walking the directory otherwise. Reading through git is what makes
  this mode agree with `--from-ref`; a bare walk would count gitignored residue
  as template content. The manual-diff mode. Exactly one of the two is required.
- `--repo <path>` — project root; defaults to the working directory.
- `--apply` — perform deletions. Absent, the run is a dry run.
- `.claude/sync-keep` — the project's allowlist. Blank lines and `#` comments are
  ignored. Each remaining line is one glob pattern.
- The `## Syncable Paths` doc block in `.agents/skills/sync/SKILL.md` — the
  canonical root list. The script *parses* this block rather than carrying a
  copy, so it becomes a consumer of the one source `tests/test-syncable-paths.sh`
  already pins, not an eighth hand-maintained duplicate of it.

A syncable root must be a direct subdirectory of `.agents/` or `.claude/` —
`.agents/skills/`, `.claude/hooks/`, and so on. The doc block is read from the
template, which is a remote repository or a local directory, so it is untrusted
input to a file-deleting operation: an unconstrained block naming `src/` would
delete the project's source, and `.claude/` would sweep in the never-sync files
including `sync-keep` itself. Staying inside the repository is not sufficient,
because all of those paths already are. A root failing this shape is an error.

Glob semantics match the spec `implementation_paths` contract: case-sensitive,
whole-path, `*` matches any run of characters except `/`, `?` matches exactly one
character except `/`, `**` matches any run including `/`. No other glob syntax is
accepted.

## Outputs

A report on stdout, then — under `--apply` only — deletions on disk.

```
sync retirement — source: workflow/master, roots: 7
  retire: .agents/skills/tdd/SKILL.md
  retire: .claude/hooks/pre-push-guard.sh
  kept:   .agents/skills/ai-video-essay/SKILL.md (matched .agents/skills/ai-video-essay/**)
  mode:   dry-run (no changes written)
```

- Every retire path is listed **in full**, never truncated. The progressive-
  disclosure cap that bounds other reports in this repo is a readability
  optimisation; here the list *is* the record of what is about to be destroyed,
  and abbreviating it would hide exactly what the report exists to show.
- Every allowlist hit is reported with the pattern that matched it, so a
  surviving path is traceable to the line that saved it.
- Directories emptied by the deletions are pruned.

Exit codes: `0` success · `1` failure (unreadable ref, missing root, invalid
pattern, invalid syncable root, deletion failure) · `2` usage error.

Nothing is deleted on any non-zero exit **decided before the apply step** — every
validation failure above is one of those. The single exception is an I/O error
part-way through the deletion loop: files already removed stay removed. The run
still exits `1`, and it reports `applied (N deleted, M failed)` followed by each
path it could not delete, so the record always matches the disk.

Pruning an emptied directory can fail independently of the deletion that emptied
it — the file is gone either way. That is reported as `not pruned` in the
outcome line with an `UNPRUNED:` line per directory, counted separately from a
failed deletion so a leftover directory never reads as a file that survived. A
prune failure must not abort the run: doing so would discard the record of
everything already deleted, which is the one thing this tool cannot afford to
lose.

**The template checkout is untrusted input, including its git configuration.**
`--from-dir` names a tree the project did not write, and git executes commands
named by that repository's own config (`core.fsmonitor` on `ls-files`). The
checkout is same-uid, so `safe.directory` does not fire, and the read happens
during the Step 3 dry run — before the user approves anything and without
`--apply`. Every git invocation therefore pins the exec-capable knobs off on the
command line, where `-c` outranks repository config, and ignores system and
global config.

## Edge Cases

- **No `.claude/sync-keep`** — bootstrap. Reports `bootstrap: required` and
  splits the project-only paths by provenance: those the template has ever
  carried are retired as template content, and only those it never carried are
  listed as candidates. Under `--apply` it writes `.claude/sync-keep.candidate`,
  never `.claude/sync-keep` itself; promoting the candidate is the human's
  confirming act. Additions and modifications still sync normally.
- **Provenance unreadable** — the template's history could not be read. Reports
  `provenance: unavailable (<reason>)` and retires *nothing*, holding every
  project-only path as a candidate rather than reading "I cannot tell" as
  "project-specific". The reason is git's own, carried out of the probe and
  flattened to one printable line, and the remediation hint belongs to the
  reason rather than being appended to all of them: a truncated clone, a ref
  that does not resolve and an unreadable object need different responses, and
  only the first is fixed by deepening a clone.
- **Truncated template history** — detected by whether the revision's root
  commit *records a parent that is absent*, which is what a shallow graft looks
  like at any depth. A commit count only ever caught depth 1, so a `--depth 5`
  clone silently produced a different retirement set from the same commit SHA —
  the exact non-determinism this feature exists to remove.
- **A synced file the project edited** — held as a candidate, never retired. The
  edit is what makes it the project's.
- **A project's own file at a path the template once used** — held as a
  candidate. A shared filename is a collision, not provenance.
- **Bootstrap `--apply` whose candidate write fails** — for any reason other
  than the file already existing (unwritable directory, read-only mount,
  ENOSPC), the failure is folded into the deletion report rather than raised
  through it, so the run still lists every path it removed and exits non-zero.
- **A dangling symlink at the candidate path** — refused. `os.path.exists`
  reports False for one while `open(path, "w")` follows it and creates the
  target, so the check is `lexists`.
- **Shallow *project*, complete template ref** — provenance is available. Depth
  is measured on the revision being read, not on the repository holding it, so a
  project that is itself a `--depth 1` checkout (the CI default) still retires.
  Measuring the repository instead silently disabled retirement in `--from-ref`,
  the mode the skill prescribes.
- **Bootstrap `--apply` with a candidate already present** — exits 1 having
  deleted nothing. The refusal to overwrite a file a human was asked to edit is
  a *precondition*, checked before the deletions rather than after them: a guard
  that fires after the destruction it guards reports nothing about what was
  destroyed.
- **Empty `.claude/sync-keep`** — a recorded, deliberate "nothing is
  project-specific". Distinct from absent, and it permits deletion.
- **Invalid pattern** — absolute, `..`-traversing, backslash-separated, using
  unsupported glob syntax, or resolving outside every syncable root. Reported
  with the offending pattern and its line, non-zero exit, nothing deleted. A
  pattern outside every syncable root can never protect anything, so accepting it
  would silently record intent that has no effect. "Outside every syncable root"
  is judged against the roots the doc block **declares**, not the subset the
  template currently has files under — otherwise a root emptied upstream turns a
  project's correctly recorded intent into a fatal error and blocks every
  unrelated retirement.
- **File roots** — `CLAUDE.md` and `.claude/settings.json` are files, not
  directories. Retirement is undefined for them and they are excluded from the
  scan; they are already handled by the existing checkout step.
- **A syncable root absent from the project** — treated as empty, not an error.
  A project that never received `.claude/browsers/` has nothing to retire there.
- **A syncable root absent from the template** — an error. The template is the
  authority on what the roots contain; a missing root means the ref or checkout
  is wrong, and proceeding would retire the project's entire copy of it.
- **A trailing-slash pattern** — `.agents/skills/mine/` reaches a syncable root
  but matches no file, so it protects nothing. Refused, naming the `**` form
  that works. This is the most natural thing a human writes, and accepting it
  silently retires exactly what it was written to save.
- **A pattern that matches nothing this run** — reported as `unmatched:`, not an
  error: the path it names may not exist yet. It is also the state a stale
  allowlist is in immediately before it stops protecting something.
- **A candidate path containing glob metacharacters** — the pattern language has
  no escape syntax, so such a path cannot be expressed exactly. `sync-keep.candidate`
  writes it as a comment naming the problem rather than as a pattern that would
  either over-match or fail validation on a line the tool wrote itself.
- **A root retired upstream** — once a directory leaves the doc block it is no
  longer scanned, so the project keeps its copy indefinitely. The retirement set
  is defined only within the roots the template currently declares; removing a
  whole root needs a one-off manual deletion. Filed as a follow-up.
- **Project on a stale branch** — a branch carrying skills that the project's
  `main` already dropped retires them like any other project-only path. The
  template, not the project branch, is the authority.

- **A candidate path the reader would strip or split.** `read_keep_patterns`
  strips each line, so a path with surrounding whitespace round-trips into a
  pattern that cannot match it, and a path containing a line break splits into a
  second, live rule at column 0. Both are written as `# UNEXPRESSIBLE` comments
  naming the path — **every** line of it, since commenting only the first lets
  the remainder escape back to column 0 — alongside the glob-metacharacter and
  backslash cases: a rule that looks like protection and silently protects
  nothing is worse than a refusal to write one. The rejected set is derived from
  what `validate_pattern` refuses rather than restated, which is how backslash
  drifted out of it once already.
- **A syncable root whose segment is `.`, `..` or a glob.** Rejected by the root
  validator itself, not by the downstream check that the template contains files
  under every root. The downstream check happens to refuse these too, because
  git normalises its output — but relying on that leaves whole-repo deletion one
  refactor away, so the constraint lives in the shape the design depends on.

## Acceptance Criteria

- Running `/sync` twice against an unchanged template leaves a byte-identical
  tree on the second run, and the second run reports zero retirements.
- A file retired upstream is removed from the project without a human
  classifying it.
- A path listed in `.claude/sync-keep` survives a sync that would otherwise
  delete it, and is reported with the pattern that matched it.
- A project-only path not in `sync-keep` is reported before deletion, never
  deleted silently; the default run reports without deleting at all.
- Syncing the same project from two different branches yields the same set of
  harness paths.
- `.claude/sync-keep` is documented as non-syncable in `SKILL.md` § Syncable
  Paths, in both the canonical and compatibility copies.
- A project with no `.claude/sync-keep` still retires files that are
  byte-identical to something the template's history shows it shipped at that
  path, holds everything else — including customised, uncommitted, and
  same-name-different-file cases — as a candidate, and is told how to bootstrap
  the allowlist. When that history cannot be read it retires nothing and says why.
- Bootstrap `--apply` that cannot write its candidate file deletes nothing, and
  any run that deletes reports every path it removed even when part of it failed.
- An invalid `sync-keep` pattern fails loudly, names the pattern, and deletes
  nothing.
- `--from-ref` and `--from-dir` produce the same retirement set for the same
  template content.
- The syncable roots the script scans come from the `## Syncable Paths` doc
  block, so the block stays the single source the drift test already pins.

## Implementation Paths

- `.agents/skills/sync/SKILL.md` — canonical skill. Owns the `## Syncable Paths`
  doc block the script parses, documents `.claude/sync-keep` in the never-sync
  list, and adds the retirement pass to the procedure.
- `.agents/skills/sync/scripts/sync-retire.py` — the mechanism. Stdlib-only
  Python 3; computes, reports, and applies the retirement set.
- `.claude/skills/sync/**` — byte-identical Claude Code compatibility copy of the
  above, pinned by `tests/test-skill-parity.sh`.
- `tests/test-sync-retirement.sh` — the behavioral suite for every criterion
  above.

## Deferred

Two limits are deliberate, each filed rather than folded in:

- The syncable-path list is still enumerated by hand across seven regions in
  three files. This spec makes the script an eighth *consumer* of the canonical
  block instead of an eighth copy, but does not collapse the other six.
- `_pattern_to_regex` / `match_path` are re-implemented here rather than shared
  with `.agents/skills/wrap-up-session/scripts/spec-reconcile.py`, which has the
  same three-token semantics. That file's hyphenated name makes it importable
  only through `importlib`, and the two validators have different contracts
  (`sync-keep` additionally requires a syncable root). Extracting a shared module
  would widen this change beyond the routed radius.

Review raised four more, all filed and none fixed here:

- A `sync-keep` pattern naming a root the template has since dropped is a hard
  exit `1` that blocks every unrelated retirement, and blames the project's file
  for an upstream change (`sync.stale-root-blocks-retirement`).
- Runs of `**` / `*?` compile to adjacent unbounded quantifiers that backtrack
  catastrophically. Input is the project's own never-synced `sync-keep`, and the
  same shape exists in `spec-reconcile.py` — so the fix belongs with the shared
  matcher, not ahead of it (`glob-matcher-redos`).
- Step 6 asks the user to commit before Step 6.4 deletes, leaving the deletions
  and the bootstrap candidate uncommitted. Pre-existing ordering, amplified now
  the set is computed rather than four fixed paths
  (`sync.retirement-lands-after-commit`).
- Nothing bounds the size of the retirement set
  (`sync.retire-blast-radius-cap`, already filed).
