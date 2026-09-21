#!/bin/bash
# tests/test-skill-references.sh — reference integrity + self-containment for skills.
#
# Two invariants, both mechanical:
#
#   1. REFERENCE INTEGRITY — every concrete skill-asset path a skill names
#      (`references/x.md`, `scripts/x.py`, `templates/x.md`, `assets/x`) must
#      resolve to a file that exists, tried skill-dir-first then repo-root.
#      A renamed or deleted asset otherwise breaks a skill silently.
#
#   2. SELF-CONTAINMENT — a path inside an EXECUTED command must resolve from the
#      project root, which is where the Bash tool's cwd actually is. Two shapes are
#      forbidden in executable fences:
#        - `../other-skill/...`      relative traversal out of the skill
#        - `.claude/skills/...`      names a tree the template ships nothing under
#      A traversal resolves outside the repo entirely and is simply broken. The
#      template no longer ships anything under `.claude/skills/` -- Claude Code
#      loads skills from `.agents/skills/` through the `jplugin` plugin -- so an
#      executed path naming that tree resolves nothing and stays forbidden.
#
#      `.agents/skills/...` in an executed command is ALLOWED. It is the
#      canonical tree, checked into this repo, so it is always present -- this is
#      how a skill legitimately reaches a shared script in a sibling skill, and
#      `scripts/` is not among `/sync`'s syncable paths, so relocating those
#      scripts to the repo root would strand them downstream.
#
# "Executed" is decided by FENCE LANGUAGE, not by fence membership: this repo has
# 173 unlabeled fences that are data listings (path tables, templates, sample
# output) versus 23 ```bash fences that are real commands. Only bash/sh/shell/
# console fences are treated as executable context.
#
# Deliberately NOT violations in this repo (unlike a distributed plugin, where
# every skill directory must stand alone):
#   - `scripts/bootstrap-worktree.sh` — repo-root shared scripts are legitimate
#     here; the skill tree lives in the same repo.
#   - Cross-skill paths in PROSE. They must exist (invariant 1) but are not
#     executed, so cwd cannot break them.
#   - Glob patterns (`scripts/smoke*.sh`) — discovery patterns for the USER's
#     project, not references to files in this repo.
#
# Excludes .claude/worktrees/, which holds full copies of the skill tree and
# would otherwise double-scan and report phantom violations.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TREES=".agents/skills"

# Emit "<lineno>|<executable>|<token>" per candidate path token.
#
# One combined regex, and POSIX ERE is leftmost-longest, so a traversal or
# harness-pinned path matches whole rather than leaving its tail to be re-matched
# as a bogus skill-local token. Each match is consumed before scanning on.
scan_tokens() {
  awk '
    /^[[:space:]]*```/ {
      if (fence) { fence = 0; exec_fence = 0 }
      else {
        fence = 1
        lang = $0
        sub(/^[[:space:]]*```/, "", lang)
        sub(/[[:space:]]*$/, "", lang)
        exec_fence = (lang == "bash" || lang == "sh" || lang == "shell" || lang == "console")
      }
      next
    }
    {
      line = $0
      while (match(line, /\.\.\/[A-Za-z0-9_.\/-]+|\.(agents|claude)\/skills\/[A-Za-z0-9_.\/-]+|(references|scripts|assets|templates)\/[A-Za-z0-9_.*?\/-]+/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        # Trim trailing markdown/punctuation the regex absorbs. Done here rather
        # than via a `sed` per token: one spawn per token dominated runtime.
        sub(/[.,;:)`]+$/, "", tok)
        if (tok != "") print NR "|" exec_fence "|" tok
      }
    }
  ' "$1"
}

is_glob() {
  case "$1" in *"*"*|*"?"*) return 0 ;; *) return 1 ;; esac
}

fail() {
  _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
  printf '  FAIL %s\n' "$1"
}

for tree in $TREES; do
  [ -d "$tree" ] || continue
  while IFS= read -r md; do
    skill_rel="${md#"$tree"/}"
    skill_name="${skill_rel%%/*}"
    skill_dir="$tree/$skill_name"
    # Tree-root files (e.g. README.md) have no owning skill directory.
    [ -d "$skill_dir" ] || continue

    while IFS='|' read -r lineno executable tok; do
      [ -n "$tok" ] || continue
      is_glob "$tok" && continue

      case "$tok" in
        ../*)
          if [ "$executable" = "1" ]; then
            fail "SelfContain: $md:$lineno executes escaping path $tok"
          else
            assert_eq "exists" "$([ -e "$skill_dir/$tok" ] && echo exists || echo missing)" \
              "RefInt: $md:$lineno prose ref $tok resolves"
          fi
          ;;
        .claude/skills/*)
          if [ "$executable" = "1" ]; then
            fail "SelfContain: $md:$lineno executes compat-copy path $tok (use .agents/skills/)"
          else
            assert_eq "exists" "$([ -e "$tok" ] && echo exists || echo missing)" \
              "RefInt: $md:$lineno cited path $tok exists"
          fi
          ;;
        .agents/skills/*)
          # Canonical tree: allowed in executed commands, must still exist.
          assert_eq "exists" "$([ -e "$tok" ] && echo exists || echo missing)" \
            "RefInt: $md:$lineno canonical path $tok exists"
          ;;
        *)
          if [ -e "$skill_dir/$tok" ] || [ -e "$tok" ]; then
            assert_eq "resolved" "resolved" "RefInt: $md:$lineno $tok resolves"
          else
            fail "RefInt: $md:$lineno names $tok — not in $skill_dir/ nor at repo root"
          fi
          ;;
      esac
    done <<EOF
$(scan_tokens "$md")
EOF
  done <<EOF
$(find "$tree" -name '*.md' -not -path '*/.claude/worktrees/*' | sort)
EOF
done

finish
