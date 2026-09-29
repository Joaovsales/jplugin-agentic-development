#!/usr/bin/env python3
"""publish_evidence.py — push e2e screenshots to an orphan branch and print the PR section.

A VISUAL acceptance criterion passes only with a PNG on disk
(`<artifact dir>/<short-sha>/<AC-id>.png`, laid out by `e2e_evidence.py`), but a reviewer reads the PR,
not the author's disk. This script commits those PNGs to the project's own
`e2e-evidence` branch, which shares no history with the feature branch or
`master`, and prints a `## Visual evidence` markdown section whose image links
are pinned to that evidence commit. `/wrap-up-session` inserts the section in
the PR body.

Why it is built from plumbing: the feature branch must stay exactly as it was
(HEAD, index, working tree). The tree is assembled in a temporary
`GIT_INDEX_FILE` with `hash-object -w` / `update-index --cacheinfo` /
`write-tree` / `commit-tree`, seeded with `read-tree` of the fetched tip when the
branch already exists. No checkout, stash or worktree switch ever happens.

The artifact layout belongs to `e2e_evidence.py` (the check that enforces it);
this script loads that module from the sibling skill by path and refuses to run
without it, rather than keep a copy of the layout that could drift.

The evidence branch only grows: merged PRs link to its commits, so it is never
force-pushed. A rejected push (another session published first) is retried once
from a fresh fetch; a second rejection, or any other git failure on the first
attempt, is loud (`evidence: publish failed`, exit 1).

`--sha` is required: wrap-up commits before it writes the PR, so HEAD has moved
past the sha the walkthrough saved its PNGs under, and a HEAD default would
publish nothing without saying so.
Re-running for the same short-sha overwrites the same paths in a new commit; when
the rebuilt tree equals the tip's tree no commit is made and the tip is linked.

Opt-out and fallback: an `E2E evidence: local` line below the AGENTS.md end
marker (anywhere in AGENTS.md when the file has no marker) or a non-GitHub
`origin` pushes nothing and lists the local PNG paths instead.

stdout is only the markdown section (empty when there is nothing to publish);
stderr is one `evidence:` status line. Standard library only.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

BRANCH = "e2e-evidence"
REF = f"refs/heads/{BRANCH}"
END_MARKER = "<!-- jplugin-agentic-development:end -->"
OPT_OUT_RE = re.compile(r"^[ \t]*E2E evidence:[ \t]*local[ \t]*$", re.IGNORECASE | re.MULTILINE)
#: scp-style, https and ssh:// GitHub remotes, with or without `.git`.
GITHUB_URL_RE = re.compile(
    r"^(?:git@github\.com:|https?://(?:[^@/]+@)?github\.com/|ssh://git@github\.com/)"
    r"(?P<owner>[A-Za-z0-9_.-]+)/(?P<repo>[A-Za-z0-9_.-]+?)(?:\.git)?/?$"
)

CHECKER = Path(__file__).resolve().parents[2] / "verify-evidence" / "scripts" / "e2e_evidence.py"


def load_checker(path: Path):
    """The module that owns the artifact layout; loud when it is not beside us."""
    if not path.is_file():
        sys.exit(f"evidence: publish failed (layout owner {path} not found)")
    spec = importlib.util.spec_from_file_location("e2e_evidence", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses resolves its module by name
    spec.loader.exec_module(module)
    return module


layout = load_checker(CHECKER)

#: (short-sha, AC-id, absolute PNG path)
Entry = Tuple[str, str, Path]


class GitError(RuntimeError):
    """A git command exited non-zero."""


class PushRejected(GitError):
    """The remote moved on: another session published first."""

#: git's wording for a push refused because the remote tip moved. English only,
#: so the push is run under LC_ALL=C (`push_env`).
REJECTED_RE = re.compile(r"\[rejected\]|non-fast-forward|fetch first")


def git(repo: Path, *args: str, env: Optional[Dict[str, str]] = None) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        raise GitError(f"git {args[0]}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def collect_entries(repo: Path, shas: Sequence[str]) -> List[Entry]:
    entries: List[Entry] = []
    for sha in shas:
        for png in layout.artifact_pngs(repo, sha):
            entries.append((sha, png.stem, png))
    return entries


def github_slug(repo: Path) -> Optional[str]:
    result = subprocess.run(
        ["git", "-C", str(repo), "config", "--get", "remote.origin.url"],
        capture_output=True, text=True,
    )
    match = GITHUB_URL_RE.match(result.stdout.strip())
    return f"{match['owner']}/{match['repo']}" if match else None


def opted_out_local(repo: Path) -> bool:
    agents = repo / "AGENTS.md"
    if not agents.is_file():
        return False
    text = agents.read_text(encoding="utf-8")
    below = text.split(END_MARKER, 1)[1] if END_MARKER in text else text
    return OPT_OUT_RE.search(below) is not None


def visibility_marker(slug: str) -> str:
    """` — public repo`, nothing for private, ` — visibility unknown` otherwise.

    `gh` being absent, offline or unauthenticated does not fail the publish,
    but it must not read as private: the marker exists so a public publish is
    never silent.
    """
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{slug}", "--jq", ".private"],
            capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return " — visibility unknown"
    answer = result.stdout.strip() if result.returncode == 0 else ""
    return {"false": " — public repo", "true": ""}.get(answer, " — visibility unknown")


def fetch_tip(repo: Path) -> Optional[str]:
    if not git(repo, "ls-remote", "origin", REF).strip():
        return None
    git(repo, "fetch", "--quiet", "origin", REF)
    return git(repo, "rev-parse", "FETCH_HEAD^{commit}").strip()


def build_tree(repo: Path, tip: Optional[str], entries: Sequence[Entry]) -> str:
    with tempfile.TemporaryDirectory() as scratch:
        env = {**os.environ, "GIT_INDEX_FILE": os.path.join(scratch, "index")}
        if tip:
            git(repo, "read-tree", tip, env=env)
        for sha, ac_id, png in entries:
            blob = git(repo, "hash-object", "-w", str(png)).strip()
            git(repo, "update-index", "--add", "--cacheinfo",
                f"100644,{blob},{sha}/{ac_id}.png", env=env)
        return git(repo, "write-tree", env=env).strip()


def commit_env(repo: Path) -> Dict[str, str]:
    """Repo identity when configured; a neutral one for CI containers without it."""
    env = dict(os.environ)
    ident = subprocess.run(["git", "-C", str(repo), "var", "GIT_COMMITTER_IDENT"], capture_output=True)
    if ident.returncode != 0:
        for role in ("AUTHOR", "COMMITTER"):
            env.setdefault(f"GIT_{role}_NAME", "jplugin evidence")
            env.setdefault(f"GIT_{role}_EMAIL", "evidence@localhost")
    return env


def make_commit(repo: Path, tip: Optional[str], entries: Sequence[Entry]) -> Optional[str]:
    """Return a new commit on `tip`, or None when the tree is already the tip's."""
    tree = build_tree(repo, tip, entries)
    if tip and git(repo, "rev-parse", f"{tip}^{{tree}}").strip() == tree:
        return None
    shas = ", ".join(dict.fromkeys(sha for sha, _, _ in entries))
    parent = ["-p", tip] if tip else []
    message = f"evidence: {shas} ({len(entries)} screenshots)"
    return git(repo, "commit-tree", tree, *parent, "-m", message, env=commit_env(repo)).strip()


def push_env() -> Dict[str, str]:
    """The caller's environment with git's messages pinned to English."""
    return {**os.environ, "LC_ALL": "C"}


def publish_once(repo: Path, entries: Sequence[Entry]) -> str:
    tip = fetch_tip(repo)
    commit = make_commit(repo, tip, entries)
    if commit is None:
        return str(tip)
    try:
        git(repo, "push", "origin", f"{commit}:{REF}", env=push_env())
    except GitError as error:
        raise PushRejected(str(error)) if REJECTED_RE.search(str(error)) else error
    return commit


def publish(repo: Path, entries: Sequence[Entry]) -> str:
    """Publish, retrying a rejected push once from a fresh fetch. Raises GitError otherwise."""
    try:
        return publish_once(repo, entries)
    except PushRejected:
        return publish_once(repo, entries)


def render_published(slug: str, commit: str, entries: Sequence[Entry]) -> str:
    lines = ["## Visual evidence", ""]
    for sha, ac_id, _ in entries:
        url = f"https://github.com/{slug}/blob/{commit}/{sha}/{ac_id}.png?raw=true"
        lines.append(f"![{ac_id}]({url})")
    return "\n".join(lines)


def render_local(repo: Path, entries: Sequence[Entry], reason: str) -> str:
    lines = ["## Visual evidence (local only)", "", reason, ""]
    lines += [f"- {png.relative_to(repo).as_posix()}" for _, _, png in entries]
    return "\n".join(lines)


def local_reason(slug: Optional[str]) -> str:
    if slug is None:
        return "Screenshots were not published: `origin` is not a GitHub remote."
    return "Screenshots were not published: AGENTS.md sets `E2E evidence: local`."


def run(repo: Path, shas: Sequence[str]) -> int:
    entries = collect_entries(repo, shas)
    if not entries:
        print("evidence: none", file=sys.stderr)
        return 0
    slug = github_slug(repo)
    if slug is None or opted_out_local(repo):
        print(render_local(repo, entries, local_reason(slug)))
        print(f"evidence: local {len(entries)}", file=sys.stderr)
        return 0
    try:
        commit = publish(repo, entries)
    except GitError as error:
        # One line: git's stderr can span several, and the caller greps one.
        print(f"evidence: publish failed ({' '.join(str(error).split())})", file=sys.stderr)
        return 1
    print(render_published(slug, commit, entries))
    print(f"evidence: published {len(entries)} to {slug}{visibility_marker(slug)}", file=sys.stderr)
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--repo", default=".", help="feature repo (default: current directory)")
    parser.add_argument("--sha", action="append", required=True,
                        help="short sha the walkthrough saved its PNGs under (repeatable)")
    args = parser.parse_args(argv)
    return run(Path(args.repo).resolve(), args.sha)


if __name__ == "__main__":
    sys.exit(main())
