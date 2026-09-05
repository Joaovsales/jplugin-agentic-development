#!/usr/bin/env python3
"""Deterministic retirement for /sync.

`/sync` copies files in; it never deletes. A path present in a project but
absent from the template is either retired upstream or project-specific, and
until now nothing recorded which — so the answer was re-derived by a model on
every run, and two runs against one template commit could produce different
trees.

This script replaces that judgement with set arithmetic:

    retire = project paths under syncable roots
           - template paths under the same roots
           - paths matching a .claude/sync-keep pattern

Nothing is classified at run time. Given the same template revision, the same
project tree and the same sync-keep, the retirement set is identical on every
run and from every project branch.

Stdlib only, Python 3.8+.
"""

from __future__ import annotations

import argparse
import dataclasses
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Sequence, Set, Tuple

KEEP_FILE = ".claude/sync-keep"
CANDIDATE_FILE = ".claude/sync-keep.candidate"
SKILL_DOC = ".agents/skills/sync/SKILL.md"

# `[`, `]`, `{`, `}` and `!` are the glob syntax this format does *not* accept.
# Silently ignoring them would let an author record intent that protects
# nothing, which is the failure mode the whole allowlist exists to prevent.
UNSUPPORTED_GLOB_CHARS = "[]{}!"

# A syncable root must be a direct subdirectory of one of the two harness trees:
# `.agents/skills/`, `.claude/hooks/`, and so on. The doc block that names the
# roots is read from the *template* — a remote repository, or in manual-diff mode
# a directory under /tmp — so without this the template chooses what a
# file-deleting tool is pointed at. A hostile or simply mistaken block naming
# `src/` deletes the project's source; naming `.claude/` sweeps in the never-sync
# files, including the allowlist this whole mechanism depends on. Staying inside
# the repository is not sufficient, because every one of those paths already is.
SYNCABLE_ROOT_PATTERN = re.compile(r"^\.(agents|claude)/[A-Za-z0-9_-]+/$")


class PruneError(Exception):
    """A directory that could not be removed, carrying which one it was."""

    def __init__(self, directory: str, reason: str) -> None:
        super().__init__(f"{directory}: {reason}")
        self.directory = directory
        self.reason = reason


class RetireError(Exception):
    """A failure that must stop the run before anything is deleted."""


# ------------------------------------------------------- patterns and matching


def _pattern_to_regex(pattern: str) -> str:
    """Translate the three supported tokens; everything else is a literal.

    Hand-written rather than `fnmatch`, whose `*` happily crosses `/` and whose
    `[seq]` syntax this format does not accept. Borrowing it would silently
    widen every allowlist entry.
    """
    # TODO(shortcut): this and `match_path` duplicate
    # `.agents/skills/wrap-up-session/scripts/spec-reconcile.py`, which has the
    # same three-token semantics. Not shared yet because that file's hyphenated
    # name makes it importable only through `importlib`, and the two validators
    # have different contracts — a sync-keep pattern must additionally name a
    # syncable root. Upgrade path: extract the matcher into an importable module
    # both scripts read (filed as `glob-matcher-shared-module`).
    # Kept as a `#` comment, not docstring prose: the /wrap-up-session shortcut
    # ledger greps for comment syntax, and a marker it cannot see is a deferral
    # that rots silently.
    out: List[str] = []
    index = 0
    while index < len(pattern):
        if pattern.startswith("**", index):
            out.append(".*")
            index += 2
        elif pattern[index] == "*":
            out.append("[^/]*")
            index += 1
        elif pattern[index] == "?":
            out.append("[^/]")
            index += 1
        else:
            out.append(re.escape(pattern[index]))
            index += 1
    return "".join(out)


def match_path(pattern: str, path: str) -> bool:
    return re.fullmatch(_pattern_to_regex(pattern), path) is not None


def validate_pattern(pattern: str, line_number: int, roots: Sequence[str]) -> str:
    """Return `pattern` if this program will interpret it, else raise.

    Every rejection is a value that would otherwise fail *silently*: an
    unsupported token matches nothing, so the path it was meant to protect is
    retired anyway and the author learns about it from the deletion. The line
    number travels with the message because an allowlist is edited by hand.
    """
    where = f"{KEEP_FILE} line {line_number}"
    if pattern.startswith("/") or re.match(r"^[A-Za-z]:", pattern):
        raise RetireError(f"{where}: absolute path not allowed: `{pattern}`")
    if "\\" in pattern:
        raise RetireError(f"{where}: use POSIX separators, not backslashes: `{pattern}`")
    if ".." in pattern.split("/"):
        raise RetireError(f"{where}: `..` traversal not allowed: `{pattern}`")
    if pattern.endswith("/"):
        raise RetireError(
            f"{where}: `{pattern}` ends in `/`, so it matches no file and protects "
            f"nothing — did you mean `{pattern}**`?"
        )
    bad = [c for c in UNSUPPORTED_GLOB_CHARS if c in pattern]
    if bad:
        raise RetireError(
            f"{where}: unsupported glob syntax {''.join(bad)!r} in `{pattern}` "
            f"— only *, ? and ** are accepted"
        )
    if not _reaches_a_root(pattern, roots):
        raise RetireError(
            f"{where}: `{pattern}` is outside every syncable root "
            f"({', '.join(roots)}) — it can never protect anything"
        )
    return pattern


def _reaches_a_root(pattern: str, roots: Sequence[str]) -> bool:
    """Can this pattern match any path under any root?

    Tested on the pattern's literal head — everything before its first glob
    token — because a prefix test alone contradicts the matcher: `**` crosses
    `/`, so `.claude/**` does reach `.claude/hooks/`, and rejecting it with
    "it can never protect anything" told the author the opposite of the truth.
    A head that is a prefix of a root, or prefixed by one, reaches it.
    """
    cut = min((i for i in (pattern.find("*"), pattern.find("?")) if i != -1), default=len(pattern))
    head = pattern[:cut]
    return any(head.startswith(root) or root.startswith(head) for root in roots)


def read_keep_patterns(repo: str, roots: Sequence[str]) -> Optional[List[str]]:
    """Read `.claude/sync-keep`, or return None when the project has no file.

    None is *bootstrap*, an empty list is a recorded "nothing here is
    project-specific". Collapsing the two would make an unconfigured project
    look like one that had opted into deletion.
    """
    path = os.path.join(repo, KEEP_FILE)
    if not os.path.isfile(path):
        # S7: absent and unreadable are different states. A dangling symlink or a
        # directory here is not "no allowlist" -- reporting bootstrap for it would
        # claim the project never configured one, and write a candidate over the
        # top of whatever is actually there.
        if os.path.lexists(path):
            raise RetireError(
                f"{KEEP_FILE} exists but is not a regular file — refusing to treat "
                f"it as an absent allowlist"
            )
        return None
    patterns: List[str] = []
    text = _read_text(path)
    for line_number, raw in enumerate(text.splitlines(), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        patterns.append(validate_pattern(stripped, line_number, roots))
    return patterns


# ------------------------------------------------------------- syncable roots


def _validate_root(entry: str, origin: str) -> str:
    """Refuse a root that is not one of the directories `/sync` manages.

    Errs toward scanning less: a legitimate new root that does not fit the shape
    is simply not retired from, which leaves stale files behind. The opposite
    failure deletes files the tool was never meant to touch.
    """
    if not SYNCABLE_ROOT_PATTERN.match(entry):
        raise RetireError(
            f"{origin}: `{entry}` is not a syncable root — a root must be a direct "
            f"subdirectory of .agents/ or .claude/ (for example .agents/skills/). "
            f"Refusing to point a file-deleting tool at it"
        )
    return entry


def parse_syncable_roots(text: str, origin: str) -> List[str]:
    """Read the directory roots out of the `## Syncable Paths` doc block.

    The block is parsed rather than copied so this script becomes a *consumer*
    of the one list `tests/test-syncable-paths.sh` already pins, instead of an
    eighth hand-maintained duplicate of it.

    The block's file entries (`CLAUDE.md`, `.claude/settings.json`) are dropped:
    retirement is undefined for a file — it has no project-only paths inside it
    — and the checkout step already handles them.
    """
    directories: List[str] = []
    in_block = False
    for line in text.splitlines():
        if line.startswith("## Syncable Paths"):
            in_block = True
            continue
        if in_block and re.match(r"^#{2,} ", line):
            break
        if in_block and "→" in line:
            entry = line.split("→", 1)[0].strip()
            if entry.endswith("/"):
                directories.append(_validate_root(entry, origin))
    if not directories:
        raise RetireError(
            f"{origin}: no `## Syncable Paths` doc block with directory roots — "
            f"cannot determine what to scan"
        )
    return sorted(set(directories))


# ---------------------------------------------------------------- inventories


def _read_text(path: str) -> str:
    """Read a file the operator controls, reporting failures on our own channel.

    `open` raises OSError and UnicodeDecodeError, and `main` only catches
    RetireError -- so an unreadable or non-UTF-8 allowlist escaped as a
    traceback, while SKILL.md promises this tool "fails loudly" in the sense of
    a controlled stop.
    """
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise RetireError(f"cannot read {path}: {exc}")


def _git(repo: str, *args: str) -> str:
    """Run git against a tree whose configuration is untrusted input.

    `--from-dir` points this at a template checkout the project did not write,
    and git reads that repository's own `.git/config` — where `core.fsmonitor`
    names a command git executes on `ls-files`. The checkout is same-uid, so
    `safe.directory` never fires, and the read happens during the Step 3 dry
    run, before the user has approved anything. Pinning the exec-capable knobs
    off on the command line beats them: `-c` outranks repository config.
    """
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    result = subprocess.run(
        ("git", "-C", repo, "-c", "core.fsmonitor=", "-c", "core.hooksPath=" + os.devnull)
        + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        # surrogateescape, not replace: this string is fed back to os.remove, and
        # a replacement character produces a path that can never round-trip.
        errors="surrogateescape",
        env=env,
    )
    if result.returncode != 0:
        raise RetireError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def _one_line(exc: Exception) -> str:
    """Collapse a multi-line git error into a single report line.

    `render` emits one line per item and its readers grep it, while git's
    fatals routinely run to three lines with a usage hint appended.
    """
    return " ".join(
        "".join(char for char in token if char.isprintable())
        for token in str(exc).split()
    )


def _history_is_truncated(where: str, revision: str) -> bool:
    """True when this revision's history stops at a shallow graft.

    A shallow clone makes git treat its boundary commits as roots, but the
    commit *objects* still record the parents that were never fetched. So a
    root whose object names a parent is a graft — at any clone depth.

    Both earlier probes were wrong in opposite directions.
    `--is-shallow-repository` describes the repository, and in `--from-ref` the
    revision lives in the *project*, so a shallow project suppressed provenance
    for a complete template ref. Counting commits caught only depth 1, so a
    `--depth 5` clone silently produced a *different* retirement set from the
    same commit SHA — the non-determinism this whole feature exists to remove.
    """
    for commit in _git(
        where, "rev-list", "--max-parents=0", "--end-of-options", revision
    ).split():
        # Headers only. `cat-file commit` emits headers, a blank line, then the
        # free-text message -- so a commit message containing a line that begins
        # `parent ` was read as a graft, and one such message upstream would
        # report `provenance: unavailable` for every downstream project forever.
        header = _git(where, "cat-file", "commit", commit).split("\n\n", 1)[0]
        if re.search(r"^parent ", header, re.M):
            return True
    return False


def _project_blobs(repo: str, paths: Sequence[str]) -> Dict[str, str]:
    """Hash each project file as it exists **on disk**, not as it is indexed.

    On disk is the load-bearing part. A file with uncommitted local edits hashes
    to something no template commit ever produced, so it falls out of the
    retirement set and is held for a human — which is the only way to avoid
    destroying work that `git checkout` cannot bring back.
    """
    if not paths:
        return {}
    hashed = _git(repo, "hash-object", "--", *paths).split()
    return dict(zip(paths, hashed))


def template_history_blobs(
    where: str, revision: str, roots: Sequence[str]
) -> Dict[str, Set[str]]:
    """Every blob the template has ever held at each path under these roots.

    Paths alone cannot answer "is this the template's file?". `.claude/hooks/`
    is a syncable root and `pre-commit.sh` is a name both a template and a
    project reach for, so path membership would delete a file this project
    wrote itself and never synced. The blob is what distinguishes them.

    `--raw` carries the pre- and post-image blob of every change, so one walk
    yields the full content history without re-reading a tree per commit.

    `-z` is load-bearing, not a parsing convenience. Without it git C-quotes
    paths holding non-ASCII bytes, and whether it does is decided by
    `core.quotePath` — read from the repository being inspected, which in
    `--from-dir` mode is the untrusted template checkout. This map is keyed on
    those strings while the project side uses raw bytes, so one line in someone
    else's `.git/config` moved a file between "held for a human" and "deleted",
    and made the two source modes disagree for identical content.
    """
    stream = _git(
        where, "log", "--pretty=format:", "--raw", "--no-abbrev", "-z",
        "--diff-filter=AMRD", "--end-of-options", revision, "--", *roots,
    )
    blobs: Dict[str, Set[str]] = {}
    fields = stream.split("\0")
    index = 0
    while index < len(fields):
        record = fields[index]
        if not record.startswith(":"):
            index += 1
            continue
        columns = record.split()
        if len(columns) < 5:
            index += 1
            continue
        # A rename or copy names both the old path and the new one, and the
        # blob belongs to each; everything else names one.
        wanted = 2 if columns[4][:1] in ("R", "C") else 1
        for path in (p for p in fields[index + 1 : index + 1 + wanted] if p):
            for sha in columns[2:4]:
                if sha and set(sha) != {"0"}:
                    blobs.setdefault(path, set()).add(sha)
        index += 1 + wanted
    return blobs


def template_history_paths(
    repo: str, ref: Optional[str], directory: Optional[str], roots: Sequence[str]
) -> Tuple[Optional[Dict[str, Set[str]]], str]:
    """Every path the template has *ever* carried under these roots.

    This is the record that answers "is this project-specific?" without asking a
    model. A path the template once shipped and no longer does was retired
    upstream; a path the template never carried is the project's own. Before
    this, only the template's current state was consulted, so the two were
    indistinguishable and a project without a sync-keep had to keep both.

    Returns `(None, reason)` when the history is not available -- a truncated
    clone has one commit, and its "history" is just its current state, which
    would silently classify every retired path as project-specific. The reason
    travels with it because every git failure here used to be reported as
    "shallow template history": a missing ref, an unreadable object and a
    genuinely shallow clone are three different problems with three different
    fixes, and the operator was shown only the third.

    The probe measures the **revision**, not the repository. `--is-shallow-
    repository` is a property of the whole repo, and in `--from-ref` mode the
    revision lives in the *project* -- so a project that is itself a `--depth 1`
    checkout (what CI does by default) reported "shallow template history" and
    retired nothing, however complete the fetched template ref was. Counting
    commits reachable from the revision asks the question actually being asked,
    in both modes, and needs no branch.
    """
    where = directory or repo
    revision = "HEAD" if directory else str(ref)
    try:
        if _history_is_truncated(where, revision):
            return None, (
                f"{revision} has truncated history — a shallow clone carries no "
                f"record of what the template used to ship. Re-clone without "
                f"--depth (--filter=blob:none keeps it cheap)"
            )
        return template_history_blobs(where, revision, roots), ""
    except RetireError as exc:
        return None, _one_line(exc)


def project_paths(repo: str, roots: Sequence[str]) -> List[str]:
    """Tracked files under the syncable roots.

    Tracked, not walked: `/sync` delivers files through `git checkout`, so an
    untracked file under a root was never synced in and is not this program's
    to delete. It also keeps the two template modes agreeing — a walk would see
    build residue such as `__pycache__` that `git ls-tree` can never report.

    `isfile` excludes broken symlinks, symlinks to directories, and submodule
    gitlinks *at the leaf*, so none of those is ever retired. That is the safe
    direction — the tool leaves them rather than guessing whether `os.remove` is
    the right verb — but it does mean a retired-upstream symlink of those shapes
    needs manual removal. A tracked symlink to a *file* is retired normally, and
    removes the link, never its target.

    It says nothing about the **directories above** the leaf: `isfile` follows
    every component, so a symlinked directory inside a syncable root resolves
    this path somewhere else entirely. `_confined_target` is what refuses that,
    at the deletion itself — this filter is not a containment check and must not
    be read as one.

    Filtered to what is actually on disk, because `ls-files` reports the *index*.
    A path this script deleted on an earlier run stays in the index until the
    removal is staged, so an unfiltered read would list it again, compute it as
    project-only a second time, and fail on `os.remove` — making a second
    `--apply` before the user commits crash rather than report nothing to do.
    """
    stream = _git(repo, "ls-files", "-z", "--", *roots)
    return sorted(
        path
        for path in stream.split("\0")
        if path and os.path.isfile(os.path.join(repo, path))
    )


def template_paths_from_ref(repo: str, ref: str, roots: Sequence[str]) -> List[str]:
    stream = _git(
        repo, "ls-tree", "-r", "--name-only", "-z", "--end-of-options", ref,
        "--", *roots,
    )
    return sorted(p for p in stream.split("\0") if p)


def template_paths_from_dir(directory: str, roots: Sequence[str]) -> List[str]:
    """Template inventory from a checkout on disk.

    Read through git when the checkout is a repository — which is how `/sync`
    obtains it — so all three inventories mean the same thing by "the paths
    under a root". A bare walk counts gitignored residue as template content,
    which both breaks the `--from-ref`/`--from-dir` equivalence and lets
    `assert_roots_present` be satisfied by files the committed tree lacks,
    masking the wrong checkout in the one guard that exists to catch it.
    """
    if os.path.isdir(os.path.join(directory, ".git")):
        stream = _git(directory, "ls-files", "-z", "--", *roots)
        return sorted(p for p in stream.split("\0") if p)
    found: List[str] = []
    for root in roots:
        base = os.path.join(directory, root)
        for current, _dirs, names in os.walk(base):
            for name in names:
                absolute = os.path.join(current, name)
                found.append(os.path.relpath(absolute, directory).replace(os.sep, "/"))
    return sorted(found)


def read_template_doc(repo: str, ref: Optional[str], directory: Optional[str]) -> str:
    """Read the roots doc block from the *template*, never from the project.

    The template is the authority on what the roots contain. Reading the
    project's copy would let a project on a stale branch scan yesterday's root
    list, which is the non-determinism this feature removes.
    """
    if directory:
        path = os.path.join(directory, SKILL_DOC)
        if not os.path.isfile(path):
            raise RetireError(f"template checkout has no {SKILL_DOC}: {directory}")
        return _read_text(path)
    # --end-of-options at the sink: `main` rejects a ref starting with `-`, but
    # that guard is 400 lines away and the tests already import this module and
    # call in directly, so it is one refactor from being bypassed. Without it
    # `git show "--output=...:path"` is read as an option.
    return _git(repo, "show", "--end-of-options", f"{ref}:{SKILL_DOC}")


def usable_roots(
    template: Sequence[str], roots: Sequence[str], source: str
) -> Tuple[List[str], List[str]]:
    """Split declared roots into those the template can vouch for, and those it cannot.

    A root the template has no files under is ambiguous. Retiring from it would
    compute `everything the project has` minus `nothing` and delete the
    project's entire copy — the one mistake this script must never make quietly.

    **One** empty root is read as an ordinary upstream deletion and skipped, so
    that a single commit cannot disable retirement everywhere: two roots in this
    template hold a single file each, and removing either used to exit 1 for
    every downstream project and retire nothing at all.

    **Several** empty roots are read as a wrong or partial source and refused.
    That distinction is what keeps the catastrophe guard: a truncated checkout
    empties many roots at once, while upstream retires them one release at a
    time. The threshold matters because the doc block itself lives under
    `.agents/skills/`, so that root is non-empty in *any* template this script
    can read — an all-empty test would never fire for it, and a broken clone
    carrying only the sync skill would otherwise retire every other skill the
    project has.
    """
    present = [r for r in roots if any(p.startswith(r) for p in template)]
    empty = [r for r in roots if r not in present]
    if len(empty) > 1:
        raise RetireError(
            f"template source {source} contains no files under {len(empty)} of "
            f"{len(roots)} syncable roots ({', '.join(empty)}) — refusing a "
            f"source this incomplete; retiring against it would delete the "
            f"project's copy of each"
        )
    if not present:
        raise RetireError(
            f"template source {source} contains no files under any syncable root "
            f"({', '.join(roots)}) — refusing to treat an empty template as a "
            f"complete one"
        )
    return present, empty


# ------------------------------------------------------------- the retirement


@dataclasses.dataclass
class Plan:
    roots: List[str]
    source: str
    retire: List[str] = dataclasses.field(default_factory=list)
    kept: List[Tuple[str, str]] = dataclasses.field(default_factory=list)
    # `bootstrap` discriminates: it selects whether `candidates` or
    # `retire`/`kept` carry meaning, and both consumers branch on it. Modelled
    # as one type with a flag rather than two types, which keeps the invalid
    # combinations representable — see the `glob-matcher-shared-module` sibling
    # follow-up for the split this wants eventually.
    candidates: List[str] = dataclasses.field(default_factory=list)
    unmatched: List[str] = dataclasses.field(default_factory=list)
    # Patterns that reach only a skipped root: inactive this run, but the only
    # thing that will protect the file when the template restores that root.
    # Reporting them as `unmatched` invited the operator to delete them.
    dormant: List[str] = dataclasses.field(default_factory=list)
    bootstrap: bool = False
    # Declared in the doc block but empty in the template: reported, never
    # scanned. Retirement is undefined for a root the template cannot vouch for.
    skipped_roots: List[str] = dataclasses.field(default_factory=list)
    # Empty means provenance was read -- distinct from "read it, nothing was
    # ever retired". Non-empty is why it could not be, quoted to the operator.
    provenance_reason: str = ""


def split_by_allowlist(
    project_only: Sequence[str], patterns: Sequence[str]
) -> Tuple[List[str], List[Tuple[str, str]], List[str]]:
    """Split project-only paths into those to retire and those a pattern saved.

    Each kept path carries the pattern that matched it, so a survivor is
    traceable to the line that saved it — "kept" alone would make a sync-keep
    entry that silently stopped matching look like one still doing its job.

    Also returns the patterns that matched nothing. That is not an error — a
    path may legitimately not exist yet — but it is the state a stale allowlist
    is in just before it stops protecting something, and it is invisible unless
    reported.
    """
    retire: List[str] = []
    kept: List[Tuple[str, str]] = []
    for path in project_only:
        matched = next((pat for pat in patterns if match_path(pat, path)), None)
        if matched is None:
            retire.append(path)
        else:
            kept.append((path, matched))
    used = {pattern for _, pattern in kept}
    return retire, kept, [pattern for pattern in patterns if pattern not in used]


def compute_plan(repo: str, ref: Optional[str], directory: Optional[str]) -> Plan:
    """Resolve both inventories and reduce them to what this run would delete."""
    source = ref or directory or ""
    roots = parse_syncable_roots(read_template_doc(repo, ref, directory), source)
    template = (
        template_paths_from_dir(directory, roots)
        if directory
        else template_paths_from_ref(repo, str(ref), roots)
    )
    scanned, skipped = usable_roots(template, roots, source)
    known = set(template)
    project_only = [p for p in project_paths(repo, scanned) if p not in known]
    patterns = read_keep_patterns(repo, roots)
    if patterns is None:
        # Bootstrap. A project with no recorded allowlist still knows one thing
        # for certain: a path the template *used to* carry was retired upstream,
        # not written by this project. Deleting those needs no human
        # classification, which is the whole premise of the feature -- and
        # without it a project that never promotes a candidate keeps every
        # retired skill forever.
        history, reason = template_history_paths(repo, ref, directory, scanned)
        if history is None:
            return Plan(
                roots=scanned, source=source, bootstrap=True,
                candidates=project_only, skipped_roots=skipped,
                provenance_reason=reason,
            )
        # Content, not path. A path the template once used proves nothing about
        # the file sitting there now: `.claude/hooks/pre-commit.sh` is a name
        # both a template and a project reach for, and a project that edited a
        # synced file has made it its own. Retire only a byte-identical copy of
        # something the template actually shipped at that path -- anything else
        # goes to the human, including a file with uncommitted edits, which
        # `git checkout` could never bring back.
        blobs = _project_blobs(repo, project_only)
        retired_upstream = [
            p for p in project_only if blobs.get(p) in history.get(p, set())
        ]
        unproven = set(project_only) - set(retired_upstream)
        return Plan(
            roots=scanned, source=source, bootstrap=True,
            retire=retired_upstream,
            candidates=[p for p in project_only if p in unproven],
            skipped_roots=skipped,
        )
    retire, kept, unmatched = split_by_allowlist(project_only, patterns)
    # A pattern under a skipped root matched nothing because nothing under that
    # root was scanned -- not because it went stale. The two need different
    # words: `unmatched` is documented as "about to stop protecting something",
    # which is the opposite of the truth here.
    dormant = [
        pattern for pattern in unmatched
        if not _reaches_a_root(pattern, scanned) and _reaches_a_root(pattern, skipped)
    ]
    return Plan(
        roots=scanned, source=source, retire=retire, kept=kept,
        unmatched=[p for p in unmatched if p not in dormant],
        dormant=dormant, skipped_roots=skipped,
    )


def _field(path: str) -> str:
    """A path, rendered so it can only ever occupy one line of the report.

    The report is the sole record of what a file-deleting tool destroyed, and
    SKILL.md tells the operator to read it in full. A path containing a newline
    would otherwise emit lines indistinguishable from real ones — a file can be
    named so that the run claims to have kept what it deleted. `repr` also
    escapes carriage returns, which repaint a terminal line, and surrogates
    from `errors="surrogateescape"`, which would raise on print.
    """
    return path if path.isprintable() else repr(path)


def render(plan: Plan) -> str:
    """Render what this run proposes, printed before anything is written.

    The retire list is never truncated.

    The progressive-disclosure cap that bounds other reports in this repo is a
    readability optimisation. Here the list *is* the record of what is about to
    be destroyed, and abbreviating it would hide exactly what the report exists
    to show.
    """
    lines = [f"sync retirement — source: {plan.source}, roots: {len(plan.roots)}"]
    for root in plan.skipped_roots:
        lines.append(
            f"  skipped: {root} — declared but empty in the template; "
            f"nothing under it is retired this run"
        )
    if plan.bootstrap:
        lines.append(f"  bootstrap: required (no {KEEP_FILE})")
        if plan.provenance_reason:
            lines.append(
                f"  provenance: unavailable ({plan.provenance_reason}) — nothing "
                f"is retired"
            )
        for path in plan.retire:
            lines.append(f"  retire: {_field(path)} (was template content, retired upstream)")
        for path in plan.candidates:
            lines.append(f"  candidate: {_field(path)}")
        lines.append(
            f"  next:   re-run with --apply to write {CANDIDATE_FILE}, review it, "
            f"then rename it to {KEEP_FILE}"
        )
        return "\n".join(lines)
    for path in plan.retire:
        lines.append(f"  retire: {_field(path)}")
    if not plan.retire:
        lines.append("  retire: (none)")
    for path, pattern in plan.kept:
        lines.append(f"  kept:   {_field(path)} (matched {_field(pattern)})")
    for pattern in plan.dormant:
        lines.append(
            f"  dormant: {_field(pattern)} — under a skipped root; it protects again "
            f"when the template restores that root. Keep it"
        )
    for pattern in plan.unmatched:
        lines.append(f"  unmatched: {_field(pattern)} — matched nothing this run")
    return "\n".join(lines)


def _confined_target(repo_real: str, relative: str) -> Optional[str]:
    """The path to delete, or None when a directory on the way is a symlink.

    `project_paths` reads the *index* and confirms the leaf with
    `os.path.isfile`, which follows every component. So a symlinked directory
    inside a syncable root — a developer sharing a skill tree across worktrees
    is enough, no hostile template required — makes `os.remove` delete a file
    somewhere else entirely. That file was never in this repository, so
    `git restore` cannot bring it back, which is the whole loss this tool is
    built to avoid.

    The leaf itself needs no check: `os.remove` never follows a final symlink,
    so a symlinked *file* costs only the link.
    """
    parent = os.path.dirname(relative)
    declared = os.path.normpath(os.path.join(repo_real, parent))
    resolved = os.path.realpath(os.path.join(repo_real, parent))
    if resolved != declared:
        return None
    if os.path.commonpath([repo_real, resolved]) != repo_real:
        return None
    return os.path.join(resolved, os.path.basename(relative))


def apply_plan(
    repo: str, plan: Plan
) -> Tuple[List[str], List[Tuple[str, str]], List[Tuple[str, str]]]:
    """Delete the retirement set, prune the emptied directories, report removals.

    Returns what it actually removed and what it could not, rather than what it
    intended to. A mid-loop failure that propagated would abandon the record of
    the files already gone, leaving the operator to discover them with
    `git status` — for a tool whose list is the record of what was destroyed,
    that is the one hole that matters.

    Pruning stops at the syncable root: an absent root and an empty one are
    different states to every other reader of the tree, and only the deletions
    below it were authorised.
    """
    removed: List[str] = []
    failed: List[Tuple[str, str]] = []
    pruned_failed: List[Tuple[str, str]] = []
    repo_real = os.path.realpath(repo)
    for relative in plan.retire:
        target = _confined_target(repo_real, relative)
        if target is None:
            failed.append((
                relative,
                "a directory on this path is a symlink, so it resolves outside "
                "the repository — refusing to delete",
            ))
            continue
        try:
            os.remove(target)
        except OSError as exc:
            failed.append((relative, str(exc)))
            continue
        removed.append(relative)
    for relative in removed:
        try:
            _prune_upwards(repo, os.path.dirname(relative), plan.roots)
        except PruneError as exc:
            # The file is already gone; only the empty directory above it
            # survives. Propagating here would discard `removed` -- the record
            # of what was destroyed -- which is the one hole this function
            # exists to close. A leftover directory is cosmetic; a lost record
            # is not.
            entry = (exc.directory, exc.reason)
            if entry not in pruned_failed:
                pruned_failed.append(entry)
    return removed, failed, pruned_failed


# Every character validate_pattern rejects outright, plus the glob tokens this
# language has no escape for. Restating this set by hand is what let backslash
# drift out of it: `validate_pattern` refuses `\`, but `_as_pattern` happily
# wrote one, so the tool emitted a line that made every later sync exit 1.
UNEXPRESSIBLE_CHARS = UNSUPPORTED_GLOB_CHARS + "*?" + "\\" + "\n\r"


def _is_unexpressible(path: str) -> bool:
    """A path no sync-keep line can name, for any reason the reader would trip on."""
    return path != path.strip() or bool(set(path) & set(UNEXPRESSIBLE_CHARS))


def _as_pattern(path: str) -> str:
    """Emit a project path as an allowlist pattern, or comment it out.

    Candidate lines are read back as globs, and this language has no escape
    syntax. A path containing `*` would become an over-broad rule that silently
    protects unrelated siblings from retirement; one containing `[` would make
    every later sync exit 1 on a line this tool wrote itself. Neither is
    something a human asked for, so an unexpressible path is written as a
    comment naming the problem.
    """
    if _is_unexpressible(path):
        return (
            "# UNEXPRESSIBLE — this path contains glob metacharacters, surrounding\n"
            "# whitespace, or a line break, and no exact pattern can name it: the\n"
            "# reader strips each line, so such a rule would silently protect\n"
            "# nothing and the file would be retired anyway. Widen it\n"
            "# deliberately, or rename the file:\n"
            + "\n".join(f"#   {line}" for line in path.splitlines() or [path])
        )
    return path


def assert_candidate_writable(repo: str) -> None:
    """Raise if the candidate file cannot be written, touching nothing.

    Separated from the write so the bootstrap apply path can check it *before*
    deleting: a precondition that only fires after the destruction it guards
    reports nothing about what was destroyed.
    """
    path = os.path.join(repo, CANDIDATE_FILE)
    # lexists, not exists: a dangling symlink is invisible to `exists`, and
    # `open(path, "w")` then follows it and writes through to whatever it
    # names. `read_keep_patterns` already refuses this for the allowlist; the
    # candidate is the file this tool writes, which makes it the better target.
    if os.path.lexists(path):
        raise RetireError(
            f"{CANDIDATE_FILE} already exists — review it and rename it to "
            f"{KEEP_FILE}, or delete it to regenerate. Refusing to overwrite a "
            f"file this tool asked a human to edit"
        )


def write_candidate(repo: str, plan: Plan) -> str:
    """Write the reviewable candidate allowlist, never the allowlist itself.

    Promoting the candidate is the human's confirming act. A script that wrote
    `.claude/sync-keep` directly would record an intent nobody expressed, and
    every later run would treat that guess as data.
    """
    assert_candidate_writable(repo)
    path = os.path.join(repo, CANDIDATE_FILE)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [
        "# Candidate sync-keep, written by /sync in bootstrap mode.",
        "#",
        "# Every path below exists in this project but not in the template. Delete",
        "# the lines naming paths that were retired upstream, keep the ones that are",
        f"# genuinely project-specific, then rename this file to {os.path.basename(KEEP_FILE)}.",
        "# Until that file exists, /sync retires nothing.",
        "",
    ]
    lines.extend(_as_pattern(path) for path in plan.candidates)
    # O_EXCL|O_NOFOLLOW subsumes the lexists precondition and closes the window
    # between it and this write, which the bootstrap path widens by deleting in
    # between. A same-uid process cannot land a symlink here and be followed.
    try:
        descriptor = os.open(
            path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644
        )
    except FileExistsError:
        raise RetireError(
            f"{CANDIDATE_FILE} already exists — review it and rename it to "
            f"{KEEP_FILE}, or delete it to regenerate. Refusing to overwrite a "
            f"file this tool asked a human to edit"
        )
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    return path


def _prune_upwards(repo: str, relative_dir: str, roots: Sequence[str]) -> None:
    """Remove directories emptied by the deletion, stopping at the syncable root.

    An OSError carries the directory it was raised for, because pruning walks
    upward: the directory this was *called* with has usually been removed
    successfully by the time a parent fails, so reporting the starting point
    names a path that no longer exists.
    """
    boundaries = {root.rstrip("/") for root in roots}
    while relative_dir and relative_dir not in boundaries:
        absolute = os.path.join(repo, relative_dir)
        if not os.path.isdir(absolute):
            return
        try:
            if os.listdir(absolute):
                return
            os.rmdir(absolute)
        except OSError as exc:
            raise PruneError(relative_dir, str(exc))
        relative_dir = os.path.dirname(relative_dir)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sync-retire",
        description="Compute and apply the deterministic /sync retirement set.",
    )
    parser.add_argument("--from-ref", help="template inventory read from a git ref")
    parser.add_argument("--from-dir", help="template inventory read from a checkout")
    parser.add_argument("--repo", default=".", help="project root (default: cwd)")
    parser.add_argument("--apply", action="store_true", help="perform the deletions")
    return parser


def apply_requested_writes(repo: str, plan: Plan) -> Tuple[str, int]:
    """Carry out what `--apply` means in this mode, and report what happened.

    Bootstrap writes a candidate for review and deletes nothing; a configured
    project deletes the retirement set. Both return their outcome line and an
    exit code rather than printing, so `render`'s format stays owned in one
    place and a partial deletion still reports every file it removed.
    """
    if plan.bootstrap:
        # Bootstrap deletes only what provenance proves was template content.
        # Everything of unknown origin goes to the candidate file for a human,
        # exactly as before -- the confirming act is still theirs, it just no
        # longer stands between the project and a skill the template retired.
        #
        # Precondition first: write_candidate refuses an existing candidate, and
        # that raise used to happen *after* the deletions, so `removed` -- the
        # record of what was destroyed -- was discarded on the routine
        # "candidate not promoted yet" path. Nothing may fail between the
        # deletion and its report.
        assert_candidate_writable(repo)
        removed, failed, pruned_failed = apply_plan(repo, plan)
        # The existence check above is a courtesy, not the guarantee. Every
        # other way this write fails -- unwritable `.claude/`, read-only mount,
        # ENOSPC -- can only be discovered by attempting it, which is *after*
        # the deletions. So the failure is folded into the report rather than
        # raised through it: propagating here would unwind past `removed`, the
        # only record that those files ever existed.
        unwritten: List[Tuple[str, str]] = []
        try:
            write_candidate(repo, plan)
        except (OSError, RetireError) as exc:
            unwritten.append((CANDIDATE_FILE, _one_line(exc)))
        if not plan.retire and not failed and not pruned_failed and not unwritten:
            return (
                f"  wrote:  {CANDIDATE_FILE} "
                f"({len(plan.candidates)} candidates to review)"
            ), 0
        outcome, code = _deletion_outcome(removed, failed, pruned_failed, unwritten)
        if unwritten:
            return outcome, code
        return (
            f"{outcome}\n  wrote:  {CANDIDATE_FILE} "
            f"({len(plan.candidates)} candidates to review)"
        ), code
    removed, failed, pruned_failed = apply_plan(repo, plan)
    return _deletion_outcome(removed, failed, pruned_failed)


def _deletion_outcome(
    removed: List[str],
    failed: List[Tuple[str, str]],
    pruned_failed: List[Tuple[str, str]],
    unwritten: Sequence[Tuple[str, str]] = (),
) -> Tuple[str, int]:
    """One format for what a deletion did, shared by both apply paths.

    `unwritten` is a fourth category because a run can delete successfully and
    still fail afterwards — the bootstrap candidate write is the case. It has
    to make the run *partial*, or the deletion record collapses back to a count
    at exactly the moment the operator most needs the paths.
    """
    if not failed and not pruned_failed and not unwritten:
        return f"  mode:   applied ({len(removed)} deleted)", 0
    headline = f"  mode:   applied ({len(removed)} deleted"
    if failed:
        headline += f", {len(failed)} failed"
    if pruned_failed:
        headline += f", {len(pruned_failed)} not pruned"
    if unwritten:
        headline += f", {len(unwritten)} not written"
    lines = [headline + ")"]
    # The docstring promises a partial run "reports every file it removed", and a
    # count is not that: the operator would have to subtract FAILED lines from an
    # earlier render they may no longer have.
    lines.extend(f"  deleted: {_field(path)}" for path in removed)
    lines.extend(f"  FAILED: {_field(path)} — {reason}" for path, reason in failed)
    # A directory left behind is reported separately: the files under it are
    # gone either way, so this must not read as a deletion that did not happen.
    lines.extend(f"  UNPRUNED: {_field(path)} — {reason}" for path, reason in pruned_failed)
    lines.extend(f"  FAILED: cannot write {_field(path)} — {reason}" for path, reason in unwritten)
    return "\n".join(lines), 1


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    # An option supplied but empty means the caller's variable was unset -- the
    # shape `--from-dir "$WORKFLOW_CLONE"` takes when that assignment did not
    # survive. Treating it as "not supplied" would silently sync against the
    # wrong source, so it is a usage error rather than a default.
    for flag, value in (("--from-ref", args.from_ref), ("--from-dir", args.from_dir)):
        if value is not None and not value.strip():
            print(f"sync-retire: {flag} was given an empty value", file=sys.stderr)
            return 2
    # Truthiness, consistently: an empty --from-dir used to pass this guard, then
    # take the directory branch for the roots doc and the ref branch for the file
    # inventory -- reading roots from the *project* working tree. That is exactly
    # the branch-dependent scan this feature exists to remove, at exit 0.
    if bool(args.from_ref) == bool(args.from_dir):
        print(
            "sync-retire: pass exactly one of --from-ref or --from-dir, "
            "and neither may be empty",
            file=sys.stderr,
        )
        return 2
    if args.from_ref and args.from_ref.startswith("-"):
        print("sync-retire: --from-ref may not begin with '-'", file=sys.stderr)
        return 2
    repo = os.path.abspath(args.repo)
    if not os.path.isdir(repo):
        print(f"sync-retire: no such directory: {args.repo}", file=sys.stderr)
        return 2

    try:
        plan = compute_plan(repo, args.from_ref, args.from_dir)
    except RetireError as exc:
        print(f"sync-retire: {exc}", file=sys.stderr)
        return 1

    print(render(plan))
    if not args.apply:
        print("  mode:   dry-run (no changes written)")
        return 0
    try:
        outcome, code = apply_requested_writes(repo, plan)
    except (OSError, RetireError) as exc:
        print(f"sync-retire: {exc}", file=sys.stderr)
        return 1
    print(outcome)
    return code


if __name__ == "__main__":
    sys.exit(main())
