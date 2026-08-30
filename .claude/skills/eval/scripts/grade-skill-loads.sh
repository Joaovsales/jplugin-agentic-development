#!/usr/bin/env bash
# grade-skill-loads.sh — which skills did each candidate actually load?
#
# Grades a triggerability run from the transcripts rather than from what the
# candidates said they did. A candidate that mentions a skill, prints a
# SKILL.md path, or claims to have followed a process has not necessarily
# loaded anything; the only evidence that survives is a Skill tool-use block.
#
# Usage:
#   grade-skill-loads.sh <transcript-dir>          list loads per candidate
#   grade-skill-loads.sh <transcript-dir> <skill>  grade against one skill
#
# <transcript-dir> is the workflow's own directory, holding one
# agent-<id>.jsonl per candidate.
#
# Exit: 0 measured, 2 nothing to measure (bad path, no transcripts, or a
# transcript this parser cannot read). Never 0 on a failed measurement — a
# silent zero reads as "the skill never fired".

set -euo pipefail

die() { printf 'grade-skill-loads: %s\n' "$1" >&2; exit 2; }

DIR="${1:-}"
[ -n "$DIR" ] || die "usage: grade-skill-loads.sh <transcript-dir> [skill]"
[ -d "$DIR" ] || die "no such directory: $DIR"
WANT="${2:-}"

# Grounded in the observed transcript shape:
#   "name":"Skill","input":{"skill":"plan","args":"..."}
# A load is counted only from a real tool-use block. Anything looser matches a
# candidate's own console output and inflates every result.
BLOCK='"name":[[:space:]]*"Skill"'

loads_in() {
  grep -oE "$BLOCK,[[:space:]]*\"input\":\{[[:space:]]*\"skill\":[[:space:]]*\"[^\"]+\"" "$1" 2>/dev/null \
    | sed 's/.*"skill":[[:space:]]*"//; s/"$//' | sort -u | paste -sd, - || true
}

fired=0; misrouted=0; none=0; total=0

for f in "$DIR"/agent-*.jsonl; do
  [ -e "$f" ] || die "no agent-*.jsonl transcripts in $DIR"
  total=$((total + 1))
  id="$(basename "$f" .jsonl)"
  got="$(loads_in "$f")"

  # A transcript that holds a Skill block the extractor could not read means the
  # transcript format moved. Reporting "NONE" there would be a false negative,
  # which is the exact error this script exists to prevent.
  if [ -z "$got" ] && grep -qE "$BLOCK" "$f"; then
    die "$id holds a Skill block this parser cannot read — transcript format changed"
  fi

  if [ -z "$WANT" ]; then
    printf '%s  %s\n' "$id" "${got:--}"
    continue
  fi

  case ",$got," in
    *",$WANT,"*) verdict=FIRED;     fired=$((fired + 1)) ;;
    ,,)          verdict=NONE;      none=$((none + 1)) ;;
    *)           verdict=MISROUTED; misrouted=$((misrouted + 1)) ;;
  esac
  printf '%-10s %s  loaded: %s\n' "$verdict" "$id" "${got:--}"
done

[ -n "$WANT" ] || exit 0
printf -- '-> %s: %d/%d FIRED, %d MISROUTED, %d NONE\n' \
  "$WANT" "$fired" "$total" "$misrouted" "$none"
