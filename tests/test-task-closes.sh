#!/bin/bash
# tests/test-task-closes.sh — `task-registry closes <pr>`, the post-merge check (#146).
#
# A merge made with a workflow's GITHUB_TOKEN does not fire GitHub's closing
# keywords (tasks/solutions/bugs/bot-merged-pr-leaves-linked-issue-open.md), so
# the automation that merged runs this command afterwards: every issue the PR
# links and left open is closed through the registry's gated close, or named
# with a non-zero exit. `select` is the backstop for a merge nobody ran it
# after: an open issue whose closing PR merged is never a candidate, and each
# one is named with the `closes` line that repairs it.
#
# Every case runs the real CLI in-process with `GitHubProvider._run` answered
# from a canned scenario. That is the seam every gh call crosses, so the argv
# pinned here is the argv gh would receive — and unlike the bash gh mock on
# PATH, it is reachable from Python on Windows.
. "$(dirname "$0")/lib.sh"

py_module .agents/skills/task-registry/scripts
SCRIPTS="${PYTHONPATH%%:*}"   # py_module puts the declared directory first
CLI="$SCRIPTS/task-registry.py"
PY="$TEST_PYTHON"

F="$(fixture_dir)"
mkdir -p "$F/tasks" "$F/stub"
printf '# Tasks\n' > "$F/tasks/todo.md"
fixture_copy task-registry/task-tracking.md "$F/docs/task-tracking.md"

# The scenario is JSON: `prs` maps a PR number to its state and either the
# [repository, issue] pairs its body closes (rendered as `closes <ref>` clauses)
# or a verbatim `body`; `issues` maps an issue number to OPEN or
# CLOSED; `fail` lists issue numbers whose close gh rejects; `unreadable` lists
# issue numbers gh cannot read (transferred or deleted since the merge).
# For `select`: `backlog` lists the open issues as [number, labels, linked PR
# numbers, state_reason]; `pr_states` maps a linked PR number to the state its
# timeline event carries (a PR missing from it has no readable state);
# `timeline_fail` makes the timeline read fail.
cat > "$F/stub/closes_stub.py" <<'EOF'
import importlib.util
import json
import re
import sys

from registry.providers.base import ProviderError
from registry.providers.github import GitHubProvider

LABELS = ("needs-investigation", "bug", "enhancement", "design-decision", "simplify",
          "tech-debt", "documentation", "now", "next", "in-progress")
HERE = "fixture-owner/fixture-repo"


def timeline(issue, entries, pr_states):
    """Cross-referenced events the way the REST timeline lists them.

    An entry is a PR number in this repository or a [repository, number] pair;
    the PR's state, merge time, repository and body ride on `source.issue`. A
    PR absent from `pr_states` carries no state at all.
    """
    events = []
    for entry in entries:
        repo, number = entry if isinstance(entry, list) else (HERE, entry)
        state = pr_states.get(str(number))
        source = {
            "number": number, "body": f"Closes #{issue}",
            "repository_url": f"https://api.github.com/repos/{repo}",
            "pull_request": {"merged_at": "2026-10-02T00:00:00Z" if state == "MERGED" else None},
        }
        if state is not None:
            source["state"] = "open" if state == "OPEN" else "closed"
        events.append({"event": "cross-referenced", "source": {"type": "issue", "issue": source}})
    return events


def run_cli(cli, scenario, argv):
    calls = []
    prs, issues = scenario.get("prs", {}), scenario.get("issues", {})
    failing, unreadable = set(scenario.get("fail", ())), set(scenario.get("unreadable", ()))
    backlog, pr_states = scenario.get("backlog", []), scenario.get("pr_states", {})

    def answer(command, code, output, check):
        if check and code != 0:
            raise ProviderError(f"github: `{' '.join(command[:3])}` exited {code} — {output}")
        return code, output

    def fake_run(self, command, check=True, input=None):
        command = list(command)
        calls.append(" ".join(command) + (f" {input}" if input else ""))
        # Everything is REST: `gh api [--method M] repos/<owner>/<name>/issues[/<n>|?<query>]`,
        # a write's payload on stdin.
        method = command[command.index("--method") + 1] if "--method" in command else "GET"
        path = ""
        if command[1] == "api":
            path = next((arg for arg in command[2:] if not arg.startswith("-") and arg != method), "")
        pull_read = re.fullmatch(rf"repos/{HERE}/pulls/(\d+)", path)
        issue_read = re.fullmatch(rf"repos/{HERE}/issues/(\d+)", path)
        timeline_read = re.fullmatch(rf"repos/{HERE}/issues/(\d+)/timeline\?.*", path)
        if pull_read:
            number = pull_read.group(1)
            if number not in prs:
                return answer(command, 1, f"HTTP 404: Not Found (https://api.github.com/{path})", check)
            pr = prs[number]
            body = pr.get("body")
            if body is None:
                body = ", ".join(
                    f"closes {'' if repo == HERE else repo}#{issue}" for repo, issue in pr.get("closes", [])
                )
            return answer(command, 0, json.dumps({
                "number": int(number), "state": "open" if pr["state"] == "OPEN" else "closed",
                "merged": pr["state"] == "MERGED", "body": body,
                "html_url": f"https://github.com/{HERE}/pull/{number}",
            }), check)
        if issue_read and method == "PATCH":
            number = issue_read.group(1)
            if number in failing:
                return answer(command, 1, "HTTP 403: Resource not accessible by integration", check)
            return answer(command, 0, json.dumps({"number": int(number), "state": "closed"}), check)
        if issue_read:
            number = issue_read.group(1)
            if number in unreadable:
                return answer(command, 1, f"HTTP 404: Not Found (https://api.github.com/{path})", check)
            return answer(command, 0, json.dumps({
                "number": int(number), "title": f"Issue {number}", "body": "", "labels": [],
                "state": issues.get(number, "OPEN").lower(),
                "html_url": f"https://github.com/fixture-owner/fixture-repo/issues/{number}",
                "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z",
                "assignees": [],
            }), check)
        if timeline_read:
            if scenario.get("timeline_fail"):
                return answer(command, 1, "HTTP 502: Bad Gateway", check)
            events = [timeline(issue, links, pr_states) for issue, _, links, _ in backlog
                      if str(issue) == timeline_read.group(1)]
            return answer(command, 0, json.dumps(events[0] if events else []), check)
        if path.startswith(f"repos/{HERE}/labels?"):
            return answer(command, 0, json.dumps([{"name": name} for name in LABELS]), check)
        if path.startswith(f"repos/{HERE}/issues?"):
            return answer(command, 0, json.dumps([
                {
                    "number": issue, "title": f"Issue {issue}", "body": "", "state": "open",
                    "state_reason": reason.lower() or None, "labels": [{"name": name} for name in labels],
                    "html_url": f"https://github.com/{HERE}/issues/{issue}",
                    "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z",
                    "assignees": [],
                }
                for issue, labels, links, reason in backlog
            ]), check)
        raise AssertionError("unexpected gh call: " + " ".join(command))

    GitHubProvider._run = fake_run
    spec = importlib.util.spec_from_file_location("task_registry_cli", cli)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        code = module.main(argv)
    except SystemExit as exc:  # argparse refuses an unknown command this way
        code = exc.code
    sys.stdout.flush()
    print(f"exit={code}")
    for call in calls:
        print(f"call: {call}")


if __name__ == "__main__":
    with open(sys.argv[2], encoding="utf-8") as handle:
        scenario = json.load(handle)
    run_cli(sys.argv[1], scenario, sys.argv[3:])
EOF

# registry <scenario-json> <cli args...> — the CLI's output, then
# `exit=<code>`, then one `call: <argv>` line per gh invocation. The scenario
# travels through a file: MSYS rewrites path-like argv on Windows, and JSON
# naming `owner/repo` looks like one.
registry() {
  printf '%s' "$1" > "$F/scenario.json"; shift
  (cd "$F" && \
    "$PY" "$F/stub/closes_stub.py" "$CLI" "$F/scenario.json" "$@" 2>&1)
}
closes() { local scenario="$1"; shift; registry "$scenario" closes "$@"; }

HERE='fixture-owner/fixture-repo'

# --- provider: what one merged pull request closes ---------------------------
out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",92]]}},"issues":{"91":"OPEN","92":"CLOSED"}}' '#141' --apply --approve)"
assert_contains "$out" "call: gh api repos/$HERE/pulls/141" \
  "provider (AC13): the pull request is read with GET /pulls/{n}, never gh pr view"
assert_not_contains "$out" "call: gh pr" \
  "provider (AC13): no gh pr subcommand runs -- GraphQL is refused in the sandbox"
assert_contains "$out" "call: gh api repos/$HERE/issues/91" \
  "provider: each linked issue's state is read over REST before anything is closed"

out="$(closes '{"prs":{"141":{"state":"OPEN","closes":[["'$HERE'",91]]}}}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a pull request that is not merged exits 1"
assert_contains "$out" "not merged (state open)" "provider: the refusal says the pull request is not merged, naming its REST state"
assert_not_contains "$out" "repos/$HERE/issues" "provider: nothing is read or closed for an unmerged pull request"

out="$(closes '{"prs":{"141":{"state":"CLOSED","closes":[["'$HERE'",91]]}}}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a pull request closed without merging exits 1"
assert_contains "$out" "not merged (state closed)" \
  "provider: closed is not merged -- REST's state alone cannot tell them apart, so merged is read"

out="$(closes '{}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a pull request GitHub cannot find exits 1"
assert_contains "$out" "HTTP 404" "provider: the refusal carries gh's HTTP status"

out="$(closes '{}' 'abc' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a reference that is not a number exits 1"
assert_not_contains "$out" "call: gh" "provider: a reference that is not a number never reaches gh"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["other-owner/other-repo",5]]}},"issues":{"91":"OPEN"}}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a closing reference in another repository exits 1"
assert_contains "$out" "other-owner/other-repo#5" "provider: the foreign reference is named"
assert_contains "$out" "nothing was closed" "provider: the refusal says nothing was closed"
assert_not_contains "$out" "--method PATCH" "provider: no issue is closed while one is out of reach"

# --- provider (AC13): GitHub's closing keywords, read off the body ---------
# REST exposes no closing-issue relation, so the body is parsed the way GitHub
# reads it: each keyword binds to the ONE reference after it (Decision 13).
for keyword in close closes closed fix fixes fixed resolve resolves resolved Closes FIXED; do
  out="$(closes '{"prs":{"141":{"state":"MERGED","body":"'"$keyword"' #91"}},"issues":{"91":"OPEN"}}' '#141' --apply --approve)"
  assert_contains "$out" "call: gh api --method PATCH repos/$HERE/issues/91" \
    "provider (AC13): \`$keyword #91\` in the body closes #91"
done
for body in "Fixes: #91" "Resolves $HERE#91" "closes https://github.com/$HERE/issues/91" \
            "Closes #91, closes #93" "Closes #91 and later fixes #91 again"; do
  out="$(closes '{"prs":{"141":{"state":"MERGED","body":"'"$body"'"}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141' --apply --approve)"
  assert_contains "$out" "closes: closed #91" "provider (AC13): \`$body\` closes #91"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c "PATCH repos/$HERE/issues/91 ")" \
    "provider (AC13): \`$body\` closes #91 exactly once"
done
assert_contains "$out" "exit=0" "provider (AC13): a body naming #91 twice exits 0"
out="$(closes '{"prs":{"141":{"state":"MERGED","body":"Closes #91, closes #93"}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141' --apply --approve)"
assert_contains "$out" "closes: closed #93" "provider (AC13): a keyword repeated per reference closes each one"
out="$(closes '{"prs":{"141":{"state":"MERGED","body":"Closes #91, #93"}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141' --apply --approve)"
assert_contains "$out" "closes: closed #91" "provider (AC13): a keyword binds to the reference right after it"
assert_not_contains "$out" "issues/93" \
  "provider (AC13): a chained reference without its own keyword is not closed -- GitHub would not close it either"
out="$(closes '{"prs":{"141":{"state":"MERGED","body":"See #91; the example body is `Closes #93`"}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141' --apply --approve)"
assert_contains "$out" "nothing to do" \
  "provider (AC13): a bare mention and a keyword inside a code span close nothing"
assert_not_contains "$out" "--method PATCH" "provider (AC13): no issue is closed for a body without a live closing clause"

out="$(closes '{}' '#141' --provider local --apply --approve)"
assert_contains "$out" "exit=1" "provider: a tracker without pull requests refuses with exit 1"
assert_contains "$out" "local:" "provider: the refusal names the provider"

# --- command: close what the merge left open ---------------------------------
out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",92]]}},"issues":{"91":"OPEN","92":"CLOSED"}}' '#141' --apply --approve)"
assert_contains "$out" "exit=0" "command: closing every open linked issue exits 0"
assert_contains "$out" "call: gh api --method PATCH repos/$HERE/issues/91 --input - "'{"state": "closed", "state_reason": "completed"}' \
  "command: the open linked issue is closed through PATCH /issues/{n}, the payload on stdin"
assert_not_contains "$out" "call: gh api --method PATCH repos/$HERE/issues/92" "command: an issue already closed is left alone"
assert_contains "$out" "closes: closed #91" "command: each closed issue gets one line"
assert_not_contains "$out" "timeline" \
  "command: closes reads no linked PR state -- a lookup only select needs must not fail the repair"

out="$(closes '{"prs":{"140":{"state":"MERGED","closes":[["'$HERE'",92]]}},"issues":{"92":"CLOSED"}}' '#140' --apply --approve)"
assert_contains "$out" "exit=0" "command: a merge that closed everything exits 0"
assert_contains "$out" "nothing to do" "command: a merge that closed everything says nothing to do"
assert_not_contains "$out" "--method PATCH" "command: nothing is closed when nothing is open"

out="$(closes '{"prs":{"7":{"state":"MERGED","closes":[]}}}' '#7' --apply --approve)"
assert_contains "$out" "exit=0" "command: a merged pull request with no closing reference exits 0"
assert_contains "$out" "nothing to do" "command: a merged pull request with no closing reference says nothing to do"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",93]]}},"issues":{"91":"OPEN","93":"OPEN"},"fail":["91"]}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "command: a failed close exits 1"
assert_contains "$out" "#91 is still open" "command: the issue that could not be closed is named"
assert_contains "$out" "call: gh api --method PATCH repos/$HERE/issues/93" "command: a failed close does not stop the rest"
assert_contains "$out" "closes: closed #93" "command: the issues that did close are still reported"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",93]]}},"issues":{"93":"OPEN"},"unreadable":["91"]}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "command: an issue that cannot be read exits 1"
assert_contains "$out" "could not read #91" "command: an unreadable issue is reported as unread"
assert_not_contains "$out" "#91 is still open" "command: an unreadable issue is never reported as open"
assert_contains "$out" "closes: closed #93" "command: an unreadable issue does not stop the rest"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",93]]}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141')"
assert_contains "$out" "exit=1" "command: a dry run with open linked issues exits 1"
assert_contains "$out" "#91 is still open" "command: a dry run names the first open issue"
assert_contains "$out" "#93 is still open" "command: a dry run names every open issue"
assert_contains "$out" "pass --apply" "command: a dry run says how to perform the close"
assert_not_contains "$out" "--method PATCH" "command: a dry run closes nothing"

out="$(closes '{}')"
assert_contains "$out" "exit=2" "command: no pull request reference is a usage error"
assert_contains "$out" "requires the merged pull request" "command: the usage error says what is missing"
assert_not_contains "$out" "call: gh" "command: a usage error reaches no tracker"

# --- select: an issue a merge left open is never a candidate -----------------
# #155's closing PR merged without closing it (stranded); #120's is still open
# (in flight); #130's was closed unmerged; #140 was reopened after its PR
# merged; #160's PR state cannot be read; #10 has no link at all.
BACKLOG='"backlog":[[155,["bug","now"],[189],""],[120,["bug","now"],[144],""],[130,["bug","next"],[131],""],[140,["bug","next"],[141],"REOPENED"],[160,["bug","next"],[161],""],[10,["bug","next"],[],""],[180,["enhancement","now"],[181],""]]'
STATES='"pr_states":{"189":"MERGED","144":"OPEN","131":"CLOSED","141":"MERGED"}'
out="$(registry "{$BACKLOG,$STATES}" select --routine fix)"
assert_contains "$out" "exit=0" "select: a stranded issue does not fail the routine's pick"
assert_contains "$out" "stranded:      #155" "select: an open issue whose closing PR merged is named as stranded"
assert_contains "$out" "task-registry closes '#189' --apply --approve" \
  "select: the stranded line carries the closes command that repairs it"
assert_not_contains "$out" "candidate:     155 —" "select: a stranded issue is never the candidate"
assert_not_contains "$out" "candidate:     120 —" "select: an issue whose closing PR is open stays in flight"
assert_not_contains "$out" "stranded:      #140" "select: an issue reopened after its PR merged is not stranded"
assert_not_contains "$out" "stranded:      #120" "select: an open closing PR is in flight, not stranded"
assert_contains "$out" "remaining:     2 other candidate(s)" \
  "select: the pool is #130 (PR closed unmerged), #140 (reopened) and #10 -- #160's unreadable PR counts as in flight"
assert_contains "$out" "call: gh api repos/$HERE/issues/155/timeline?per_page=100&page=1" \
  "select: a candidate's linked PRs are read from its REST timeline, paged"
assert_not_contains "$out" "issues/180/timeline" \
  "select: the timeline is read after the kind filter -- another routine's issue costs nothing"
assert_contains "$out" "checked:       6 candidate(s) for linked pull requests" \
  "select: the routine's own pool is what was checked"

out="$(registry '{"backlog":[[155,["bug","now"],[189],""]],"pr_states":{"189":"MERGED"}}' select --routine fix)"
assert_contains "$out" "exit=0" "select: a pool holding only a stranded issue exits 0"
assert_contains "$out" "candidate:     none" "select: a pool holding only a stranded issue has no candidate"
assert_contains "$out" "stranded:      #155" "select: a stranded issue is named even when nothing is claimable"

out="$(registry '{"backlog":[[170,["bug","next"],[["other-owner/other-repo",171]],""]],"pr_states":{"171":"MERGED"}}' select --routine fix)"
assert_not_contains "$out" "stranded:" \
  "select: a merged PR in another repository is not stranded -- closes cannot reach it"
assert_contains "$out" "candidate:     170 —" \
  "select: an issue whose only closing PR merged elsewhere is not in flight"

out="$(registry '{"backlog":[[10,["bug","next"],[],""]]}' select --routine fix)"
assert_contains "$out" "candidate:     10 —" "select: an unlinked issue is still a candidate"
assert_contains "$out" "call: gh api repos/$HERE/issues/10/timeline" \
  "select: every candidate's timeline is read -- an unlinked issue proves itself clean"

out="$(registry "{$BACKLOG,\"timeline_fail\":true}" select --routine fix)"
assert_contains "$out" "exit=1" "select: a failed timeline read exits 1"
assert_contains "$out" "timeline" "select: the failed timeline read is named"
assert_not_contains "$out" "candidate:" "select: no candidate is offered when linked PR state is unknown"

# --- the skill documents the command ----------------------------------------
SKILL_MD="${SCRIPTS%/scripts}/SKILL.md"
assert_file_contains "$SKILL_MD" "closes <pull-request>" \
  "skill: the argument hint names closes"
assert_file_contains "$SKILL_MD" '| `closes` |' \
  "skill: the command table has a closes row"
assert_file_contains "$SKILL_MD" '### `closes`' \
  "skill: closes has its own section"
assert_file_contains "$SKILL_MD" "stranded:" \
  "skill: select's stranded line is documented"

finish
