#!/usr/bin/env python3
"""gh_pr.py — the wrap-up's pull-request operations, over `gh api` (REST).

Claude Code's cloud sandbox reaches GitHub through a proxy that accepts REST
and refuses GraphQL, and every `gh pr` subcommand is GraphQL-backed, so the
pull-request steps of `/wrap-up-session` and its closure actions run through
this script instead (specs/github-rest-in-sandboxes.md, Decision 8):

    gh_pr.py create --base <branch> --title <title> --body-file <file> [--draft]
    gh_pr.py view <number or branch> --json <fields> [-q .<field>]
    gh_pr.py edit <number> --body-file <file>
    gh_pr.py ready <number> [--undo]
    gh_pr.py checks <number> [--watch] [--required]
    gh_pr.py mergeable <number>

`view` knows the fields `number`, `url`, `body`, `mergeable` and `headSha`,
printed as one JSON object, or as one field's bare value with `-q .<field>`.
`mergeable` reads MERGEABLE, CONFLICTING or UNKNOWN — the words the closure
prose already uses — from REST's true, false and null.

`ready` posts to the sandbox proxy's `ccr/ready_for_review` and
`ccr/convert_to_draft` routes; a 404 there means no proxy, so outside the
sandbox it runs `gh pr ready [--undo]` instead and says which path it took
(Decision 9). `checks --required` reads the base branch's required checks and
watches every check when that read is refused or the branch is unprotected.

Exit codes tell a plain "no" from a failed ask, because the terminal PR
assertion depends on that distinction:
    0  done: the pull request exists, every check passed, the branch merges
    1  no: `view` found no pull request; a check failed or is still pending;
       the branch conflicts with its base
    2  GitHub could not be asked; `gh`'s stderr is quoted on stderr

Standard library plus `gh`, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from typing import Callable, Dict, List, Optional, Sequence, Tuple
from urllib.parse import quote

# The one GitHub-remote parser the wrap-up scripts share.
from publish_evidence import GITHUB_URL_RE

#: REST's `mergeable` tri-state in the words the closure actions read.
MERGEABLE = {True: "MERGEABLE", False: "CONFLICTING", None: "UNKNOWN"}
#: Check conclusions that do not fail a watch.
GREEN = ("success", "neutral", "skipped")
#: The fields `view --json` answers, each read off the REST pull request.
VIEW_FIELDS: Dict[str, Callable[[Dict], object]] = {
    "number": lambda pull: pull.get("number"),
    "url": lambda pull: pull.get("html_url", ""),
    "body": lambda pull: pull.get("body") or "",
    "mergeable": lambda pull: MERGEABLE[pull.get("mergeable")],
    "headSha": lambda pull: (pull.get("head") or {}).get("sha", ""),
}
#: Seconds between polls (`checks --watch`, a null `mergeable`) and the watch
#: budget. Environment overrides exist so the tests do not sleep.
POLL_SECONDS = float(os.environ.get("GH_PR_POLL_SECONDS", "10"))
WATCH_SECONDS = float(os.environ.get("GH_PR_WATCH_SECONDS", "1800"))
#: A null `mergeable` right after a push is GitHub still computing it; it is
#: re-read this many times before being reported unknown.
MERGEABLE_RETRIES = 3
HTTP_STATUS_RE = re.compile(r"HTTP (\d{3})")


class GhError(Exception):
    """A refusal with the exit code it earns: 1 for "no", 2 for "could not ask"."""

    def __init__(self, message: str, code: int = 2) -> None:
        super().__init__(message)
        self.code = code


# ---------------------------------------------------------------- processes
def run(command: Sequence[str], stdin: Optional[str] = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            list(command), input=stdin, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GhError(f"`{command[0]}` could not run — {exc}") from exc


def git(*args: str) -> str:
    completed = run(["git", *args])
    if completed.returncode != 0:
        raise GhError(f"git {args[0]}: {completed.stderr.strip() or completed.stdout.strip()}")
    return completed.stdout.strip()


def repo_slug() -> str:
    match = GITHUB_URL_RE.match(git("config", "--get", "remote.origin.url"))
    if not match:
        raise GhError("origin is not a GitHub remote, so there is no pull request to reach")
    return f"{match['owner']}/{match['repo']}"


def api(method: str, path: str, payload: Optional[Dict] = None) -> subprocess.CompletedProcess:
    """`gh api [--method M] <path> [--input -]`, the payload on stdin (Decision 5)."""
    command = ["gh", "api"]
    if method != "GET":
        command += ["--method", method]
    command.append(path)
    stdin = None
    if payload is not None:
        command += ["--input", "-"]
        stdin = json.dumps(payload)
    return run(command, stdin)


def ask(method: str, path: str, payload: Optional[Dict] = None, tolerate: Sequence[int] = ()):
    """The parsed answer; None when the HTTP status is one in `tolerate`; else GhError(2)."""
    completed = api(method, path, payload)
    if completed.returncode != 0:
        status = HTTP_STATUS_RE.search(completed.stderr or "")
        if status and int(status.group(1)) in tolerate:
            return None
        detail = (completed.stderr or completed.stdout).strip() or "no output"
        raise GhError(f"gh api {method} {path} failed — {detail}")
    try:
        return json.loads(completed.stdout or "null")
    except json.JSONDecodeError as exc:
        raise GhError(f"gh api {method} {path} answered something other than JSON — {exc}") from exc


def path(slug: str, *parts: str) -> str:
    return "/".join([f"repos/{slug}", *parts])


def as_pr_number(value: str) -> Optional[str]:
    """The digits of a pull request number (a leading `#` tolerated, the way
    `gh` takes it), or None when `value` is something else, such as a branch."""
    number = value.lstrip("#")
    return number if number.isdigit() else None


def pr_number(value: str) -> str:
    """A pull request number fit for a path segment, or a parser refusal.

    Every subcommand's `number` argument is parsed through this type, so
    anything but digits never reaches `gh`: unchecked, `../issues/7` would
    become a route.
    """
    number = as_pr_number(value)
    if number is None:
        raise argparse.ArgumentTypeError(f"{value!r} is not a pull request number")
    return number


def read_file(name: str) -> str:
    with open(name, encoding="utf-8") as handle:
        return handle.read()


# ------------------------------------------------------------- pull requests
def read_pull(slug: str, number: str) -> Dict:
    pull = ask("GET", path(slug, "pulls", number), tolerate=(404,))
    if pull is None:
        raise GhError(f"no pull request #{number}", 1)
    return pull


def find_pull(slug: str, branch: str) -> Dict:
    """The newest pull request whose head is `branch`, whatever its state."""
    owner = slug.split("/")[0]
    # A branch name may carry `&` or `#`; quoted, it stays one query value.
    head = f"{owner}:{quote(branch, safe='/')}"
    found = ask("GET", path(slug, f"pulls?head={head}&state=all&per_page=1"))
    if not found:
        raise GhError(f"no pull request for {branch}", 1)
    return found[0]


def check_results(slug: str, sha: str, wanted: Optional[set]) -> List[Tuple[str, str]]:
    """(name, state) per check run and commit status on `sha`; `wanted` narrows by name."""
    runs = ask("GET", path(slug, "commits", sha, "check-runs?per_page=100")).get("check_runs") or []
    statuses = ask("GET", path(slug, "commits", sha, "status")).get("statuses") or []
    results = [
        (run.get("name", ""), (run.get("conclusion") or "pending") if run.get("status") == "completed" else "pending")
        for run in runs
    ] + [(status.get("context", ""), status.get("state") or "pending") for status in statuses]
    if wanted is not None:
        results = [(name, state) for name, state in results if name in wanted]
    return results


def required_checks(slug: str, base: str) -> Optional[set]:
    """The base branch's required check names, or None when every check counts."""
    protection = ask(
        "GET", path(slug, "branches", base, "protection", "required_status_checks"), tolerate=(403, 404),
    )
    if protection is None:
        note(f"checks: {base} declares no required checks (branch not protected) — watching all checks")
        return None
    names = set(protection.get("contexts") or []) | {
        check.get("context", "") for check in protection.get("checks") or []
    }
    names.discard("")
    if not names:
        note(f"checks: {base} declares no required checks — watching all checks")
        return None
    return names


def note(message: str) -> None:
    """A progress line on stderr, so stdout stays the results a caller parses."""
    print(message, file=sys.stderr)


# -------------------------------------------------------------- subcommands
def cmd_create(args: argparse.Namespace) -> int:
    slug = repo_slug()
    head = git("branch", "--show-current")
    if not head:
        raise GhError("not on a branch — a pull request needs a head branch")
    pull = ask("POST", path(slug, "pulls"), {
        "title": args.title, "head": head, "base": args.base,
        "body": read_file(args.body_file), "draft": bool(args.draft),
    })
    print(pull.get("html_url", ""))
    return 0


def cmd_view(args: argparse.Namespace) -> int:
    slug = repo_slug()
    number = as_pr_number(args.target)
    pull = read_pull(slug, number) if number else find_pull(slug, args.target)
    fields = [field.strip() for field in args.json.split(",") if field.strip()]
    unknown = [field for field in fields if field not in VIEW_FIELDS]
    if unknown:
        raise GhError(f"unknown field(s) {', '.join(unknown)} — view knows {', '.join(VIEW_FIELDS)}")
    facts = {field: VIEW_FIELDS[field](pull) for field in fields}
    if args.query is None:
        print(json.dumps(facts))
        return 0
    name = args.query.lstrip(".")
    if name not in facts:
        raise GhError(f"-q {args.query} names a field --json did not ask for")
    value = facts[name]
    print(value if isinstance(value, str) else json.dumps(value))
    return 0


def cmd_edit(args: argparse.Namespace) -> int:
    slug = repo_slug()
    ask("PATCH", path(slug, "pulls", args.number), {"body": read_file(args.body_file)})
    print(f"edited #{args.number}")
    return 0


def cmd_ready(args: argparse.Namespace) -> int:
    slug = repo_slug()
    verb = "drafted" if args.undo else "marked ready"
    route = "convert_to_draft" if args.undo else "ready_for_review"
    if ask("POST", path(slug, "pulls", args.number, "ccr", route), tolerate=(404,)) is not None:
        print(f"ready: #{args.number} {verb} through the ccr route")
        return 0
    # A 404 on that route means no sandbox proxy, so GraphQL is reachable here.
    command = ["gh", "pr", "ready", args.number] + (["--undo"] if args.undo else [])
    completed = run(command)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or "no output"
        raise GhError(f"no ccr route here, and `{' '.join(command)}` failed — {detail}")
    print(f"ready: #{args.number} {verb} through gh pr ready (no ccr route)")
    return 0


def cmd_checks(args: argparse.Namespace) -> int:
    slug = repo_slug()
    pull = read_pull(slug, args.number)
    sha = (pull.get("head") or {}).get("sha", "")
    wanted = required_checks(slug, (pull.get("base") or {}).get("ref", "")) if args.required else None
    deadline = time.monotonic() + WATCH_SECONDS
    while True:
        results = check_results(slug, sha, wanted)
        pending = [name for name, state in results if state == "pending"]
        if not args.watch or not pending or time.monotonic() >= deadline:
            break
        time.sleep(POLL_SECONDS)
    for name, state in results:
        print(f"{state}\t{name}")
    if not results:
        print("checks: none")
        return 0
    if pending:
        print(f"checks: {'timeout' if args.watch else 'pending'} — {', '.join(pending)} still running")
        return 1
    failed = [name for name, state in results if state not in GREEN]
    if failed:
        print(f"checks: fail — {', '.join(failed)}")
        return 1
    print(f"checks: pass — {len(results)} check(s)")
    return 0


def cmd_mergeable(args: argparse.Namespace) -> int:
    slug = repo_slug()
    for attempt in range(MERGEABLE_RETRIES + 1):
        pull = read_pull(slug, args.number)
        if pull.get("mergeable") is not None:
            break
        if attempt < MERGEABLE_RETRIES:
            time.sleep(POLL_SECONDS)
    state = MERGEABLE[pull.get("mergeable")]
    if state == "CONFLICTING":
        print(f"mergeable: conflicting with {(pull.get('base') or {}).get('ref', 'the base branch')}")
        return 1
    print("mergeable: clean" if state == "MERGEABLE" else "mergeable: unknown")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create", help="open a pull request for the current branch")
    create.add_argument("--base", required=True)
    create.add_argument("--title", required=True)
    create.add_argument("--body-file", required=True)
    create.add_argument("--draft", action="store_true")
    create.set_defaults(run=cmd_create)

    view = commands.add_parser("view", help="read a pull request by number or head branch")
    view.add_argument("target")
    view.add_argument("--json", required=True, help="comma-separated: " + ",".join(VIEW_FIELDS))
    view.add_argument("-q", "--query", help="print one field's bare value, e.g. -q .url")
    view.set_defaults(run=cmd_view)

    edit = commands.add_parser("edit", help="replace a pull request's body")
    edit.add_argument("number", type=pr_number)
    edit.add_argument("--body-file", required=True)
    edit.set_defaults(run=cmd_edit)

    ready = commands.add_parser("ready", help="mark ready for review, or draft with --undo")
    ready.add_argument("number", type=pr_number)
    ready.add_argument("--undo", action="store_true")
    ready.set_defaults(run=cmd_ready)

    checks = commands.add_parser("checks", help="the head commit's check runs and statuses")
    checks.add_argument("number", type=pr_number)
    checks.add_argument("--watch", action="store_true")
    checks.add_argument("--required", action="store_true")
    checks.set_defaults(run=cmd_checks)

    mergeable = commands.add_parser("mergeable", help="clean, conflicting or unknown")
    mergeable.add_argument("number", type=pr_number)
    mergeable.set_defaults(run=cmd_mergeable)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.run(args)
    except GhError as exc:
        print(f"gh_pr.py: {exc}", file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    sys.exit(main())
