---
implementation_paths:
  - .agents/skills/quality-gate/scripts/gate-integrity.py
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/build/SKILL.md
  - AGENTS.md
  - tests/test-gate-integrity.sh
  - tests/test-doc-conventions.sh
---

# Spec: Gate integrity — a slice cannot pass by editing the checks that judge it

> Origin: [#439](https://github.com/Joaovsales/jplugin-agentic-development/issues/439).
> Prior art: mitkox/esf @ e5567fb, `docs/adr/0007-defense-in-depth.md` § 4 (CheckGateIntegrity).

## Summary

`gate-integrity.py` compares every protected file — test runners, the
expected-failures list, CI workflows, lint and test configs — against its blob
at a base commit or tree by content hash, never by reading a diff. `/build` runs it at
Slice Close, where a protected change outside the slice's Surface stops the
slice as `GATE_TAMPERED`, and `/quality-gate` runs it as Phase 0, where it
becomes a MUST-FIX. Added expected-failure rows, new skip markers and deleted
assertions are always reported, and a check that cannot run says `not checked`.

## Behavior

`python3 .agents/skills/quality-gate/scripts/gate-integrity.py --base <rev>
[--spec <spec> [--slice <n>]...] [--repo <dir>]` checks the working tree of
`<repo>` (default: the current directory) against `<rev>`, a commit or a tree.
`gate-integrity.py --snapshot [--repo <dir>]` prints the tree id of the working
tree (tracked, untracked, not ignored) through a scratch index, touching
neither the real index nor working files; `/build` passes it back as `--base`.
The snapshot writes raw blobs and a tree into Git's object store, bypassing
clean filters even when a file is already modified at dispatch.
Tracked submodules retain their index's mode-160000 gitlink object IDs,
including when deinitialized; other unsupported filesystem types still refuse.

1. **Protected set.** The protected patterns are the default list below, every
   glob on a `Protected paths:` line below the `AGENTS.md` end marker
   (whitespace-separated, backticks stripped, several lines allowed), and the
   file named on the `Expected failures:` line — read from **both** the base's
   `AGENTS.md` and the current one, so deleting a declaration never unprotects
   what it named. Each base declaration the current `AGENTS.md` drops or
   retargets prints `GATE_TAMPERED AGENTS.md — <declaration> declared at
   <base8>, removed` (or `, now <target>`). Defaults:
   `.github/workflows/**`, `.gitlab-ci.yml`, `.circleci/**`, `.pre-commit-config.yaml`,
   `.eslintrc*`, `eslint.config.*`, `.prettierrc*`, `pyproject.toml`, `setup.cfg`,
   `tox.ini`, `pytest.ini`, `.flake8`, `ruff.toml`, `.ruff.toml`, `mypy.ini`,
   `.golangci.yml`, `.golangci.yaml`, `jest.config.*`, `vitest.config.*`.
   The candidate paths are the files in the base tree (`git ls-tree -r`) and the
   tracked and untracked, non-ignored files of the working tree (`git ls-files
   -c -o --exclude-standard`); a candidate is protected when a protected
   pattern matches it.
   Policy discovery resolves `AGENTS.md` through the same bounded,
   repository-contained link rules as gate contents, separately in the base
   tree and working tree. An outside, dangling or unsupported policy link is
   `not checked`, never an empty policy.
2. **Content comparison.** Each protected path's base blob id (from
   `ls-tree`) is compared with the git blob id of the raw working-tree bytes,
   computed in-process in the repository's object format. Hashing for the
   check never runs the clean filters the current `.gitattributes` names;
   snapshot creation uses `hash-object --no-filters` for regular files and
   `--stdin` for link text. The one normalization accepted is CRLF read as LF (a
   Windows checkout of an LF blob). An added, deleted or edited file differs.
   Because the working-tree bytes are hashed and the base blob is read from the
   object store, an `assume-unchanged` or `skip-worktree` bit, a change already
   committed after the base, a `diff.mnemonicPrefix` or `diff.noprefix` setting
   and a clean filter all leave the result unchanged. A symlink is compared
   twice: its own link text, and the content it resolves to — followed through
   the base tree on the base side and through the working tree on the current
   side — so an unchanged link never hides a changed referent. A link that
   leaves the repository, or resolves through an unsupported directory
   symlink, is `NOT_CHECKED`.
3. **Surface.** With `--spec` and `--slice`, the Surface is that slice's
   § Build Order Surface (the implicit one-slice plan reads
   `implementation_paths`); `--slice` repeated takes the union of the named
   slices (a parallel batch); with `--spec` alone it is the union of every
   slice's Surface; with neither it is empty. A Surface entry **declares** a
   protected path when it matches the path and the entry itself lies wholly
   inside a protected pattern — `tests/expected-failures.txt` and
   `.github/workflows/**` declare, a broad `tests/**` does not. For paths already
   protected by the defaults or base declarations, only those historical
   patterns set Surface precision: adding a broader current glob cannot
   authorize an earlier gate. Current declarations set precision only for
   newly protected paths, so unrelated added protection remains allowed.
4. **Report.** One line per result, then one summary line:

   | Line | When |
   |---|---|
   | `GATE_TAMPERED <path> — changed since <base8>, not declared in the surface` | a protected path differs and no Surface entry declares it |
   | `GATE_CHANGED <path> — changed since <base8>, declared in the surface` | a protected path differs and a Surface entry declares it |
   | `EXPECTED_FAILURE_ADDED <path> — <row>` | a non-comment, non-blank row of the expected-failures file is new since the base — always, declared or not; the row names the test file and the failing assertion |
   | `SKIP_ADDED <path>:<line> — <text>` | an added line of a test file that existed at the base carries a skip marker |
   | `ASSERTION_DELETED <path>:<base line> — <text>` | a line carrying an assertion was removed from such a test file and is not re-added anywhere in it |
   | `NOT_CHECKED <path> — <reason>` | one file could not be read or hashed |

   Summary: `gate-integrity: GATE_TAMPERED (<n>)`, `gate-integrity: findings (<n>)`,
   `gate-integrity: clean`, or `gate-integrity: not checked — <reason>`.
5. **Exit status.** `1` when any `GATE_TAMPERED` line printed; otherwise `3`
   when the check could not run or any `NOT_CHECKED` line printed; otherwise
   `0`, with or without findings. `2` is bad usage (argparse, an unreadable spec
   or an unknown slice).

**Skip markers** are `.skip`, `.only`, `@skip`/`@pytest.mark.skip`/`skipif`/`xfail`,
`unittest.skip`, `pytest.skip(`/`pytest.xfail(`, `@Disabled`, `@Ignore`,
`#[ignore]`, `xit(`/`xdescribe(`/`xtest(`/`fit(`/`fdescribe(`, `t.Skip(`, and a
line starting with `skip ` (this repository's `tests/lib.sh`). **Assertions**
are lines carrying `assert…`, `expect(`, `t.Error`/`t.Fatal`, `require.` or
`should`. A **test file** has a `test`, `tests`, `spec` or `__tests__`
directory segment, or a name `test_*`, `test-*`, `*_test.*`, `*.test.*`,
`*.spec.*` or `*Test.*`.

### In the skills

- `/build` records a **gate base** with `--snapshot` before each dispatch (a
  parallel batch: once), and § *Slice Close* runs the script with `--base
  <gate-base> --spec <spec> --slice <n>` (one `--slice` per batch slice) next to
  `slice.py check`, so an earlier slice's declared protected change is not
  blamed on a later one. Exit 1 stops the slice: the header
  stays `[ ]`, the handover records `unfinished: GATE_TAMPERED <paths>`, and the
  slice stays out of the done set, so nothing blocked by it becomes ready. Exit
  3 is recorded as `gate integrity: not checked — <reason>` in the handover's
  `> Surface:` line, never as clean. Every finding line goes on that line too.
- `/quality-gate` **Phase 0 — Gate Integrity** runs the script with the
  merge-base from *Scope* and the spec when one exists, before Phase 1.
  `GATE_TAMPERED` is `[MUST-FIX | confidence: 100 | autofix_class: manual |
  owner: human]`, `EXPECTED_FAILURE_ADDED` is `[SHOULD-FIX | confidence: 100 |
  manual | human]` and `GATE_CHANGED` is `[NITPICK | confidence: 100 | advisory |
  human]`. `SKIP_ADDED` and `ASSERTION_DELETED` are pattern matches, so each
  starts as `[SHOULD-FIX | confidence: 50 | manual | human]` and gets one
  verification read of its hunk: a real skip or a real deletion rises to 75, and
  a marker that is test data inside a string is refuted and dropped with a
  word. Every finding goes to `Reported, not applied` and the receipt's
  `unresolved`; exit 3 is named in `Not checked:`.

## Inputs

- `--base <rev>`: any revision `git rev-parse` resolves to a commit or a tree;
  a value starting with `-` is never read as an option.
- `--spec`, `--slice`: a spec with `implementation_paths` frontmatter and an
  optional § Build Order.
- `AGENTS.md` below `<!-- jplugin-agentic-development:end -->`: `Protected paths:`
  and `Expected failures:` lines. No `AGENTS.md` means the defaults alone.

## Outputs

Result lines and a summary on stdout, `NOT_CHECKED` reasons included; the exit
status above. Checking writes nothing; `--snapshot` writes Git objects only.

## Edge Cases

- `assume-unchanged` hides an edit from `git diff` and `git status`: still `GATE_TAMPERED`.
- An edit committed after the base, with a clean working tree: still `GATE_TAMPERED`.
- `diff.mnemonicPrefix=true` or `diff.noprefix=true`: results are identical.
- A protected file deleted, or a new file under a protected glob: `GATE_TAMPERED`.
- A protected path that is a symlink: an unchanged link and referent are clean; a retargeted link, or an unchanged link whose referent changed, is `GATE_TAMPERED`, and rows added behind a linked expected-failures file are reported; a link out of the repository is `NOT_CHECKED`.
- A clean filter in `.gitattributes` that restores the original bytes: still `GATE_TAMPERED`.
- A CRLF checkout of an LF runner: unchanged.
- `Protected paths:` or `Expected failures:` removed or retargeted in `AGENTS.md`: the base declaration still protects, and the removal is `GATE_TAMPERED AGENTS.md`.
- `AGENTS.md` unreadable: `not checked`, exit 3.
- Slice 2 closes after slice 1 changed a protected file slice 1 declared: judged against slice 2's gate base, it is not blamed.
- The base does not resolve, or the directory is not a git work tree: `gate-integrity: not checked — <reason>`, exit 3.
- An invalid glob on a `Protected paths:` line: `not checked`, exit 3, naming the glob.
- A test file deleted outright: one `ASSERTION_DELETED` line per assertion it held.
- An assertion moved within its file (removed and re-added identically): no finding.
- An expected-failures row only reordered: no `EXPECTED_FAILURE_ADDED` line.
- A row added to the expected-failures file inside a declared Surface: `GATE_CHANGED` plus `EXPECTED_FAILURE_ADDED`.

## Interfaces

### gate-integrity.py

- **Path:** `.agents/skills/quality-gate/scripts/gate-integrity.py`
- **Hides:** the protected-set resolution (defaults, `AGENTS.md` declarations), blob-vs-hash comparison, the surface-declaration rule and the skip/assertion patterns.
- **Interface:** `gate-integrity.py --base <rev> [--spec <spec> [--slice <n>]...] [--repo <dir>]` → result lines, exit 0/1/3; `--snapshot [--repo <dir>]` → a tree id, exit 0/3.
- **Alternative considered:** a `slice.py check --gate` flag. `slice.py` is already 865 lines and `/quality-gate` has no slice; one script both callers share keeps the rules in one place.
- **Depth:** one call resolves the protected set, hashes every candidate, reads the surface and classifies every change.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where does the check live? | A new `quality-gate/scripts/gate-integrity.py`, called by `/build` Slice Close and `/quality-gate` Phase 0 | assumed | `/quality-gate` owns review checks; both callers share one implementation; `slice.py` is past the file-size bar |
| 2 | How is a change detected? | `git hash-object` of the working file against the base tree's blob id | assumed | the issue's mechanism; reading no diff output makes assume-unchanged, committed changes and diff config irrelevant |
| 3 | What counts as naming a protected file in the Surface? | An entry that matches the path and lies wholly inside a protected pattern | assumed | a broad `tests/**` would otherwise silently whitelist the runner; the issue asks the slice to *name* the file |
| 4 | Which defaults? | CI workflow and lint/test-config files common across ecosystems, plus the declared expected-failures file; project runners are declared with `Protected paths:` | assumed | generic defaults cannot know a project's runner; this repository declares `tests/run.sh tests/affected.sh tests/lib.sh` |
| 5 | Severity of non-tamper results at `/quality-gate` | `EXPECTED_FAILURE_ADDED` SHOULD-FIX at 100; `SKIP_ADDED` and `ASSERTION_DELETED` SHOULD-FIX at 50 with one verification read; `GATE_CHANGED` NITPICK; owner human throughout | assumed | the row and the declared change are exact facts; the skip and assertion patterns also match test data (dogfooding flagged this repository's own fixtures), so a reviewer confirms them before they count toward HOLD |
| 6 | Phase numbering | A new Phase 0 before Phase 1 | assumed | the receipt's reviewer entries are keyed by phases 1–5; renumbering would break receipts and pins for no gain |
| 7 | Exit status of "cannot run" | `3`, distinct from clean `0`, tampered `1` and usage `2` | assumed | callers must be able to tell `not checked` from clean without parsing prose |
| 8 | Whose `AGENTS.md` declares the policy? | The union of the base's and the current; a dropped or retargeted base declaration is `GATE_TAMPERED AGENTS.md` | review of PR #447 | the policy must not be able to remove itself; a human decides a protection change |
| 9 | How are working bytes hashed? | In-process git blob ids of the raw bytes, CRLF-as-LF accepted; symlinks compared by link text and by resolved content | review of PR #447 | `git hash-object` runs mutable clean filters; link identity alone hid a changed referent |
| 10 | Which base does Slice Close use? | A per-slice gate base from `--snapshot` at dispatch; `/quality-gate` Phase 0 keeps the merge-base | review of PR #447 | the session base blamed slice 2 for slice 1's declared change; slices are not committed one by one, so the snapshot is a tree, not HEAD |

## Acceptance Criteria

- AC1: A protected file changed outside the Surface stops the slice as `GATE_TAMPERED` (exit 1), including when `git diff` against the base prints nothing; `/build` § *Slice Close* leaves the header `[ ]` on exit 1.
- AC2: Every row added to the expected-failures file is reported as `EXPECTED_FAILURE_ADDED`, naming the test file and the assertion message, whether or not the Surface declares the file.
- AC3: A new skip marker (`skip`, `xfail`, `.only`, `@Disabled`) in a test file that existed at the base produces `SKIP_ADDED`, and an assertion removed from such a file produces `ASSERTION_DELETED`.
- AC4: A check that cannot run prints `gate-integrity: not checked — <reason>` and exits 3, never 0; `/build` and `/quality-gate` record it as not checked.
- AC5: Fixtures cover an `assume-unchanged` edit, a committed edit and `diff.mnemonicPrefix=true`, and each is detected.
- AC6: A protected file named in the Surface yields `GATE_CHANGED` and exit 0, while a broad Surface glob such as `tests/**` does not declare it.
- AC7: `/quality-gate` runs the check as Phase 0 and maps `GATE_TAMPERED` to a MUST-FIX finding; `AGENTS.md` declares this repository's protected runners below the end marker.

## Implementation Paths

- `.agents/skills/quality-gate/scripts/gate-integrity.py` — the check.
- `.agents/skills/quality-gate/SKILL.md` — Phase 0 and its finding mapping.
- `.agents/skills/build/SKILL.md` — the Slice Close call and the stop on exit 1.
- `AGENTS.md` — this repository's `Protected paths:` line below the end marker.
- `tests/test-gate-integrity.sh` — fixture repos for AC1–AC6.
- `tests/test-doc-conventions.sh` — pins the skill wiring for AC1, AC4 and AC7.

## Build Order

Sizing: 3 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 3: four systems — the two callers, `AGENTS.md` and the doc pins are one wiring contract, and splitting them leaves a half-wired gate.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Content-hash tamper check | The script resolves the protected set, hashes each candidate against its base blob and classifies changes against the Surface | `.agents/skills/quality-gate/scripts/gate-integrity.py`, `tests/test-gate-integrity.sh` | — | 5, 6 | `bash tests/test-gate-integrity.sh` | 2 files · 2 systems · 2 ACs |
| 2 | Weakening findings | Added expected-failure rows, new skip markers, deleted assertions and the not-checked outcome | `.agents/skills/quality-gate/scripts/gate-integrity.py`, `tests/test-gate-integrity.sh` | 1 | 2, 3, 4 | `bash tests/test-gate-integrity.sh` | 2 files · 2 systems · 3 ACs |
| 3 | Skill wiring | `/build` Slice Close stops on `GATE_TAMPERED`, `/quality-gate` Phase 0 maps results to findings, `AGENTS.md` declares this repository's runners | `.agents/skills/build/SKILL.md`, `.agents/skills/quality-gate/SKILL.md`, `AGENTS.md`, `tests/test-doc-conventions.sh` | 2 | 1, 7 | `bash tests/test-doc-conventions.sh` | 4 files · 4 systems · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/gate-integrity.md`.
Plan: `## Plan: Gate integrity` in `tasks/todo.md`, 3 slices, ready set <1>.
Files: .agents/skills/quality-gate/scripts/gate-integrity.py, .agents/skills/quality-gate/SKILL.md, .agents/skills/build/SKILL.md, AGENTS.md, tests/test-gate-integrity.sh, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: detect by hash-object against the base blob, never by parsing a diff (D2); a Surface entry declares a protected path only when it lies wholly inside a protected pattern (D3); exit 3 means not checked (D7); the quality-gate check is Phase 0 (D6).
```
