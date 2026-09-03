#!/bin/bash
# tests/test-living-spec-reconciliation.sh — specs are living contracts, and
# wrap-up is what keeps them true.
#
# WHY THIS EXISTS
#
# A spec written at /plan time describes what the code was *going* to do. Nothing
# in the workflow ever revisited it, so specs/ accreted prospective language,
# superseded behaviour, and `## Files Likely Involved` lists naming paths that had
# since moved. The failure is quiet: the spec still parses, still reads plausibly,
# and still gets handed to reviewers as the contract the diff must satisfy — so a
# reviewer measures today's code against last month's intent and reports the
# difference as a defect.
#
# Two halves, and they need different kinds of test:
#
#   * Candidate DISCOVERY is deterministic — glob matching, change-set
#     collection, metadata validation, dedup. That is a script, and it is tested
#     by running it against throwaway Git repositories built under a temp dir.
#   * Semantic RECONCILIATION is a judgement — did this diff change what the spec
#     claims? No assertion can settle that, and a keyword heuristic pretending to
#     would be worse than nothing. So what is pinned here is the *instruction*:
#     that wrap-up assigns exactly one outcome per candidate, that it reads the
#     code flow before deciding, and that an unresolved case defers loudly rather
#     than guessing.
#
# The same limit the tier floors and the review-payload contract have: whether a
# given runtime pass actually reasoned that way is not observable from disk.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CANON=".agents/skills"
COMPAT=".claude/skills"

# Extract the body of the FIRST `## Acceptance Criteria` section, stopping at the
# next H2 or at a fence terminator. Anchoring on the heading rather than grepping
# the whole file matters: `- [ ]` appears legitimately in these skills' own task
# examples, and a file-wide grep would pass while the template itself still
# shipped checkboxes.
#
# The stop condition is load-bearing. An earlier draft toggled on ``` and ran off
# the end of the template into unrelated prose, which made the assertion vacuous
# in exactly the direction that hides a regression. `assert_not_contains` rejects
# an empty haystack, so a heading that stops matching fails loudly rather than
# passing by finding nothing.
extract_ac_section() {
  awk '
    !found && /^## Acceptance Criteria[[:space:]]*$/ { found = 1; next }
    found && (/^## / || /^```[[:space:]]*$/)         { exit }
    found                                            { print }
  ' "$1"
}

printf '\n--- 1. Workflow-created specs are living contracts ------------------\n'

# A spec that does not declare its implementation surface cannot be selected when
# that surface changes -- it is discoverable only by the legacy prose fallback,
# which is exactly the debt this feature retires. So the templates that CREATE
# specs must emit the metadata, or every new spec is born legacy.
for tree in "$CANON" "$COMPAT"; do
  for skill in plan brainstorm; do
    f="$tree/$skill/SKILL.md"
    assert_file_matches "$f" '^implementation_paths:' \
      "$skill ($tree): spec template declares implementation_paths frontmatter"
    assert_file_matches "$f" '^## Implementation Paths$' \
      "$skill ($tree): spec template carries an H2 Implementation Paths section"

    # Ordinary bullets, not task checkboxes. A spec's Acceptance Criteria state
    # what is true of the code now; a checkbox states what someone intends to do
    # about it, and a half-ticked list in a merged spec is unreadable as either.
    ac="$(extract_ac_section "$f")"
    assert_not_contains "$ac" '- [ ]' \
      "$skill ($tree): template Acceptance Criteria use ordinary bullets, not checkboxes"

    # The legacy heading must be gone from the template, not merely joined by the
    # new one -- a template emitting both teaches the format it is replacing.
    assert_file_not_matches "$f" '^## Files Likely Involved$' \
      "$skill ($tree): spec template no longer emits the legacy Files Likely Involved heading"
  done

  # The plan block is what associates completed tasks with a spec. Without an
  # exact machine-readable line, wrap-up would have to guess a spec from a
  # similar filename, which is the one thing the spec forbids it to do.
  assert_file_contains "$tree/plan/SKILL.md" '> Spec: specs/[feature-name].md' \
    "plan ($tree): plan template associates its tasks with exactly one spec path"
done

# specs/README.md is where a human learns the format. A contract documented only
# inside the generator is one nobody reads before hand-writing a spec.
assert_file_matches specs/README.md '^implementation_paths:' \
  "specs/README.md documents the implementation_paths frontmatter"
assert_prose_contains specs/README.md 'living contract' \
  "specs/README.md states specs describe current behavior, not intent"
assert_prose_contains specs/README.md 'Frontmatter is the matching contract' \
  "specs/README.md distinguishes the matching contract from the explanatory section"

# ---------------------------------------------------------------------------
# Fixture plumbing. Every scenario builds a throwaway Git repository under a temp
# dir and removes it on exit, so nothing here can touch this repository's specs.
# ---------------------------------------------------------------------------

HELPER="$REPO/$CANON/wrap-up-session/scripts/spec-reconcile.py"

if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else printf '  FAIL no python interpreter found (python3/python)\n'; exit 1
fi

TMP_DIRS=()
cleanup() { for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# make_repo -> prints the path of a fresh repo with `main` holding one commit.
make_repo() {
  local d
  d="$(mktemp -d)"
  TMP_DIRS+=("$d")
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name  Test
  mkdir -p "$d/src" "$d/specs" "$d/tasks"
  printf 'one\n'   > "$d/src/kept.py"
  printf 'two\n'   > "$d/src/renamed_from.py"
  printf 'three\n' > "$d/src/deleted.py"
  printf 'four\n'  > "$d/src/unstaged.py"
  git -C "$d" add -A >/dev/null
  git -C "$d" commit -qm base
  printf '%s' "$d"
}

printf '\n--- 2. The change set is one immutable pre-reconciliation snapshot ---\n'

# Wrap-up edits specs. If it re-derived the change set afterwards it would see its
# own edits and could select itself, so the snapshot is taken once, before any
# write. Three sources must be unioned: a session whose work is committed, one
# still staged, and one still dirty are all the same session.
D="$(make_repo)"
git -C "$D" checkout -qb feature
printf 'one\nchanged\n' > "$D/src/kept.py"
git -C "$D" mv src/renamed_from.py src/renamed_to.py
git -C "$D" rm -q src/deleted.py
printf 'new\n' > "$D/src/added.py"
git -C "$D" add -A >/dev/null
git -C "$D" commit -qm work
printf 'staged\n' > "$D/src/staged.py"
git -C "$D" add src/staged.py
printf 'four\ndirty\n' > "$D/src/unstaged.py"

CS="$($PY "$HELPER" changeset --repo "$D" --base main --json 2>&1)"
assert_contains "$CS" '"src/kept.py"'      "changeset: committed modification captured"
assert_contains "$CS" '"src/added.py"'     "changeset: committed addition captured"
assert_contains "$CS" '"src/staged.py"'    "changeset: staged-but-uncommitted path captured"
assert_contains "$CS" '"src/unstaged.py"'  "changeset: unstaged working-tree path captured"

# A rename is two facts, not one. A spec that named the old path must still be
# selected -- that spec is precisely the one now describing a file that moved,
# which is the case most in need of reconciliation.
assert_contains "$CS" '"src/renamed_from.py"' "changeset: rename retains its OLD path"
assert_contains "$CS" '"src/renamed_to.py"'   "changeset: rename retains its NEW path"
assert_contains "$CS" '"src/deleted.py"'      "changeset: deletion retains the old path"

# Status letters survive to the consumer, so a reconciler can tell "this file
# moved" from "this file changed" without re-running git.
assert_contains "$CS" '"status": "R"' "changeset: rename reported with status R"
assert_contains "$CS" '"status": "D"' "changeset: deletion reported with status D"
assert_contains "$CS" '"status": "A"' "changeset: addition reported with status A"

# Copy detection is exercised at the parser rather than by contorting git into
# emitting a C record: what must not regress is that `C` is handled like `R`,
# with both endpoints retained.
#
# The parser reads git's NUL-delimited `-z` form, not tab/newline. That is not
# incidental: without `-z`, git quotes any path holding a space or a non-ASCII
# byte, and a quoted path matches no spec pattern -- so the spec that documents
# that file is silently never selected. NUL delimiting removes the quoting layer
# entirely rather than teaching the parser to undo it.
PARSED="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
# Register before exec: the module uses `from __future__ import annotations`, so
# @dataclass resolves its field types by looking itself up in sys.modules.
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
stream = "C085\0src/from.py\0src/to.py\0M\0src/plain name.py\0"
changes = mod.parse_name_status(stream, "committed")
print(json.dumps([[c.status, c.path, c.old_path] for c in changes]))
EOF
)"
assert_contains "$PARSED" '"C", "src/to.py", "src/from.py"'  "parser: copy keeps both endpoints and score-stripped status"
assert_contains "$PARSED" '"M", "src/plain name.py", null'   "parser: a path containing a space survives unquoted"

printf '\n--- 3. Path metadata: matching semantics and loud rejection ---------\n'

# The matcher is exercised in-process. Driving it through fixture repositories
# would test git and the matcher at once, and a matching bug would surface as a
# missing candidate three layers away from the rule that caused it.
MATCH="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

cases = {
    # `*` and `?` stop at a separator; `**` is the only token that crosses one.
    "star-same-dir":     ("src/*.py",        "src/a.py"),
    "star-not-nested":   ("src/*.py",        "src/sub/a.py"),
    "globstar-nested":   ("src/**",          "src/sub/deep/a.py"),
    "globstar-flat":     ("src/**",          "src/a.py"),
    "globstar-mid":      ("**/test_*.py",    "tests/deep/test_x.py"),
    "question-one":      ("src/?.py",        "src/a.py"),
    "question-not-two":  ("src/?.py",        "src/ab.py"),
    "question-not-sep":  ("src/a?b.py",      "src/a/b.py"),
    # Whole-path, case-sensitive. A prefix is not a match: `src/a` naming
    # `src/api.py` would silently widen every spec's declared surface.
    "case-sensitive":    ("SRC/a.py",        "src/a.py"),
    "whole-path-prefix": ("src/a",           "src/api.py"),
    "exact":             ("tests/run.sh",    "tests/run.sh"),
}
print(json.dumps({k: mod.match_path(pat, path) for k, (pat, path) in cases.items()}))
EOF
)"
assert_contains "$MATCH" '"star-same-dir": true'      "glob: * matches within one directory segment"
assert_contains "$MATCH" '"star-not-nested": false'   "glob: * does NOT cross a / separator"
assert_contains "$MATCH" '"globstar-nested": true'    "glob: ** crosses separators"
assert_contains "$MATCH" '"globstar-flat": true'      "glob: ** also matches zero directories deep"
assert_contains "$MATCH" '"globstar-mid": true'       "glob: ** composes with * in one pattern"
assert_contains "$MATCH" '"question-one": true'       "glob: ? matches exactly one character"
assert_contains "$MATCH" '"question-not-two": false'  "glob: ? does not match two characters"
assert_contains "$MATCH" '"question-not-sep": false'  "glob: ? does not match a / separator"
assert_contains "$MATCH" '"case-sensitive": false'    "glob: matching is case-sensitive"
assert_contains "$MATCH" '"whole-path-prefix": false' "glob: a prefix is not a match — whole path only"
assert_contains "$MATCH" '"exact": true'              "glob: a literal path matches itself"

# Rejection. Each of these is a value a spec author can write by accident, and
# each fails in the same silent direction if merely ignored: the pattern matches
# nothing, so the spec is never selected and quietly stops being maintained.
REJECT="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

def outcome(pattern):
    try:
        mod.validate_pattern(pattern, "specs/x.md")
        return "accepted"
    except mod.SpecPathError as exc:
        return str(exc)

print(json.dumps({
    "absolute":    outcome("/etc/passwd"),
    "traversal":   outcome("../../.ssh/id_rsa"),
    "inner-dots":  outcome("src/../../etc/passwd"),
    "charclass":   outcome("src/[ab].py"),
    "braces":      outcome("src/{a,b}.py"),
    "negation":    outcome("!src/a.py"),
    "backslash":   outcome("src\\a.py"),
    "empty":       outcome("   "),
    "ordinary":    outcome("src/**/handler.py"),
    "missing-ok":  outcome("src/does/not/exist.py"),
}))
EOF
)"
assert_contains "$REJECT" '"ordinary": "accepted"'   "validation: an ordinary glob is accepted"
# A path that simply is not on disk is NOT an error: the spec says so explicitly,
# because a deleted or renamed file is the normal case reconciliation exists for.
assert_contains "$REJECT" '"missing-ok": "accepted"' "validation: a path that no longer exists is not an error"
assert_not_contains "$REJECT" '"absolute": "accepted"'   "validation: an absolute path is rejected"
assert_not_contains "$REJECT" '"traversal": "accepted"'  "validation: a leading .. traversal is rejected"
assert_not_contains "$REJECT" '"inner-dots": "accepted"' "validation: a mid-path .. segment is rejected"
assert_not_contains "$REJECT" '"charclass": "accepted"'  "validation: a character class is rejected"
assert_not_contains "$REJECT" '"braces": "accepted"'     "validation: brace expansion is rejected"
assert_not_contains "$REJECT" '"negation": "accepted"'   "validation: a negation prefix is rejected"
assert_not_contains "$REJECT" '"backslash": "accepted"'  "validation: a Windows separator is rejected"
assert_not_contains "$REJECT" '"empty": "accepted"'      "validation: an empty pattern is rejected"

# Evidence, not just refusal. "invalid path" without the spec and the value makes
# the author grep every spec in the tree to find which one broke the run.
assert_contains "$REJECT" 'specs/x.md'  "validation: the error names the offending spec"
assert_contains "$REJECT" '/etc/passwd' "validation: the error quotes the offending value"

# Malformed frontmatter is the same class of failure one level up: the block
# parses to nothing, so the spec looks metadata-free and silently falls back to
# the legacy reader instead of announcing that its contract is broken.
FM="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json, tempfile, os
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

def outcome(text):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "s.md")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    try:
        patterns, source = mod.spec_patterns(p, "specs/s.md")
        return "ok:%s:%s" % (source, ",".join(patterns))
    except mod.SpecPathError as exc:
        return str(exc)

good = "---\nimplementation_paths:\n  - src/**\n  - tests/t.sh\n---\n\n# Spec\n"
unterminated = "---\nimplementation_paths:\n  - src/**\n\n# Spec\n"
empty_list = "---\nimplementation_paths:\n---\n\n# Spec\n"
scalar = "---\nimplementation_paths: src/**\n---\n\n# Spec\n"
legacy = "# Spec\n\n## Files Likely Involved\n- `src/legacy.py` - why\n- `tests/x.sh` - why\n"
# The legacy section is PROSE, and prose backticks type names beside paths. A
# reader that validated every token the way declared metadata is validated would
# hard-fail wrap-up on a legacy spec that is perfectly fine.
prose = ("# Spec\n\n## Files Likely Involved\n"
         "- `src/cache.py` - holds a `Dict[str, int]` keyed by user\n"
         "- `run.sh` - entry point\n")
both = "---\nimplementation_paths:\n  - src/meta.py\n---\n\n## Files Likely Involved\n- `src/legacy.py` - why\n"
neither = "# Spec\n\nNo paths here.\n"

print(json.dumps({
    "good": outcome(good),
    "unterminated": outcome(unterminated),
    "empty-list": outcome(empty_list),
    "scalar": outcome(scalar),
    "legacy": outcome(legacy),
    "both": outcome(both),
    "neither": outcome(neither),
    "prose": outcome(prose),
}))
EOF
)"
assert_contains "$FM" '"good": "ok:frontmatter:src/**,tests/t.sh"' "frontmatter: a well-formed block yields its paths"
assert_not_contains "$FM" '"unterminated": "ok' "frontmatter: an unterminated block is a loud error"
assert_not_contains "$FM" '"empty-list": "ok'   "frontmatter: a key with no entries is a loud error"
assert_not_contains "$FM" '"scalar": "ok'       "frontmatter: a scalar where a list belongs is a loud error"

# Legacy fallback, and the precedence between the two readers.
assert_contains "$FM" '"legacy": "ok:legacy:src/legacy.py,tests/x.sh"' \
  "legacy: paths are parsed from ## Files Likely Involved when no metadata exists"
assert_contains "$FM" '"both": "ok:frontmatter:src/meta.py"' \
  "precedence: explicit metadata wins; the legacy section is not also consulted"
assert_contains "$FM" '"neither": "ok:none:"' \
  "a spec declaring no paths at all yields none rather than failing"
assert_contains "$FM" '"prose": "ok:legacy:src/cache.py,run.sh"' \
  "legacy: a non-path token in prose is passed over, not treated as a broken path"

printf '\n--- 4. Candidate discovery is deterministic and keeps its reasons ----\n'

# One fixture repository exercising every discovery rule at once, because the
# rules interact: precedence, overlap, dedup and the session spec all decide the
# same list, and testing them in isolation would not catch one silently
# overriding another.
E="$(make_repo)"
mkdir -p "$E/specs" "$E/tasks"

# Two specs claiming the SAME file. The mapping is many-to-many by design: a
# shared module belongs to every feature built on it, and picking one owner would
# leave the others describing behavior that moved out from under them.
cat > "$E/specs/alpha.md" <<'EOF'
---
implementation_paths:
  - src/shared.py
  - src/renamed_from.py
---
# Spec: Alpha
EOF
cat > "$E/specs/beta.md" <<'EOF'
---
implementation_paths:
  - src/shared.py
  - src/deleted.py
---
# Spec: Beta
EOF
# A legacy spec, discoverable only through the compatibility reader.
cat > "$E/specs/legacy.md" <<'EOF'
# Spec: Legacy

## Files Likely Involved
- `src/kept.py` — why it matters
EOF
# The session spec: no metadata at all, and its declared surface is untouched. It
# must still be a candidate, because the completed plan names it.
cat > "$E/specs/session.md" <<'EOF'
# Spec: Session
EOF
# A spec nothing in this change set touches. It must NOT appear.
cat > "$E/specs/unrelated.md" <<'EOF'
---
implementation_paths:
  - docs/**
---
# Spec: Unrelated
EOF
# A spec that DOES claim the spec directory. This is what makes the
# self-selection guard testable: without the exclusion this spec is selected by
# reconciliation's own edits, and each pass produces work for the next one.
cat > "$E/specs/meta.md" <<'EOF'
---
implementation_paths:
  - specs/**
---
# Spec: Meta
EOF
cat > "$E/tasks/todo.md" <<'EOF'
## Plan: Something Older
> Spec: specs/alpha.md

[x] TDD: old work -> done

## Plan: The Session
> Spec: specs/session.md

[x] TDD: current work -> done
EOF
git -C "$E" add -A >/dev/null && git -C "$E" commit -qm specs

git -C "$E" checkout -qb feature
printf 'shared\n' > "$E/src/shared.py"
printf 'one\nchanged\n' > "$E/src/kept.py"
git -C "$E" mv src/renamed_from.py src/renamed_to.py
git -C "$E" rm -q src/deleted.py
# A spec edit in the same session. Discovery must not let spec files select
# specs, or the step selects its own output and never reaches a fixed point.
printf '\nedited during the session\n' >> "$E/specs/unrelated.md"
git -C "$E" add -A >/dev/null && git -C "$E" commit -qm work

DISC="$($PY "$HELPER" discover --repo "$E" --base main --json 2>&1)"
assert_contains "$DISC" '"spec": "specs/alpha.md"'   "discover: a spec matched through its metadata is a candidate"
assert_contains "$DISC" '"spec": "specs/beta.md"'    "discover: a second spec claiming the same file is ALSO a candidate"
assert_contains "$DISC" '"spec": "specs/legacy.md"'  "discover: a legacy spec is found through Files Likely Involved"
assert_contains "$DISC" '"spec": "specs/session.md"' "discover: the plan's named spec is a candidate with no metadata and no matching path"
assert_not_contains "$DISC" '"spec": "specs/unrelated.md"' \
  "discover: an untouched spec is not a candidate"
assert_not_contains "$DISC" '"spec": "specs/meta.md"' \
  "discover: a spec claiming specs/** is NOT selected by the session's own spec edits"

# Reasons are retained per candidate, not collapsed to a boolean. Reconciliation
# reads them to decide what to re-examine, and "matched somehow" would send the
# agent back to re-derive what discovery already knew.
# Scoped to the `candidates` half deliberately. The bare path also appears in the
# `changeset` half of the same payload, so asserting against $DISC would hold
# whether or not the rename selected anything -- the assertion would stay green
# through exactly the regression it exists to catch.
printf '%s' "$DISC" > "$E/discover.json"
DISC_REASONS="$($PY -c '
import json, sys
payload = json.load(open(sys.argv[1]))
print("\n".join(r for c in payload["candidates"] for r in c["reasons"]))
' "$E/discover.json")"
assert_contains "$DISC_REASONS" 'src/renamed_from.py' "discover: a rename selects the spec via its OLD path"
assert_contains "$DISC_REASONS" 'src/deleted.py'      "discover: a deletion still selects the spec that documented it"
assert_contains "$DISC_REASONS" 'session-spec'        "discover: the session-spec reason is labelled, not disguised as a path match"

# Dedup without reason loss: alpha matches on two distinct paths and must appear
# once carrying both.
ALPHA_COUNT="$(printf '%s' "$DISC" | grep -c '"spec": "specs/alpha.md"')"
assert_eq "1" "$ALPHA_COUNT" "discover: a spec matched by two paths appears exactly once"
ALPHA_REASONS="$($PY - <<EOF
import json,sys
d=json.loads('''$DISC''')
c=[x for x in d["candidates"] if x["spec"]=="specs/alpha.md"][0]
print(len(c["reasons"]))
EOF
)"
assert_eq "2" "$ALPHA_REASONS" "discover: both match reasons survive the dedup"

# A plan block with no association yields no session spec. Guessing "the spec
# whose filename looks like the plan title" is the one inference the format
# exists to remove.
cat > "$E/tasks/todo.md" <<'EOF'
## Plan: Unassociated

[x] TDD: work -> done
EOF
NOASSOC="$($PY "$HELPER" discover --repo "$E" --base main --json 2>&1)"
assert_not_contains "$NOASSOC" 'session-spec' \
  'discover: a plan block without a `> Spec:` line contributes no session spec'
assert_not_contains "$NOASSOC" '"spec": "specs/session.md"' \
  "discover: an unassociated plan never guesses a spec from a similar filename"

# Invalid metadata anywhere stops the run, non-zero, naming spec and value. A
# discovery pass that skipped the broken spec would return a shorter list that
# looks exactly like a clean one.
cat > "$E/specs/broken.md" <<'EOF'
---
implementation_paths:
  - /etc/passwd
---
# Spec: Broken
EOF
BROKEN_OUT="$($PY "$HELPER" discover --repo "$E" --base main 2>&1)"; BROKEN_RC=$?
assert_eq "1" "$BROKEN_RC" "discover: invalid metadata exits non-zero rather than returning a short list"
assert_contains "$BROKEN_OUT" "specs/broken.md" "discover: the failure names the offending spec"
assert_contains "$BROKEN_OUT" "/etc/passwd"     "discover: the failure quotes the offending value"
rm "$E/specs/broken.md"

# Zero candidates is a success, not an error -- an internal-only session is the
# common case and must not make wrap-up look broken.
F="$(make_repo)"
git -C "$F" checkout -qb feature
printf 'x\n' >> "$F/src/kept.py"
git -C "$F" commit -qam work
EMPTY_OUT="$($PY "$HELPER" discover --repo "$F" --base main 2>&1)"; EMPTY_RC=$?
assert_eq "0" "$EMPTY_RC" "discover: no candidates exits 0"
assert_contains "$EMPTY_OUT" "0 candidates" "discover: no candidates reports a bounded count, not silence"

printf '\n--- 5. Semantic reconciliation: three outcomes, no keyword shortcut -\n'

# The three scenarios the spec names are materialised in one repository and run
# through discovery, so they are executed fixtures rather than prose about
# fixtures. What discovery must prove is that all three ARRIVE as candidates --
# including the two that will not be edited. A step that only surfaced the specs
# it was going to change could never report "unchanged", and "I examined it and
# it is still accurate" is the outcome that makes the other two trustworthy.
S="$(make_repo)"
mkdir -p "$S/specs" "$S/tasks" "$S/src"
printf 'shared\n' > "$S/src/shared.py"
printf 'behavior\n' > "$S/src/behavior.py"
printf 'opaque\n' > "$S/src/opaque.py"
cat > "$S/specs/changed-behavior.md" <<'EOF'
---
implementation_paths:
  - src/behavior.py
---
# Spec: Changed Behavior
EOF
cat > "$S/specs/untouched-contract.md" <<'EOF'
---
implementation_paths:
  - src/shared.py
---
# Spec: Untouched Contract
EOF
cat > "$S/specs/unresolvable.md" <<'EOF'
---
implementation_paths:
  - src/opaque.py
---
# Spec: Unresolvable
EOF
git -C "$S" add -A >/dev/null && git -C "$S" commit -qm specs
git -C "$S" checkout -qb feature
printf 'behavior\nnow returns a different shape\n' > "$S/src/behavior.py"   # -> updated
printf 'shared\n# reformatted only\n' > "$S/src/shared.py"                  # -> unchanged
printf 'opaque\nvalue = CONFIG_SET_AT_DEPLOY\n' > "$S/src/opaque.py"        # -> deferred
git -C "$S" commit -qam work

SEM="$($PY "$HELPER" discover --repo "$S" --base main --json 2>&1)"
assert_contains "$SEM" '"spec": "specs/changed-behavior.md"' \
  "semantic: the spec whose behavior changed reaches reconciliation"
assert_contains "$SEM" '"spec": "specs/untouched-contract.md"' \
  "semantic: a spec whose file changed but whose contract did not is STILL a candidate"
assert_contains "$SEM" '"spec": "specs/unresolvable.md"' \
  "semantic: a spec whose effect cannot be resolved is a candidate, not a silent skip"

# The judgement itself is instruction, not assertion -- a keyword heuristic
# pretending to grade it would rewrite correct specs on a word match. So what is
# pinned is that the protocol exists, names exactly three outcomes, and says
# which evidence must be read before one is assigned.
WU="$CANON/wrap-up-session/SKILL.md"
WUC="$COMPAT/wrap-up-session/SKILL.md"
for f in "$WU" "$WUC"; do
  assert_prose_contains "$f" 'exactly one outcome' \
    "wrap-up ($f): every candidate receives exactly one outcome"
  assert_prose_contains "$f" '`updated`' "wrap-up ($f): the updated outcome is defined"
  assert_prose_contains "$f" '`unchanged`' "wrap-up ($f): the unchanged outcome is defined"
  assert_prose_contains "$f" '`deferred`' "wrap-up ($f): the deferred outcome is defined"
  assert_prose_contains "$f" 'leave the file byte-identical' \
    "wrap-up ($f): unchanged means no write at all, not a cosmetic touch"
  # The comparison must be semantic. Without this, the cheapest implementation of
  # the step is grepping the diff for words from the spec, which updates specs
  # that did not change and misses the ones that did.
  assert_prose_contains "$f" 'semantic rather than keyword-based' \
    "wrap-up ($f): the comparison is semantic, not a keyword match"
  assert_prose_contains "$f" 'callers' \
    "wrap-up ($f): reconciliation reads the callers, not only the diff hunk"
  # Formatting-only and unrelated-shared-file changes are the two cases that
  # produce spurious rewrites, so they are named rather than left to judgement.
  assert_prose_contains "$f" 'Formatting-only changes' \
    "wrap-up ($f): a formatting-only change is explicitly unchanged"
  # Prose describes behavior, not the session that produced it. A spec that says
  # "this session changed X" is a changelog, and it rots on the next commit.
  assert_prose_contains "$f" 'must not mention the session' \
    "wrap-up ($f): updated prose carries no change-log narration"
  assert_prose_contains "$f" 'That history belongs in Git' \
    "wrap-up ($f): the reason change-log prose is excluded is stated, not just the rule"
done

printf '\n--- 6. Legacy migration rides on behavioral change, never on format -\n'

# The five migration steps, pinned individually. A heading alone would stay green
# with the list emptied, and each step is separately forgettable: a migration that
# adds frontmatter but leaves `## Files Likely Involved` in place ships a spec with
# two contradictory path lists and no rule saying which one wins.
for f in "$WU" "$WUC"; do
  assert_prose_contains "$f" 'add valid `implementation_paths` frontmatter' \
    "migration ($f): step 1 adds the metadata"
  assert_prose_contains "$f" 'replace `## Files Likely Involved` with `## Implementation Paths`' \
    "migration ($f): step 2 replaces the legacy heading rather than joining it"
  assert_prose_contains "$f" 'rewrite prospective descriptions into current factual ones' \
    "migration ($f): step 3 de-prospectivizes the prose"
  assert_prose_contains "$f" 'convert Acceptance Criteria checkboxes into ordinary bullets' \
    "migration ($f): step 4 converts checkboxes to bullets"
  assert_prose_contains "$f" 'leave unrelated accurate content intact' \
    "migration ($f): step 5 preserves content the change did not touch"

  # The load-bearing negative. Without it the cheapest reading of "migrate legacy
  # specs" is a sweep that reformats every one of them, which buries the single
  # behavioral diff a reviewer needs to see inside a tree-wide reflow.
  assert_prose_contains "$f" 'is **not** rewritten merely to migrate its format' \
    "migration ($f): an unchanged legacy candidate is left byte-identical"
  assert_prose_contains "$f" 'Migration rides on behavioral change' \
    "migration ($f): the reason migration is lazy is stated, not just the rule"
done

# The two skill trees must agree byte-for-byte. A contract that holds only in the
# canonical tree is one Claude Code never reads.
assert_files_identical "$WU" "$WUC" "wrap-up SKILL.md is byte-identical across skill trees"
assert_files_identical "$CANON/wrap-up-session/scripts/spec-reconcile.py" \
                       "$COMPAT/wrap-up-session/scripts/spec-reconcile.py" \
                       "spec-reconcile.py is byte-identical across skill trees"

printf '\n--- 7. Deferred work becomes one idempotent, provider-neutral task ---\n'

REGISTRY="$REPO/$CANON/task-registry/scripts/task-registry.py"

# The ID is derived from the COMPLETE repository-relative spec path, so each spec
# has at most one live reconciliation task. Deriving it from the basename would
# collide `specs/auth.md` with `specs/legacy/auth.md` and silently merge two
# unrelated deferrals into one ticket.
IDS="$($PY - "$REGISTRY" <<'EOF'
import importlib.util, sys, json, os
root = os.path.dirname(sys.argv[1])
sys.path.insert(0, root)
from registry.model import slugify_id, is_valid_id
a = slugify_id("spec-reconciliation", "specs/feature-c.md")
b = slugify_id("spec-reconciliation", "specs/legacy/feature-c.md")
print(json.dumps({"a": a, "b": b, "distinct": a != b, "valid": is_valid_id(a)}))
EOF
)"
assert_contains "$IDS" '"a": "spec-reconciliation.specs-feature-c-md"' \
  "defer id: derived from the full repository-relative spec path"
assert_contains "$IDS" '"distinct": true' \
  "defer id: two specs sharing a basename do not collide"
assert_contains "$IDS" '"valid": true' \
  "defer id: the derived id satisfies the registry's own id rule"

# A fixture project with no tracker configured -- the offline default, and the
# case every downstream repository hits before it configures anything.
P="$(mktemp -d)"; TMP_DIRS+=("$P")
mkdir -p "$P/tasks" "$P/specs"
printf '# Tasks\n\n## Plan: Existing\n\n[x] TDD: done -> done\n' > "$P/tasks/todo.md"
printf '# Spec: Feature C\n' > "$P/specs/feature-c.md"

# The record's content is passed as structured fields, not a free-form body. Each
# one round-trips through the local provider's metadata block or a managed
# section, so a second run REPLACES the record; a pasted Markdown body would be
# preserved as a foreign section and the file would grow a stale copy per run.
DEFER_ARGS=(
  --title 'Reconcile specs/feature-c.md with current export ordering'
  --kind research
  --spec specs/feature-c.md
  --summary 'Row ordering in the exporter changed; whether that ordering is observable depends on a consumer outside this repository.'
  --evidence 'selected-by: src/export.py (M, committed)'
  --evidence 'inspected: src/export.py:88 — ordering changed'
  --evidence 'missing: no test pins the ordering contract and no in-repo caller reads it'
  --evidence 'revision: feature @ abc1234'
  --criterion 'Determine whether row ordering is part of the exporter contract'
  --criterion 'Update specs/feature-c.md and its implementation_paths to match'
)

# Dry-run is the registry's iron law and this command is not an exception. A step
# that wrote on the default path would make every `/wrap-up-session` rehearsal
# leave litter behind.
DRY="$($PY "$REGISTRY" upsert spec-reconciliation.specs-feature-c-md --repo "$P" \
  "${DEFER_ARGS[@]}" 2>&1)"; DRY_RC=$?
assert_eq "0" "$DRY_RC" "upsert: dry-run exits 0"
assert_contains "$DRY" "would" "upsert: dry-run says what it would do"
assert_eq "absent" "$([ -f "$P/tasks/details/spec-reconciliation.specs-feature-c-md.md" ] && echo present || echo absent)" \
  "upsert: dry-run writes no detail file"
assert_not_contains "$(cat "$P/tasks/todo.md")" "spec-reconciliation" \
  "upsert: dry-run writes no index row"

# --apply: one durable record and one compact index row pointing at it.
APPLY="$($PY "$REGISTRY" upsert spec-reconciliation.specs-feature-c-md --repo "$P" --apply \
  "${DEFER_ARGS[@]}" 2>&1)"; APPLY_RC=$?
assert_eq "0" "$APPLY_RC" "upsert --apply exits 0"
DETAIL="$P/tasks/details/spec-reconciliation.specs-feature-c-md.md"
assert_eq "present" "$([ -f "$DETAIL" ] && echo present || echo absent)" \
  "upsert: --apply writes the canonical local record"

# Every field the spec requires a deferred task to carry. Each is separately
# forgettable, and a record missing any one of them cannot be acted on later
# without redoing the investigation that produced it.
assert_file_contains "$DETAIL" "specs/feature-c.md"   "defer record: names the spec it is about"
assert_file_contains "$DETAIL" "src/export.py"        "defer record: names the changed path that selected the spec"
assert_file_contains "$DETAIL" "ordering is observable" "defer record: states the unresolved behavior question"
assert_file_contains "$DETAIL" "inspected:"           "defer record: lists the evidence inspected"
assert_file_contains "$DETAIL" "missing:"             "defer record: lists the evidence that was missing"
assert_file_contains "$DETAIL" "revision:"            "defer record: records the branch and commit"
assert_file_contains "$DETAIL" "Determine whether row ordering" "defer record: carries verifiable reconciliation criteria"
# "Links" means a link, not merely the id. The `<!-- task-id: -->` comment
# contains the id too, so asserting the id alone passes on a row that points at
# nothing -- which is exactly the state the index exists to prevent.
INDEX_ROW="$(grep 'spec-reconciliation.specs-feature-c-md' "$P/tasks/todo.md")"
assert_contains "$INDEX_ROW" "task-id: spec-reconciliation.specs-feature-c-md" \
  "upsert: the compact index row carries the stable id"
assert_contains "$INDEX_ROW" "tasks/details/spec-reconciliation.specs-feature-c-md.md" \
  "upsert: the index row links the record it indexes, not just names it"
# `research` is the registry's own vocabulary for a spike whose output is
# knowledge. Filing documentation debt as a `bug` would put it in a queue that
# gets triaged for a severity it does not have.
assert_file_contains "$DETAIL" "research" "upsert: the task is filed as research"

# Idempotence. Re-running wrap-up over the same change set is a normal thing to
# do -- after a review fix, after a rebase -- and each run must update the one
# task rather than mint a second.
$PY "$REGISTRY" upsert spec-reconciliation.specs-feature-c-md --repo "$P" --apply \
  --title 'Reconcile specs/feature-c.md with current export ordering' \
  --kind research --spec specs/feature-c.md \
  --summary 'Second look: the only consumer is a downstream repository.' \
  --evidence 'inspected: the downstream consumer is out of tree' >/dev/null 2>&1
ROWS="$(grep -c 'spec-reconciliation.specs-feature-c-md' "$P/tasks/todo.md")"
assert_eq "1" "$ROWS" "upsert: a second run updates the one row instead of adding another"
DETAIL_COUNT="$(ls "$P/tasks/details" | wc -l | tr -d ' ')"
assert_eq "1" "$DETAIL_COUNT" "upsert: a second run leaves exactly one canonical record"
assert_file_contains "$DETAIL" "downstream repository" "upsert: the second run's new evidence reaches the record"

# Reopen. A spec that was reconciled and closed, then goes uncertain again, is
# the same question recurring -- not a new one -- so the closed task reopens.
$PY - "$DETAIL" <<'EOF'
import sys, re
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"^- status: .*$", "- status: done", t, count=1, flags=re.M))
EOF
REOPEN="$($PY "$REGISTRY" upsert spec-reconciliation.specs-feature-c-md --repo "$P" --apply \
  --title 'Reconcile specs/feature-c.md with current export ordering' \
  --kind research --spec specs/feature-c.md \
  --summary 'The question came back after the exporter changed again.' 2>&1)"
assert_contains "$REOPEN" "reopen" "upsert: a completed task is reopened rather than duplicated"
assert_file_matches "$DETAIL" '^- status: open$' "upsert: the reopened task is open again"

printf '\n--- 8. External publication only where the write policy already allows -\n'

# The destination decision is pure, so it is tested directly rather than through
# whichever tracker happens to be installed on the machine running the suite.
# Every branch here is a way documentation debt could be lost: published without
# authorization, or dropped because publishing was not allowed.
DEST="$($PY - "$REGISTRY" <<'EOF'
import sys, os, json
root = os.path.dirname(sys.argv[1])
sys.path.insert(0, root)
from registry.upsert import resolve_destination
from registry.providers.base import WriteGate

open_gate    = WriteGate(apply=True, require_approval=False)
gated        = WriteGate(apply=True, require_approval=True, approved=False)
approved     = WriteGate(apply=True, require_approval=True, approved=True)

print(json.dumps({
    "local-provider":     resolve_destination("local",  open_gate, True),
    "external-permitted": resolve_destination("github", open_gate, True),
    "external-approved":  resolve_destination("github", approved,  True),
    "needs-approval":     resolve_destination("github", gated,     True),
    "unreachable":        resolve_destination("github", open_gate, False),
}))
EOF
)"
assert_contains "$DEST" '"local-provider": "local"' \
  "destination: with no tracker the local record is simply canonical"
assert_contains "$DEST" '"external-permitted": "external"' \
  "destination: an existing policy that permits unattended writes publishes"
assert_contains "$DEST" '"external-approved": "external"' \
  "destination: explicit approval publishes"
# The two fallbacks. Neither may block wrap-up, and neither may claim success.
assert_contains "$DEST" '"needs-approval": "local-pending"' \
  "destination: approval required and not given falls back to local, publication pending"
assert_contains "$DEST" '"unreachable": "local-pending"' \
  "destination: an unreachable provider falls back to local rather than failing the run"

# The preview must describe the run --apply would perform. WriteGate.open folds
# the dry-run flag into the approval policy, so reading it here made the dry-run
# report `local-pending` for a provider the apply run would have written to --
# and the preview is the artifact a human reads before authorizing that write.
PREVIEW="$($PY - "$REGISTRY" <<'EOF'
import sys, os, json
sys.path.insert(0, os.path.dirname(sys.argv[1]))
from registry.upsert import resolve_destination
from registry.providers.base import WriteGate
dry   = WriteGate(apply=False, require_approval=False)
wet   = WriteGate(apply=True,  require_approval=False)
print(json.dumps({
    "dry": resolve_destination("github", dry, True),
    "apply": resolve_destination("github", wet, True),
}))
EOF
)"
assert_contains "$PREVIEW" '"dry": "external"' \
  "destination: the dry-run preview names the destination --apply would use"
DRY_DEST="$($PY -c "import json,sys;d=json.loads(sys.argv[1]);print(d['dry'])" "$PREVIEW")"
APPLY_DEST="$($PY -c "import json,sys;d=json.loads(sys.argv[1]);print(d['apply'])" "$PREVIEW")"
assert_eq "$APPLY_DEST" "$DRY_DEST" \
  "destination: preview and apply agree — destination is policy, not intent-to-write"

# Idempotence rests entirely on two runs minting the same id. A rule that lives
# only in prose is one each caller re-derives by hand, and `is_valid_id` accepts
# both plausible normalizations -- so a mismatch mints a second task silently, on
# the second session. The derivation is therefore exposed, not described.
DERIVED="$($PY "$REGISTRY" upsert --repo "$P" --derive-id spec-reconciliation \
  --spec specs/feature-c.md --title 'Derived id run' --kind research 2>&1)"
assert_contains "$DERIVED" "spec-reconciliation.specs-feature-c-md" \
  "derive-id: the CLI mints the same id the normalization rule specifies"
assert_contains "$DERIVED" "would update" \
  "derive-id: the derived id addresses the EXISTING task, proving the two agree"

BOTH_IDS="$($PY "$REGISTRY" upsert some.id --repo "$P" --derive-id spec-reconciliation \
  --spec specs/feature-c.md --title 'x' 2>&1)"; BOTH_RC=$?
assert_eq "2" "$BOTH_RC" "derive-id: supplying both an explicit and a derived id is a usage error"
NEITHER="$($PY "$REGISTRY" upsert --repo "$P" --title 'x' 2>&1)"; NEITHER_RC=$?
assert_eq "2" "$NEITHER_RC" "derive-id: supplying neither is a usage error, not a default"

# And the skill must say so, because the failure this prevents is a judgement
# call made at 3am by an unattended run: pausing for approval would hang the
# pipeline, and publishing without it would breach the project's write policy.
for f in "$WU" "$WUC"; do
  assert_prose_contains "$f" 'does not pause or fail' \
    "deferred ($f): an unpublishable task never blocks wrap-up"
  assert_prose_contains "$f" 'publication is pending' \
    "deferred ($f): pending external publication is reported, not silently dropped"
  # Specific, not the bare word STOP -- `STOP` appears throughout this skill, so
  # a bare needle would stay green with this rule deleted entirely.
  assert_prose_contains "$f" 'STOP wrap-up: the documentation debt would otherwise be lost' \
    "deferred ($f): a local record that cannot be written stops wrap-up, with the reason"
  assert_prose_contains "$f" 'spec-reconciliation.<normalized-spec-path>' \
    "deferred ($f): the stable id scheme is stated so the task is idempotent"
  assert_prose_contains "$f" 'task-registry' \
    "deferred ($f): the task is created through the registry, never a direct tracker call"
  assert_prose_contains "$f" 'PR description' \
    "deferred ($f): every deferred task is surfaced to reviewers in the PR"
done

printf '\n--- 9. Placement: after the register, before every downstream gate ---\n'

# Order is the whole design, not a detail. Too early and completed task intent is
# not yet available; too late and spec edits skip the gates that would have
# caught them -- a spec rewritten AFTER review and tests is a file nothing
# checked. So the step's position is asserted against the actual heading
# sequence, not merely its presence.
step_order() { grep -n '^## Step ' "$1" | sed 's/:.*Step /:/' | sed 's/ .*//'; }
for f in "$WU" "$WUC"; do
  ORDER="$(step_order "$f")"
  assert_contains "$ORDER" ":3.2" "placement ($f): a Step 3.2 exists"
  LINE_REG="$(grep -n '^## Step 2 ' "$f" | cut -d: -f1)"
  LINE_REC="$(grep -n '^## Step 3.2 ' "$f" | cut -d: -f1)"
  LINE_MAP="$(grep -n '^## Step 3.3 ' "$f" | cut -d: -f1)"
  LINE_SEC="$(grep -n '^## Step 3.5 ' "$f" | cut -d: -f1)"
  LINE_REV="$(grep -n '^## Step 4 ' "$f" | cut -d: -f1)"
  LINE_TEST="$(grep -n '^## Step 6 ' "$f" | cut -d: -f1)"
  LINE_PUSH="$(grep -n '^## Step 7 ' "$f" | cut -d: -f1)"
  assert_eq "after" "$([ "$LINE_REC" -gt "$LINE_REG" ] && echo after || echo before)" \
    "placement ($f): reconciliation runs AFTER the task register"
  assert_eq "before" "$([ "$LINE_REC" -lt "$LINE_MAP" ] && echo before || echo after)" \
    "placement ($f): reconciliation runs BEFORE verification-map maintenance"
  assert_eq "before" "$([ "$LINE_REC" -lt "$LINE_SEC" ] && echo before || echo after)" \
    "placement ($f): reconciliation runs BEFORE the security scan"
  assert_eq "before" "$([ "$LINE_REC" -lt "$LINE_REV" ] && echo before || echo after)" \
    "placement ($f): reconciliation runs BEFORE code review"
  assert_eq "before" "$([ "$LINE_REC" -lt "$LINE_TEST" ] && echo before || echo after)" \
    "placement ($f): reconciliation runs BEFORE the test run"
  assert_eq "before" "$([ "$LINE_REC" -lt "$LINE_PUSH" ] && echo before || echo after)" \
    "placement ($f): reconciliation runs BEFORE commit and push"

  # The snapshot must precede the writes, or the step reads its own edits.
  assert_prose_contains "$f" 'before any spec is written' \
    "placement ($f): the change set is captured before reconciliation writes"
  # And a failing downstream gate must take the spec edits down with the code.
  # Committing a spec whose code was rejected publishes a description of
  # behavior that does not exist.
  assert_prose_contains "$f" 'join the code in the verification, security, review, test, commit, and push gates' \
    "placement ($f): updated specs are covered by every downstream gate"
  assert_prose_contains "$f" 'failing gate blocks both' \
    "placement ($f): a failing downstream gate blocks the spec edit as well as the code"
done

printf '\n--- 10. Review context carries every relevant spec, not just one -----\n'

# Item 2 of the dispatch contract said "the spec" when a session can legitimately
# touch several. A reviewer handed one of three measures the other two's changes
# against nothing, and reports the difference as a defect.
assert_prose_contains CLAUDE.md 'Every spec relevant to this session' \
  "contract: item 2 carries every relevant spec, not a single one"
assert_prose_contains CLAUDE.md 'each spec' \
  "contract: acceptance criteria are per-spec, so a reviewer can tell them apart"
for f in "$WU" "$WUC"; do
  assert_prose_contains "$f" 'Every spec relevant to this session' \
    "payload ($f): the review payload assembles every relevant spec"
  assert_prose_contains "$f" 'reconciled this session' \
    "payload ($f): reconciled specs are named as part of the payload"
  # The boundary must survive the generalization. Handing a reviewer more specs
  # without it invites a re-review of every pre-existing spec in the tree.
  assert_prose_contains "$f" 'issues **introduced** by this session' \
    "payload ($f): the introduced-this-session boundary is retained"
done

# Deferred tasks reach the PR body, where reviewers actually look.
for f in "$WU" "$WUC"; do
  assert_prose_contains "$f" 'deliberately left alone rather than missed' \
    "PR ($f): a deferred spec is explained, not silently absent"
done

printf '\n--- 11. Reporting stays bounded; the new verb is documented ----------\n'

for f in "$WU" "$WUC"; do
  # Counts on all four outcomes. Reporting only what changed would make
  # "examined and still accurate" indistinguishable from "never looked".
  assert_prose_contains "$f" 'candidates, 2 updated, 2 unchanged, 1 deferred' \
    "report ($f): all four outcome counts appear in the reported shape"
  assert_prose_contains "$f" 'Updated: specs/feature-a.md' \
    "report ($f): updated specs are named, not just counted"
  assert_prose_contains "$f" 'Deferred: spec-reconciliation.' \
    "report ($f): the deferred task id and its record are named"
  # Quiet on the quiet path. A step that prints a paragraph when it found
  # nothing is one people stop reading on the run where it matters.
  assert_prose_contains "$f" 'is a **successful outcome** and stays one line' \
    "report ($f): no candidates is a success, not a warning"
  # All-unchanged is also a success, but it is the outcome that leaves no other
  # trace -- so it still names what it compared.
  assert_prose_contains "$f" 'Unchanged:' \
    "report ($f): the unchanged specs are named, per the AC requiring paths for all four"
  assert_prose_contains "$f" 'Candidates:' \
    "report ($f): the candidate specs are named, per the AC requiring paths for all four"
done

# The registry gained a verb. An undocumented command is one no skill will use,
# and the command table is what a reader consults before the source.
RS="$CANON/task-registry/SKILL.md"
RSC="$COMPAT/task-registry/SKILL.md"
for f in "$RS" "$RSC"; do
  assert_file_contains "$f" "task-registry.py upsert" \
    "registry ($f): upsert appears in the command examples"
  assert_prose_contains "$f" '| `upsert` |' \
    "registry ($f): upsert appears in the reads/writes capability table"
  assert_prose_contains "$f" 'idempotent' \
    "registry ($f): the property that makes upsert safe to re-run is stated"
done

# The helper must be reachable from where the skill says it is, in both trees.
for tree in "$CANON" "$COMPAT"; do
  assert_eq "present" "$([ -f "$tree/wrap-up-session/scripts/spec-reconcile.py" ] && echo present || echo absent)" \
    "distribution ($tree): the discovery helper ships inside the skill directory"
  assert_eq "present" "$([ -f "$tree/task-registry/scripts/registry/upsert.py" ] && echo present || echo absent)" \
    "distribution ($tree): the upsert module ships inside the skill directory"
done
assert_files_identical "$CANON/task-registry/scripts/registry/upsert.py" \
                       "$COMPAT/task-registry/scripts/registry/upsert.py" \
                       "upsert.py is byte-identical across skill trees"
assert_files_identical "$CANON/task-registry/scripts/task-registry.py" \
                       "$COMPAT/task-registry/scripts/task-registry.py" \
                       "task-registry.py is byte-identical across skill trees"

# This feature's own spec must obey the format it introduces. A spec that
# exempts itself is the clearest possible signal the format is optional.
OWN="specs/living-spec-reconciliation.md"
assert_file_matches "$OWN" '^implementation_paths:' \
  "dogfood: this feature's spec declares its own implementation surface"
assert_file_matches "$OWN" '^## Implementation Paths$' \
  "dogfood: this feature's spec carries the explanatory section"
assert_file_not_matches "$OWN" '^## Files Likely Involved$' \
  "dogfood: this feature's spec no longer uses the legacy heading"
own_ac="$(extract_ac_section "$OWN")"
assert_not_contains "$own_ac" '- [ ]' \
  "dogfood: this feature's spec uses ordinary-bullet Acceptance Criteria"

# And the paths it declares must actually be the ones this feature ships, or the
# next session's reconciliation will not select it.
OWN_MATCH="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json, os
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
patterns, source = mod.spec_patterns("specs/living-spec-reconciliation.md",
                                     "specs/living-spec-reconciliation.md")
shipped = [
    ".agents/skills/wrap-up-session/SKILL.md",
    ".agents/skills/wrap-up-session/scripts/spec-reconcile.py",
    ".agents/skills/task-registry/scripts/registry/upsert.py",
    "tests/test-living-spec-reconciliation.sh",
]
print(json.dumps({
    "source": source,
    "unmatched": [p for p in shipped if not any(mod.match_path(g, p) for g in patterns)],
}))
EOF
)"
assert_contains "$OWN_MATCH" '"source": "frontmatter"' \
  "dogfood: this feature's spec is discovered through metadata, not the legacy reader"
assert_contains "$OWN_MATCH" '"unmatched": []' \
  "dogfood: every file this feature ships is covered by its declared paths"

# ---------------------------------------------------------------------------
# 12. Review findings — each of these was a live defect, not a hypothetical
# ---------------------------------------------------------------------------

# A retired spec is not a description of current behaviour, so reconciling it
# would reintroduce as "current" something the project already withdrew.
R="$(make_repo)"
git -C "$R" checkout -qb feature
mkdir -p "$R/specs"
cat > "$R/specs/live.md" <<'EOF'
---
implementation_paths:
  - src/**
---
# Live
EOF
cat > "$R/specs/gone.md" <<'EOF'
---
status: superseded
implementation_paths:
  - src/**
---
# Gone
EOF
cat > "$R/specs/replaced.md" <<'EOF'
---
implementation_paths:
  - src/**
---
> Superseded by: specs/live.md

# Replaced
EOF
mkdir -p "$R/src" && echo x > "$R/src/a.py"
git -C "$R" add -A >/dev/null && git -C "$R" commit -qm work
RET="$($PY "$HELPER" discover --repo "$R" --base main --json 2>&1)"
assert_contains "$RET" '"spec": "specs/live.md"' \
  "retired: a live spec sharing the same path is still selected"
assert_not_contains "$RET" '"spec": "specs/gone.md"' \
  "retired: a spec whose status marks it superseded is not reconciled"
assert_not_contains "$RET" '"spec": "specs/replaced.md"' \
  "retired: a spec carrying a Superseded by admonition is not reconciled"

# A plan block naming a spec that does not exist is the case most in need of
# reconciliation -- typically a rename. Returning None makes it indistinguishable
# from a plan that named nothing at all.
printf '\n## Plan: x\n> Spec: specs/vanished.md\n' >> "$R/tasks/todo.md"
MISSING="$($PY "$HELPER" discover --repo "$R" --base main --json 2>&1 || true)"
assert_contains "$MISSING" 'specs/vanished.md' \
  "session-spec: an unresolvable > Spec: line names the offending path"
assert_contains "$MISSING" 'does not exist' \
  "session-spec: an unresolvable > Spec: line fails loudly instead of returning no association"

# Prose writes a directory as `src/`, but matching is a whole-path fullmatch and
# no file path ends in a slash -- so the token looked declared and selected nothing.
DIRTOK="$($PY - "$HELPER" <<'EOF'
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
paths = mod._legacy_paths("## Files Likely Involved\n\n- `.claude/agents/` holds them\n")
print(json.dumps({"paths": paths,
                  "hit": any(mod.match_path(p, ".claude/agents/critic.md") for p in paths)}))
EOF
)"
assert_contains "$DIRTOK" '"hit": true' \
  "legacy: a directory token written with a trailing slash matches files inside it"

# `{base}...HEAD` is one argv element, but git reads a leading dash as an option
# wherever it appears.
BASEDASH="$($PY "$HELPER" changeset --repo "$R" --base '--upload-pack=touch /tmp/pwn' 2>&1 || true)"
assert_contains "$BASEDASH" 'option-like' \
  "base: an option-like revision name is rejected before it reaches git"

# upsert must not overwrite the fields a human owns, nor forget where a task lives.
MERGE="$($PY - "$REPO/$CANON/task-registry/scripts" <<'EOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from registry.model import Task, ExternalRef
from registry.upsert import _merge
existing = Task(id="ns.x", title="old", status="in_progress", priority="high",
                external=ExternalRef(provider="github", id="42",
                                     url="https://example.test/42"))
incoming = Task(id="ns.x", title="new")
merged, action = _merge(existing, incoming)
print(json.dumps({"action": action, "title": merged.title, "status": merged.status,
                  "priority": merged.priority,
                  "external": None if merged.external is None else merged.external.id}))
EOF
)"
assert_contains "$MERGE" '"title": "new"' \
  "upsert: a re-run replaces the content this command owns"
assert_contains "$MERGE" '"status": "in_progress"' \
  "upsert: a re-run does not reset a status a human moved"
assert_contains "$MERGE" '"priority": "high"' \
  "upsert: a re-run preserves human triage fields"
assert_contains "$MERGE" '"external": "42"' \
  "upsert: a re-run keeps the address the task was published to"

finish
