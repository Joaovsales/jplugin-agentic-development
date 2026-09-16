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
#   "type":"tool_use","id":"toolu_...","name":"Skill","input":{"skill":"plan","args":"..."}
# A load is counted only from a real tool-use block. Anything looser matches a
# candidate's own console output and inflates every result.
#
# The anchor requires `"type":"tool_use"` earlier in the same JSON object.
# Transcripts now carry the tool *schema* inline (`{"name":"Skill",
# "description":"Invoke a skill..."}`), and a bare `"name":"Skill"` matched
# that on every candidate, so a run in which nobody loaded anything died as
# "format changed" instead of grading NONE — eight clean transcripts, zero
# measurements (2026-09-16). `[^{}]*` keeps the match inside one object.
BLOCK='"type":[[:space:]]*"tool_use"[^{}]*"name":[[:space:]]*"Skill"'

# The drift guard must not share the extractor's key-order assumption, or a
# tool-use object serialised name-before-type would grade NONE in silence. It
# also anchors on `"input":{`, which the inline schema never carries (its key is
# `input_schema`), so the schema stays ordinary content for the guard too.
DRIFT='"name":[[:space:]]*"Skill"[^{}]*"input":[[:space:]]*\{'

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
  if [ -z "$got" ] && grep -qE "$BLOCK|$DRIFT" "$f"; then
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
