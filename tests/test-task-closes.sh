#!/bin/bash
# tests/test-task-closes.sh — `task-registry closes <pr>`, the post-merge check (#146).
#
# A merge made with a workflow's GITHUB_TOKEN does not fire GitHub's closing
# keywords (tasks/solutions/bugs/bot-merged-pr-leaves-linked-issue-open.md), so
# the automation that merged runs this command afterwards: every issue the PR
# links and left open is closed through the registry's gated close, or named
# with a non-zero exit.
#
# Every case runs the real CLI in-process with `GitHubProvider._run` answered
# from a canned scenario. That is the seam every gh call crosses, so the argv
# pinned here is the argv gh would receive — and unlike the bash gh mock on
# PATH, it is reachable from Python on Windows.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
CLI="$SCRIPTS/task-registry.py"
PY="$TEST_PYTHON"
TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

F="$(mktemp -d)"; TMP_DIRS+=("$F")
mkdir -p "$F/tasks" "$F/docs" "$F/stub"
printf '# Tasks\n' > "$F/tasks/todo.md"
cat > "$F/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = github
repository = fixture-owner/fixture-repo
```
EOF

# The scenario is JSON: `prs` maps a PR number to its state and the
# [repository, issue] pairs it closes; `issues` maps an issue number to OPEN or
# CLOSED; `fail` lists issue numbers whose close gh rejects.
cat > "$F/stub/closes_stub.py" <<'EOF'
import importlib.util
import json
import sys

from registry.providers.base import ProviderError
from registry.providers.github import GitHubProvider


def run_cli(cli, scenario, argv):
    calls = []
    prs, issues = scenario.get("prs", {}), scenario.get("issues", {})
    failing = set(scenario.get("fail", ()))

    def answer(command, code, output, check):
        if check and code != 0:
            raise ProviderError(f"github: `{' '.join(command[:3])}` exited {code} — {output}")
        return code, output

    def fake_run(self, command, check=True):
        command = list(command)
        calls.append(" ".join(command))
        verb, number = command[1:3], command[-1]
        if verb == ["pr", "view"]:
            if number not in prs:
                return answer(command, 1, f"Could not resolve to a PullRequest with the number of {number}.", check)
            pr = prs[number]
            refs = [
                {
                    "number": int(issue),
                    "url": f"https://github.com/{repo}/issues/{issue}",
                    "repository": {"name": repo.split("/")[1], "owner": {"login": repo.split("/")[0]}},
                }
                for repo, issue in pr.get("closes", [])
            ]
            return answer(command, 0, json.dumps({"state": pr["state"], "closingIssuesReferences": refs}), check)
        if verb == ["issue", "view"]:
            return answer(command, 0, json.dumps({
                "number": int(number), "title": f"Issue {number}", "body": "", "labels": [],
                "state": issues.get(number, "OPEN"),
                "url": f"https://github.com/fixture-owner/fixture-repo/issues/{number}",
                "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-01T00:00:00Z",
                "assignees": [], "closedByPullRequestsReferences": [],
            }), check)
        if verb == ["issue", "close"]:
            if number in failing:
                return answer(command, 1, "HTTP 403: Resource not accessible by integration", check)
            return answer(command, 0, "", check)
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

# closes <scenario-json> <cli args...> — the CLI's output, then `exit=<code>`,
# then one `call: <argv>` line per gh invocation. The scenario travels through
# a file: MSYS rewrites path-like argv on Windows, and JSON naming
# `owner/repo` looks like one.
closes() {
  printf '%s' "$1" > "$F/scenario.json"; shift
  (cd "$F" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" \
    "$PY" "$F/stub/closes_stub.py" "$CLI" "$F/scenario.json" closes "$@" 2>&1)
}

HERE='fixture-owner/fixture-repo'

# --- provider: what one merged pull request closes ---------------------------
out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",92]]}},"issues":{"91":"OPEN","92":"CLOSED"}}' '#141' --apply --approve)"
assert_contains "$out" "call: gh pr view --repo $HERE --json state,closingIssuesReferences -- 141" \
  "provider: closing references are read with gh pr view, the number after --"
assert_contains "$out" "call: gh issue view --repo $HERE" \
  "provider: each linked issue's state is read before anything is closed"

out="$(closes '{"prs":{"141":{"state":"OPEN","closes":[["'$HERE'",91]]}}}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a pull request that is not merged exits 1"
assert_contains "$out" "not merged" "provider: the refusal says the pull request is not merged"
assert_not_contains "$out" "call: gh issue" "provider: nothing is read or closed for an unmerged pull request"

out="$(closes '{}' 'abc' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a reference that is not a number exits 1"
assert_not_contains "$out" "call: gh" "provider: a reference that is not a number never reaches gh"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["other-owner/other-repo",5]]}},"issues":{"91":"OPEN"}}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "provider: a closing reference in another repository exits 1"
assert_contains "$out" "other-owner/other-repo#5" "provider: the foreign reference is named"
assert_contains "$out" "nothing was closed" "provider: the refusal says nothing was closed"
assert_not_contains "$out" "call: gh issue close" "provider: no issue is closed while one is out of reach"

out="$(closes '{}' '#141' --provider local --apply --approve)"
assert_contains "$out" "exit=1" "provider: a tracker without pull requests refuses with exit 1"
assert_contains "$out" "local:" "provider: the refusal names the provider"

# --- command: close what the merge left open ---------------------------------
out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",92]]}},"issues":{"91":"OPEN","92":"CLOSED"}}' '#141' --apply --approve)"
assert_contains "$out" "exit=0" "command: closing every open linked issue exits 0"
assert_contains "$out" "call: gh issue close --repo $HERE -- 91" "command: the open linked issue is closed through gh issue close"
assert_not_contains "$out" "call: gh issue close --repo $HERE -- 92" "command: an issue already closed is left alone"
assert_contains "$out" "closes: closed #91" "command: each closed issue gets one line"

out="$(closes '{"prs":{"140":{"state":"MERGED","closes":[["'$HERE'",92]]}},"issues":{"92":"CLOSED"}}' '#140' --apply --approve)"
assert_contains "$out" "exit=0" "command: a merge that closed everything exits 0"
assert_contains "$out" "nothing to do" "command: a merge that closed everything says nothing to do"
assert_not_contains "$out" "call: gh issue close" "command: nothing is closed when nothing is open"

out="$(closes '{"prs":{"7":{"state":"MERGED","closes":[]}}}' '#7' --apply --approve)"
assert_contains "$out" "exit=0" "command: a merged pull request with no closing reference exits 0"
assert_contains "$out" "nothing to do" "command: a merged pull request with no closing reference says nothing to do"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",93]]}},"issues":{"91":"OPEN","93":"OPEN"},"fail":["91"]}' '#141' --apply --approve)"
assert_contains "$out" "exit=1" "command: a failed close exits 1"
assert_contains "$out" "#91 is still open" "command: the issue that could not be closed is named"
assert_contains "$out" "call: gh issue close --repo $HERE -- 93" "command: a failed close does not stop the rest"
assert_contains "$out" "closes: closed #93" "command: the issues that did close are still reported"

out="$(closes '{"prs":{"141":{"state":"MERGED","closes":[["'$HERE'",91],["'$HERE'",93]]}},"issues":{"91":"OPEN","93":"OPEN"}}' '#141')"
assert_contains "$out" "exit=1" "command: a dry run with open linked issues exits 1"
assert_contains "$out" "#91 is still open" "command: a dry run names the first open issue"
assert_contains "$out" "#93 is still open" "command: a dry run names every open issue"
assert_contains "$out" "pass --apply" "command: a dry run says how to perform the close"
assert_not_contains "$out" "call: gh issue close" "command: a dry run closes nothing"

out="$(closes '{}')"
assert_contains "$out" "exit=2" "command: no pull request reference is a usage error"
assert_contains "$out" "requires the merged pull request" "command: the usage error says what is missing"
assert_not_contains "$out" "call: gh" "command: a usage error reaches no tracker"

# --- the skill documents the command ----------------------------------------
SKILL_MD="$REPO/.agents/skills/task-registry/SKILL.md"
assert_file_contains "$SKILL_MD" "closes <pull-request>" \
  "skill: the argument hint names closes"
assert_file_contains "$SKILL_MD" '| `closes` |' \
  "skill: the command table has a closes row"
assert_file_contains "$SKILL_MD" '### `closes`' \
  "skill: closes has its own section"

finish
