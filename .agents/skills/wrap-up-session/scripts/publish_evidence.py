#!/usr/bin/env python3
"""publish_evidence.py — push e2e screenshots to an orphan branch and print the PR section.

A VISUAL acceptance criterion passes only with a PNG on disk
(`tasks/e2e-artifacts/<short-sha>/<AC-id>.png`), but a reviewer reads the PR,
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

The evidence branch only grows: merged PRs link to its commits, so it is never
force-pushed. A rejected push (another session published first) is retried once
from a fresh fetch; a second failure is loud (`evidence: publish failed`, exit 1).
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
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

BRANCH = "e2e-evidence"
REF = f"refs/heads/{BRANCH}"
ARTIFACT_DIR = "tasks/e2e-artifacts"
END_MARKER = "<!-- jplugin-agentic-development:end -->"
OPT_OUT_RE = re.compile(r"^[ \t]*E2E evidence:[ \t]*local[ \t]*$", re.IGNORECASE | re.MULTILINE)
#: scp-style, https and ssh:// GitHub remotes, with or without `.git`.
GITHUB_URL_RE = re.compile(
    r"^(?:git@github\.com:|https?://(?:[^@/]+@)?github\.com/|ssh://git@github\.com/)"
    r"(?P<owner>[A-Za-z0-9_.-]+)/(?P<repo>[A-Za-z0-9_.-]+?)(?:\.git)?/?$"
)

#: (short-sha, AC-id, absolute PNG path)
Entry = Tuple[str, str, Path]


class GitError(RuntimeError):
    """A git command exited non-zero."""


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
        for png in sorted((repo / ARTIFACT_DIR / sha).glob("*.png")):
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


def is_public_repo(slug: str) -> bool:
    """True only when `gh` positively says the repo is public.

    `gh` being absent, offline or unauthenticated is not an error for the
    publish: the marker is advisory, so those cases read as "unknown".
    """
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{slug}", "--jq", ".private"],
            capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and result.stdout.strip() == "false"


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


def commit_env() -> Dict[str, str]:
    """Repo identity when configured; a neutral one for CI containers without it."""
    env = dict(os.environ)
    if subprocess.run(["git", "var", "GIT_COMMITTER_IDENT"], capture_output=True).returncode != 0:
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
    return git(repo, "commit-tree", tree, *parent, "-m", message, env=commit_env()).strip()


def publish_once(repo: Path, entries: Sequence[Entry]) -> str:
    tip = fetch_tip(repo)
    commit = make_commit(repo, tip, entries)
    if commit is None:
        return str(tip)
    git(repo, "push", "origin", f"{commit}:{REF}")
    return commit


def publish(repo: Path, entries: Sequence[Entry]) -> str:
    """Publish, retrying once from a fresh fetch. Raises GitError on the second failure."""
    try:
        return publish_once(repo, entries)
    except GitError:
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
    marker = " — public repo" if is_public_repo(slug) else ""
    print(f"evidence: published {len(entries)} to {slug}{marker}", file=sys.stderr)
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--repo", default=".", help="feature repo (default: current directory)")
    parser.add_argument("--sha", action="append", help="short sha to publish (repeatable; default HEAD)")
    args = parser.parse_args(argv)
    repo = Path(args.repo).resolve()
    shas = args.sha or [git(repo, "rev-parse", "--short", "HEAD").strip()]
    return run(repo, shas)


if __name__ == "__main__":
    sys.exit(main())
