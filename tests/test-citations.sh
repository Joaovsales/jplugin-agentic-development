#!/bin/bash
# tests/test-citations.sh — every `<file>` § *<Heading>* citation resolves.
#
# WHY THIS EXISTS
#
# Protocol text moved out of CLAUDE.md into .agents/references/ so that each
# rule has exactly one home (specs/single-instruction-file.md § Constraints,
# "Every removed rule keeps exactly one home"). The skills and personas that
# used to say `CLAUDE.md` § *Finding Model* now cite the reference file and a
# heading inside it. A citation is a promise that the reader can go there and
# find the section; a heading renamed or a file moved turns that promise into a
# dead pointer, and nothing else notices — the skill still runs, it just sends
# the agent to a section that is not there.
#
# The citation form is fixed (spec § Component contracts, "Reference files"):
#
#   `<path>.md` § *<Heading>*
#
# and it resolves when <path> exists and holds a `## <Heading>` or
# `### <Heading>` line — or a line that opens with a bold `**<Heading>**` or
# `**<Heading>.**` label, the shape the AGENTS.md block's Core Principles use
# for their sub-rules (Observability Discipline, No Silent Failures, Code Graph
# First), which the skills cite by that name. Headings are compared with
# whitespace collapsed, because the prose is hard-wrapped and a citation can
# straddle a line break.
#
# Scope: every Markdown file under .agents/ and .claude/agents/, plus AGENTS.md
# — the files the spec names as citing sites. Paths are resolved from the repo
# root first, then relative to the citing file's directory (a skill citing its
# own references/x.md). Placeholders (`<`, `*`, `?` in the path) are skipped:
# they are templates for the reader to fill, not pointers.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

report="$("$TEST_PYTHON" - <<'PY'
import re, sys
from pathlib import Path

CITE = re.compile(r"`([^`\n]+\.md)` § \*([^*]+?)\*")
HEADING = re.compile(r"^#{2,3} (.+?)\s*$|^\*\*([^*\n]+?)\.?\*\*", re.M)

def collapse(s):
    return re.sub(r"\s+", " ", s).strip()

files = [p for p in Path(".agents").rglob("*.md") if ".claude/worktrees" not in p.as_posix()]
files += list(Path(".claude/agents").glob("*.md"))
files += [Path("AGENTS.md")]
headings = {}
def headings_of(path):
    if path not in headings:
        text = path.read_text(encoding="utf-8", errors="replace")
        headings[path] = {collapse(m.group(1) or m.group(2)) for m in HEADING.finditer(text)}
    return headings[path]

count = 0
for f in files:
    text = f.read_text(encoding="utf-8", errors="replace")
    for m in CITE.finditer(text):
        target, heading = m.group(1), collapse(m.group(2))
        if any(ch in target for ch in "<*?"):
            continue
        count += 1
        candidates = [Path(target), f.parent / target]
        found = next((c for c in candidates if c.is_file()), None)
        line = text.count("\n", 0, m.start()) + 1
        if found is None:
            print(f"FAIL {f.as_posix()}:{line} cites `{target}` § *{heading}* — file not found")
            continue
        if heading not in headings_of(found):
            print(f"FAIL {f.as_posix()}:{line} cites `{target}` § *{heading}* — no such heading in {found.as_posix()}")
print(f"COUNT {count}")
PY
)"

failures="$(printf '%s\n' "$report" | grep '^FAIL' || true)"
count="$(printf '%s\n' "$report" | sed -n 's/^COUNT //p')"

# Non-vacuity: the scanner must have seen the citations it exists to check.
# Anchored on a floor, not an exact count, so adding a citation never forces a
# test edit.
assert_eq "yes" "$([ "${count:-0}" -ge 20 ] && echo yes || echo "no ($count found)")" \
  "Citations: scanner found at least 20 § citations (not a no-op)"

assert_eq "" "$failures" \
  "Citations: every \`<file>\` § *<Heading>* citation resolves to a heading in that file
${failures}"

# The three reference files exist with their fixed heading sets, in order
# (spec § Data models, "Reference files — fixed headings").
check_headings() {  # check_headings <file> <heading>...
  f="$1"; shift
  actual="$(grep -E '^## ' "$f" | sed 's/^## //' | tr -d '\r' | paste -sd'|' -)"
  expected="$(printf '%s|' "$@" | sed 's/|$//')"
  assert_eq "$expected" "$actual" "Citations: $f carries its fixed ## headings in order"
}
check_headings .agents/references/finding-model.md \
  "Four axes" "Emission format" "Confidence anchors" "Gates" \
  "Resolving an anchor-75 finding" "Independence Accounting"
check_headings .agents/references/review-dispatch-contract.md \
  "The seven items" "Empty is not absent" "Bounded items" "Repo-survey dispatch" \
  "Share intent, withhold conclusions"
check_headings .agents/references/model-routing.md \
  "Tiers" "Ceiling" "Floors" "Agents" "Rules"

# The moved sections have one home: no skill or persona cites CLAUDE.md for them.
stale="$(grep -rnE 'CLAUDE\.md` § \*?(Finding Model|Review Dispatch Contract|Model Routing|Independence Accounting)' \
  .agents .claude/agents 2>/dev/null | grep -vF '.claude/worktrees' || true)"
assert_eq "" "$stale" \
  "Citations: no skill or persona still cites CLAUDE.md for a moved section
${stale}"

finish
