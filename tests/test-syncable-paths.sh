#!/bin/bash
# tests/test-syncable-paths.sh — the syncable-path set is enumerated by hand in
# four places; this pins them equal, and pins skill assets inside them.
#
# WHY THIS EXISTS
#
# `/sync` decides what a downstream project receives from this template. That
# decision is not stored anywhere as data — it is retyped as a list of path
# arguments in four regions across two files:
#
#   1-3. .agents/skills/sync/SKILL.md   § Syncable Paths doc block,
#                                       the `git diff --stat` command,
#                                       the full `git diff` command
#     4. .claude/hooks/session-start.sh the template-drift check
#
# Hand-maintained copies of one list drift, and had already: the
# session-start.sh drift check omitted `.agents/agents`, so a project whose
# agent personas changed upstream was never told to run `/sync`. Nobody noticed
# because nothing compared the lists. A convention asking people to update
# several regions is not a mechanism; this test is.
#
# A doc-block row whose right-hand column begins `RETIRED` is a root `/sync`
# scans for retirement but never checks out (specs/claude-plugin-manifest.md
# § Syncable Paths block). It is pinned present in the block and absent from
# every checkout list, and the CI mirror is pinned to have stopped copying it.
#
# INVARIANT 2 — assets a skill names must live where /sync ships them.
#
# The omission above is the cheap failure. The expensive one is a skill that
# instructs an agent to run a script the downstream project never received:
# `scripts/bootstrap-worktree.sh` sat at the repo root, outside every syncable
# path, while four skills documented it as the worktree fallback. It worked in
# this repo and existed nowhere else. So: every asset path a skill names, once
# resolved, must be a descendant of a declared syncable path.
#
# Scope boundary — this test checks DISTRIBUTION (does the resolved file land
# somewhere /sync ships?). Whether a named path resolves at all is
# `test-skill-references.sh`'s invariant, not this one. A token that resolves to
# nothing is skipped here rather than double-reported.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Normalise one path per line: strip a trailing slash, drop blanks, sort unique.
# `.claude/settings.json` is a file and the rest are directories; both compare
# fine as plain strings once the trailing slash is gone.
normalise() { sed 's|/$||' | grep -v '^$' | sort -u; }

# Join backslash continuations so a command split across lines reads as one
# logical line. session-start.sh wraps its argument list; the SKILL.md commands
# do not. One extractor handles both rather than two shapes of the same parse.
join_continuations() {
  awk '{ if (sub(/\\[[:space:]]*$/, "")) { printf "%s", $0 } else { print } }' "$1"
}

# Everything after the ` -- ` pathspec separator. The drift check pipes its
# result onward (`... 2>/dev/null | wc -l | tr -d ' '`), so cut at the first
# pipe or subshell close before splitting, or `wc` and `tr` read as pathspecs.
paths_after_dashdash() {
  sed 's/.* -- //; s/[|)].*//' | tr ' ' '\n' \
    | sed -n '/^[A-Za-z._]/p' | grep -v '^2>' | normalise
}

# --- source 1: the § Syncable Paths doc block --------------------------------
# Lines inside the fence have the shape `path   → description`.
# The terminator must match `parse_syncable_roots` in sync-retire.py, which
# stops at a heading of ANY depth. `##+` rather than `#{2,6}`: mawk does not
# support interval expressions, so the bounded form silently never matches.
# When only this one stopped at `^## `, a
# `### Subsection` inside the block left the script silently scanning fewer
# roots while this test still saw them all -- the two readers disagreeing is
# worse than either rule, because the drift test stays green through it.
extract_doc_block() {
  awk '/^## Syncable Paths/ { inblock = 1; next }
       inblock && /^##+ / { exit }
       inblock && /→/ && !/→ *RETIRED/ { print $1 }' "$1" | normalise
}

# The rows the block marks RETIRED: scanned by sync-retire.py, checked out by
# nothing. Kept out of EXPECTED so the checkout lists below are pinned to
# exclude them.
extract_retired_rows() {
  awk '/^## Syncable Paths/ { inblock = 1; next }
       inblock && /^##+ / { exit }
       inblock && /→ *RETIRED/ { print $1 }' "$1" | normalise
}

# --- sources 2-3: the two git diff commands ----------------------------------
# Keyed off ` -- `, not argument position, because one carries `--stat` and the
# other does not.
extract_diff_command() {
  join_continuations "$1" | grep '^git diff .* -- ' | sed -n "${2}p" | paths_after_dashdash
}

# --- source 7: the drift check ----------------------------------------------
extract_drift_check() {
  join_continuations "$1" | grep 'git diff --name-only .* -- ' | paths_after_dashdash
}

SYNC_CANON=".agents/skills/sync/SKILL.md"
HOOK=".claude/hooks/session-start.sh"
WORKFLOW=".github/workflows/sync-template.yml"

EXPECTED="$(extract_doc_block "$SYNC_CANON")"

# Non-vacuity: every comparison below is against EXPECTED, so an extractor that
# silently returned nothing would make all of them pass as "" = "". Anchored on
# a member rather than a count — pinning the size would force a test edit every
# time a path is legitimately added, which is how tests get edited reflexively.
assert_contains "$EXPECTED" "CLAUDE.md" \
  "doc-block extractor found the block (guards against vacuous '' = '' passes)"

assert_eq "$EXPECTED" "$(extract_diff_command "$SYNC_CANON" 1)" \
  "canonical /sync: 'git diff --stat' arg list matches the doc block"
assert_eq "$EXPECTED" "$(extract_diff_command "$SYNC_CANON" 2)" \
  "canonical /sync: full 'git diff' arg list matches the doc block"

assert_eq "$EXPECTED" "$(extract_drift_check "$HOOK")" \
  "session-start.sh: drift check covers the same set /sync applies"

# --- the RETIRED root: in the block, out of every checkout list ---------------
assert_eq ".claude/skills" "$(extract_retired_rows "$SYNC_CANON")" \
  "doc block: exactly one RETIRED row, .claude/skills (scanned for retirement, never checked out)"
assert_not_contains "$EXPECTED" ".claude/skills" \
  "doc block: the RETIRED row is not in the checkout set the lists above are pinned to"
assert_file_not_matches "$WORKFLOW" 'mirror "\.claude/skills"' \
  "sync-template.yml: the CI mirror no longer copies .claude/skills"
assert_file_matches "$WORKFLOW" '^# Retired .*\.claude/skills/' \
  "sync-template.yml: the header names .claude/skills/ as retired"
assert_file_matches "$WORKFLOW" 'Retired .*`\.claude/skills/`' \
  "sync-template.yml: the PR body names .claude/skills/ as retired"
assert_file_matches "$WORKFLOW" '^ *mirror "\.agents/skills"' \
  "sync-template.yml: the canonical tree is still mirrored (non-vacuity)"

# --- invariant 2: skill assets resolve inside a syncable path ---------------
is_syncable() {
  while IFS= read -r p; do
    case "$1" in "$p"|"$p"/*) return 0 ;; esac
  done <<EOF
$EXPECTED
EOF
  return 1
}

is_glob() { case "$1" in *"*"*|*"?"*) return 0 ;; *) return 1 ;; esac; }

# Two token shapes reach a script: skill-dir-relative (`scripts/render.py`, the
# common case) and canonical-tree-absolute (`.agents/skills/build/scripts/x.sh`,
# how one skill reaches a sibling's shared asset).
#
# One grep over every file rather than one per file: at ~80 skill documents the
# process spawns, not the matching, dominated the runtime (70s -> ~2s on
# Windows). `-H` keeps the filename attached so the single stream stays
# attributable.
# The canonical tree only: `.claude/skills/` is a RETIRED root, so an asset a
# copy there resolves relative to itself lands outside every syncable path by
# definition, and the copy is byte-identical to the canonical skill anyway.
scan_all_asset_tokens() {
  find .agents/skills -name '*.md' -not -path '*/.claude/worktrees/*' \
    -exec grep -oHE '\.agents/skills/[A-Za-z0-9_./-]+|(^|[^./A-Za-z0-9_-])(references|scripts|assets|templates)/[A-Za-z0-9_.*?/-]+' {} + \
    | sed 's|:[^./A-Za-z]|:|' | sed 's/[.,;:)`]*$//' | sort -u
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  md="${hit%%:*}"
  tok="${hit#*:}"
  [ -n "$tok" ] || continue
  is_glob "$tok" && continue
  skill_dir="$(dirname "$md")"
  # Resolve skill-dir-first, then repo-root — the same order agents experience.
  if [ -e "$skill_dir/$tok" ]; then resolved="$skill_dir/$tok"
  elif [ -e "$tok" ]; then resolved="$tok"
  else continue   # existence is test-skill-references.sh's invariant, not ours
  fi
  checked=$((checked + 1))
  if ! is_syncable "$resolved"; then
    _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
    printf '  FAIL Distribution: %s names %s -> %s, outside every syncable path\n' \
      "$md" "$tok" "$resolved"
  fi
done <<EOF
$(scan_all_asset_tokens)
EOF

assert_eq "yes" "$([ "$checked" -gt 0 ] && echo yes || echo no)" \
  "asset scan resolved at least one token (sanity: scanner is not a no-op)"

# The regression this test was written for: four skills execute this script, so
# it has to ship. Mode is read from the git index, not the filesystem — Windows
# checkouts do not carry the executable bit and would fail for unrelated reasons.
for tree in .agents .claude; do
  f="$tree/skills/build/scripts/bootstrap-worktree.sh"
  assert_eq "100755" "$(git ls-files -s "$f" | awk '{print $1}')" \
    "$f is tracked executable in the git index"
done

finish
