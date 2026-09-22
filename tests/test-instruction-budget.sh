#!/bin/bash
# tests/test-instruction-budget.sh — the single instruction file stays small,
# well-formed, and the only home of the shared rules.
#
# WHY THIS EXISTS
#
# Every session in every harness loads AGENTS.md. Before this file existed the
# shared rules were 493 lines of CLAUDE.md plus .claude/project.md plus a banner
# restating the skills table, and nothing stopped the next contributor from
# adding another section (specs/single-instruction-file.md § Problem). The
# managed block between the two markers is what /sync ships to every project,
# so its size is a per-session cost paid everywhere; the budget here is the
# spec's contract (§ Component contracts, "Managed block"), not a preference.
#
# The invariants below are the ones a reader cannot see by looking at the file:
#
#   - the block is at most 200 lines and the file at most 16 KiB;
#   - CLAUDE.md is exactly the import line `@AGENTS.md` (LF or CRLF), so Claude
#     Code reads the same file as Pi and Codex and nothing can accumulate there;
#   - the block's `## ` headings are the fixed set, in order (§ Data models) —
#     wording inside is free, the section set is not;
#   - no line in the block starts with `@` (an import inside the block would be
#     shipped to every project pointing at a file the template cannot deliver);
#   - the file has at most one H1, and the block none — the project's title
#     stays the sole H1;
#   - exactly one marker pair, begin before end;
#   - no live `Task tracking instructions:` pointer inside the block — the
#     registry's own POINTER_RE (`Task tracking instructions:\s*([^\s`<>]+)`,
#     case-insensitive, mid-line) must not match, so the convention is
#     documented with a `<path>` placeholder and never an example path. This
#     repository's own live pointer sits below the end marker;
#   - the two machine-parsed lines /build cites instead of restating (D21) —
#     the `[AMBIGUITY]` emission format and the `TODO(shortcut):` marker — are
#     present, as is the namespace sentence a reader of `/name` needs;
#   - .claude/project.md is gone, and outside tasks/, specs/ and tests/ the only
#     files that still name it are the readers that keep it working for an
#     unmigrated project, with a one-line notice (D3);
#   - the scaffold seeds match: project-template/CLAUDE.md is the same pointer,
#     project-template/AGENTS.md carries no block (D2: /sync is the block's only
#     writer) and no H1 other than its title.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

BEGIN='<!-- jplugin-agentic-development:begin -->'
END='<!-- jplugin-agentic-development:end -->'

# Strip CR so a CRLF checkout compares the same as an LF one.
agents="$(tr -d '\r' < AGENTS.md)"
# Drop fenced code: a `# comment` inside a ```bash block is not a heading.
unfenced() { awk '/^```/ { infence = !infence; next } !infence'; }
block="$(printf '%s\n' "$agents" | awk -v b="$BEGIN" -v e="$END" '
  $0 == b { inblock = 1; next }
  $0 == e { inblock = 0; next }
  inblock { print }')"
below="$(printf '%s\n' "$agents" | awk -v e="$END" 'seen { print } $0 == e { seen = 1 }')"

# --- markers -----------------------------------------------------------------
assert_eq "1" "$(printf '%s\n' "$agents" | grep -cxF -- "$BEGIN")" \
  "Budget: AGENTS.md has exactly one begin marker"
assert_eq "1" "$(printf '%s\n' "$agents" | grep -cxF -- "$END")" \
  "Budget: AGENTS.md has exactly one end marker"
begin_line="$(printf '%s\n' "$agents" | grep -nxF -- "$BEGIN" | cut -d: -f1)"
end_line="$(printf '%s\n' "$agents" | grep -nxF -- "$END" | cut -d: -f1)"
assert_eq "yes" "$([ "${begin_line:-0}" -lt "${end_line:-0}" ] && echo yes || echo no)" \
  "Budget: the begin marker precedes the end marker"

# --- size --------------------------------------------------------------------
block_lines="$(printf '%s\n' "$block" | grep -c '' || true)"
assert_eq "yes" "$([ "$block_lines" -gt 50 ] && [ "$block_lines" -le 200 ] && echo yes || echo "no ($block_lines lines)")" \
  "Budget: the managed block is between 51 and 200 lines (non-vacuous, within budget)"
file_bytes="$(wc -c < AGENTS.md | tr -d ' ')"
assert_eq "yes" "$([ "$file_bytes" -le 16384 ] && echo yes || echo "no ($file_bytes bytes)")" \
  "Budget: AGENTS.md is at most 16 KiB"

# --- CLAUDE.md is the import line, nothing else -------------------------------
assert_eq "@AGENTS.md" "$(tr -d '\r' < CLAUDE.md)" \
  "Budget: CLAUDE.md is byte-equal to the single line @AGENTS.md (CRLF tolerated)"
assert_eq "1" "$(grep -c '' CLAUDE.md)" \
  "Budget: CLAUDE.md is exactly one line"

# --- fixed heading set, in order ---------------------------------------------
expected_headings="$(printf '%s\n' \
  "## Session Start Checklist" \
  "## Workflow: PRD → Plan → Build → Wrap Up" \
  "## Review Gate Taxonomy" \
  "## Core Principles" \
  "## Quality Gate" \
  "## Key Directories" \
  "## Agents" \
  "## Task Tracking" \
  "## Code Economy" \
  "## Surgical Changes" \
  "## Ambiguity Protocol" \
  "## Large-Artifact Handoff" \
  "## Skills")"
assert_eq "$expected_headings" "$(printf '%s\n' "$block" | grep '^## ')" \
  "Budget: the block's ## headings are the fixed set, in order"

# --- no import line, no H1, in the block -------------------------------------
assert_eq "" "$(printf '%s\n' "$block" | grep -n '^@' || true)" \
  "Budget: no line in the block starts with @"
assert_eq "" "$(printf '%s\n' "$block" | grep -n '^# ' || true)" \
  "Budget: the block carries no H1"
assert_eq "yes" "$([ "$(printf '%s\n' "$agents" | unfenced | grep -c '^# ')" -le 1 ] && echo yes || echo no)" \
  "Budget: AGENTS.md has at most one H1"

# --- the pointer convention is documented, not exercised, inside the block ---
POINTER_RE='Task tracking instructions:[[:space:]]*[^[:space:]`<>]+'
assert_contains "$block" 'Task tracking instructions: <path>' \
  "Budget: the block documents the pointer convention with the <path> placeholder (non-vacuity)"
assert_eq "" "$(printf '%s\n' "$block" | grep -oiE "$POINTER_RE" || true)" \
  "Budget: POINTER_RE matches nothing inside the block — no live pointer ships to every project"
assert_eq "docs/task-tracking.md" "$(printf '%s\n' "$below" | grep -oiE "$POINTER_RE" | sed -E 's/^[^:]*:[[:space:]]*//' | head -1)" \
  "Budget: this repository's live pointer sits below the end marker"

# --- the machine-parsed lines /build cites instead of restating (D21) --------
assert_contains "$block" '[AMBIGUITY] <one-sentence description> | options: A) <option> B) <option> [C) ...] | picked: <letter> | reason: <one sentence>' \
  "Budget: the block carries the [AMBIGUITY] emission format verbatim"
assert_contains "$block" 'TODO(shortcut):' \
  "Budget: the block carries the TODO(shortcut): marker"
assert_eq "1" "$(printf '%s\n' "$block" | grep -cF 'is typed `/jplugin:name`')" \
  "Budget: the block states the plugin namespace mapping exactly once"

# --- .claude/project.md is gone; only the notice-bearing readers name it -----
assert_eq "absent" "$([ -e .claude/project.md ] && echo present || echo absent)" \
  "Budget: .claude/project.md no longer exists"
# The readers that keep an unmigrated project working (D3), the two docs
# that describe that state, and the /sync script that moves the file's
# sections into AGENTS.md (--migrate, slice 4). Anything else naming the file
# is a stale pointer.
allowed_mentions='^(\.agents/skills/task-registry/scripts/registry/config\.py|\.agents/skills/task-registry/references/configuration\.md|\.agents/skills/setup-deployment/SKILL\.md|\.agents/skills/verify-deployment/SKILL\.md|\.agents/skills/verify-evidence/SKILL\.md|\.agents/skills/wrap-up-session/SKILL\.md|\.agents/skills/sync/SKILL\.md|\.agents/skills/sync/scripts/sync-managed-block\.py|\.agents/hooks/session-start\.sh)$'
stray="$(git grep -l -e '\.claude/project\.md' -- . ':!tasks' ':!specs' ':!tests' 2>/dev/null \
  | grep -vE "$allowed_mentions" || true)"
assert_eq "" "$stray" \
  "Budget: outside tasks/, specs/, tests/ and the notice-bearing readers, nothing names .claude/project.md
${stray}"
# Non-vacuity for the allowlist: the readers really do still carry the notice.
assert_file_contains .agents/skills/task-registry/scripts/registry/config.py \
  'pointer found in {LEGACY_POINTER_FILE} — /sync will move it to AGENTS.md' \
  "Budget: the registry prints the one-line notice for a pointer still in .claude/project.md"

# --- scaffold seeds -----------------------------------------------------------
assert_eq "@AGENTS.md" "$(tr -d '\r' < project-template/CLAUDE.md)" \
  "Budget: project-template/CLAUDE.md is the same pointer"
assert_eq "0" "$(grep -cF -- "$BEGIN" project-template/AGENTS.md || true)" \
  "Budget: project-template/AGENTS.md ships no managed block (D2 — /sync is its only writer)"
assert_file_matches project-template/AGENTS.md '^# Project Instructions$' \
  "Budget: project-template/AGENTS.md is titled Project Instructions"
assert_eq "1" "$(tr -d '\r' < project-template/AGENTS.md | unfenced | grep -c '^# ')" \
  "Budget: project-template/AGENTS.md has exactly one H1"

finish
