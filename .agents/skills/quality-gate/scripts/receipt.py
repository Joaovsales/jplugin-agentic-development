#!/usr/bin/env python3
"""receipt.py — fingerprint a working tree and mint, check and approve the
quality receipt that `/quality-gate` and `/wrap-up-session` trade instead of
re-reviewing an unchanged diff (specs/quality-receipt-closure.md).

Four subcommands:

  * **fingerprint** — hash the `tasks/**`-excluded diff between the branch's
    merge-base and the current working tree (tracked + untracked, not
    ignored). Bookkeeping edits under `tasks/**` and committing the same tree
    never change the result.
  * **write** — validate a gate's outcome JSON, derive the verdict from its
    findings (never accept one as input), and store the receipt plus the
    branch's latest-receipt pointer under the git common dir.
  * **check** — read-only: is the stored receipt (or its delta chain) still
    valid for the current tree and policy?
  * **approve** — record a human's approval of a HOLD receipt.

The tree hash mirrors `.agents/skills/build/scripts/cached-suite.sh`'s
`working_tree_hash`: a temporary index, `git add -A` with `core.safecrlf=false`,
then `write-tree`. The real index is never touched.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence, Tuple

SCHEMA = "quality-receipt/1"
DEFAULT_BASE_CANDIDATES = (
    "origin/main",
    "origin/master",
    "origin/develop",
    "main",
    "master",
    "develop",
)
EXCLUDE_PATHSPEC = ":(exclude)tasks/**"
DIFF_FLAGS = (
    "--binary",
    "--full-index",
    "--no-ext-diff",
    "--no-textconv",
    "--no-renames",
    "--no-color",
    "--src-prefix=a/",
    "--dst-prefix=b/",
)
# Resolved relative to this file so the policy hash is stable regardless of cwd.
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
POLICY_FILES = (
    __file__,
    os.path.join(_SCRIPTS_DIR, "..", "SKILL.md"),
    os.path.join(_SCRIPTS_DIR, "..", "..", "security-scan", "SKILL.md"),
    os.path.join(_SCRIPTS_DIR, "..", "..", "software-design-expert-review", "SKILL.md"),
    os.path.join(_SCRIPTS_DIR, "..", "..", "..", "agents", "software-design-expert-review.md"),
    os.path.join(_SCRIPTS_DIR, "..", "..", "..", "references", "finding-model.md"),
    os.path.join(_SCRIPTS_DIR, "..", "..", "..", "references", "review-dispatch-contract.md"),
)

SEVERITIES = ("MUST-FIX", "SHOULD-FIX", "NITPICK")
CONFIDENCES = (50, 75, 100)
AUTOFIX_CLASSES = ("gated_auto", "manual", "advisory")
OWNERS = ("agent", "human", "release")
VERDICTS = ("GO", "HOLD", "STOP")
DISPATCHES = ("dispatched", "inline")


class ReceiptError(Exception):
    """A refusal that becomes `receipt: <message>` on stderr, exit 2."""


def die(message: str) -> "NoReturn":
    print(f"receipt: {message}", file=sys.stderr)
    sys.exit(2)


def _run(args: Sequence[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def _git(*args: str, env: Optional[Dict[str, str]] = None) -> str:
    result = _run(["git", *args], env=env)
    if result.returncode != 0:
        raise ReceiptError((result.stderr or result.stdout or "git failed").strip())
    return result.stdout.strip()


def common_dir() -> str:
    return _git("rev-parse", "--path-format=absolute", "--git-common-dir")


def receipts_dir() -> str:
    return os.path.join(common_dir(), "quality-receipts")


def current_branch() -> str:
    return _git("rev-parse", "--abbrev-ref", "HEAD")


def sanitize_branch(branch: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "-", branch)


def pointer_path(branch: Optional[str] = None) -> str:
    return os.path.join(receipts_dir(), f"branch-{sanitize_branch(branch or current_branch())}.json")


# --------------------------------------------------------------------------
# Fingerprinting
# --------------------------------------------------------------------------

def resolve_base(explicit: Optional[str]) -> str:
    if explicit:
        return explicit
    for candidate in DEFAULT_BASE_CANDIDATES:
        check = _run(["git", "rev-parse", "--verify", "--quiet", candidate])
        if check.returncode == 0:
            return candidate
    raise ReceiptError("no base ref found among " + ", ".join(DEFAULT_BASE_CANDIDATES))


def merge_base(ref: str) -> str:
    return _git("merge-base", "HEAD", ref)


def working_tree_hash() -> str:
    """The tree `git add -A` would commit right now, via a throwaway index."""
    real_index = _git("rev-parse", "--path-format=absolute", "--git-path", "index")
    top = _git("rev-parse", "--show-toplevel")
    scratch_dir = tempfile.mkdtemp(prefix="receipt-index-")
    try:
        scratch_index = os.path.join(scratch_dir, "index")
        if os.path.isfile(real_index):
            shutil.copy2(real_index, scratch_index)
        env = dict(os.environ, GIT_INDEX_FILE=scratch_index)
        add = _run(["git", "-c", "core.safecrlf=false", "-C", top, "add", "-A"], env=env)
        if add.returncode != 0:
            raise ReceiptError((add.stderr or "could not hash the working tree").strip())
        tree = _run(["git", "-C", top, "write-tree"], env=env)
        if tree.returncode != 0:
            raise ReceiptError((tree.stderr or "could not hash the working tree").strip())
        return tree.stdout.strip()
    finally:
        shutil.rmtree(scratch_dir, ignore_errors=True)


def diff_paths(base: str, tree: str, extra_pathspec: Sequence[str] = ()) -> List[str]:
    args = ["-c", "core.quotepath=false", "diff", "--name-only", *DIFF_FLAGS, base, tree, "--", ".", EXCLUDE_PATHSPEC, *extra_pathspec]
    out = _git(*args)
    return [line for line in out.splitlines() if line]


def diff_bytes(base: str, tree: str) -> bytes:
    args = ["git", "-c", "core.quotepath=false", "diff", *DIFF_FLAGS, base, tree, "--", ".", EXCLUDE_PATHSPEC]
    result = _run(args)
    if result.returncode not in (0, 1):
        raise ReceiptError((result.stderr or "diff failed").strip())
    return result.stdout.encode("utf-8")


def compute_fingerprint(explicit_base: Optional[str]) -> Tuple[str, str, str]:
    base_ref = resolve_base(explicit_base)
    base_sha = merge_base(base_ref)
    tree = working_tree_hash()
    digest = hashlib.sha256(diff_bytes(base_sha, tree)).hexdigest()
    return base_sha, tree, digest


# --------------------------------------------------------------------------
# Policy hash
# --------------------------------------------------------------------------

def policy_hash() -> str:
    hasher = hashlib.sha256()
    for path in POLICY_FILES:
        resolved = os.path.normpath(path)
        if os.path.isfile(resolved):
            with open(resolved, "rb") as handle:
                hasher.update(handle.read())
        else:
            hasher.update(resolved.encode("utf-8"))
            hasher.update(b"<missing>")
    return f"qg1-{hasher.hexdigest()[:8]}"


# --------------------------------------------------------------------------
# Schema validation
# --------------------------------------------------------------------------

def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ReceiptError(f"invalid outcome — {message}")


def validate_finding(finding: Dict, index: int) -> None:
    _require(isinstance(finding, dict), f"unresolved[{index}]: not an object")
    _require(finding.get("severity") in SEVERITIES, f"unresolved[{index}].severity: must be one of {SEVERITIES}")
    _require(finding.get("confidence") in CONFIDENCES, f"unresolved[{index}].confidence: must be one of {CONFIDENCES}")
    _require(finding.get("autofix_class") in AUTOFIX_CLASSES, f"unresolved[{index}].autofix_class: must be one of {AUTOFIX_CLASSES}")
    _require(finding.get("owner") in OWNERS, f"unresolved[{index}].owner: must be one of {OWNERS}")
    _require(isinstance(finding.get("location"), str) and finding["location"], f"unresolved[{index}].location: required")
    _require(isinstance(finding.get("summary"), str) and finding["summary"], f"unresolved[{index}].summary: required")


def validate_reviewer(reviewer: Dict, index: int) -> None:
    _require(isinstance(reviewer, dict), f"reviewers[{index}]: not an object")
    _require(isinstance(reviewer.get("phase"), int), f"reviewers[{index}].phase: required")
    _require(isinstance(reviewer.get("lens"), str) and reviewer["lens"], f"reviewers[{index}].lens: required")
    _require(reviewer.get("dispatch") in DISPATCHES, f"reviewers[{index}].dispatch: must be one of {DISPATCHES}")


def validate_outcome(outcome: Dict, tree: str) -> None:
    _require(isinstance(outcome, dict), "outcome is not an object")

    reviewers = outcome.get("reviewers")
    _require(isinstance(reviewers, list) and len(reviewers) > 0, "reviewers: must be a non-empty list")
    for index, reviewer in enumerate(reviewers):
        validate_reviewer(reviewer, index)
    phases_present = {reviewer.get("phase") for reviewer in reviewers}
    _require({1, 2, 3, 4}.issubset(phases_present), "reviewers: phases 1-4 must each be present")

    unresolved = outcome.get("unresolved", [])
    _require(isinstance(unresolved, list), "unresolved: must be a list")
    for index, finding in enumerate(unresolved):
        validate_finding(finding, index)

    _require(outcome.get("design_verdict") in VERDICTS, f"design_verdict: must be one of {VERDICTS}")

    tests = outcome.get("tests")
    _require(isinstance(tests, dict), "tests: must be an object")
    _require(isinstance(tests.get("command"), str) and tests["command"], "tests.command: required")
    _require(isinstance(tests.get("exit"), int), "tests.exit: required")
    _require(isinstance(tests.get("tree"), str) and tests["tree"], "tests.tree: required")
    _require(tests["tree"] == tree, "tests.tree: does not match the reviewed tree")

    scope = outcome.get("scope")
    is_full = scope == "full"
    is_delta = isinstance(scope, list) and len(scope) > 0
    _require(is_full or is_delta, "scope: must be \"full\" or a non-empty path list")


# --------------------------------------------------------------------------
# Receipt store
# --------------------------------------------------------------------------

def _atomic_write(path: str, payload: Dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp_path, path)
    except BaseException:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise


def load_receipt(fingerprint: str) -> Optional[Dict]:
    path = os.path.join(receipts_dir(), f"{fingerprint}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r") as handle:
        return json.load(handle)


def load_pointer(branch: Optional[str] = None) -> Optional[Dict]:
    path = pointer_path(branch)
    if not os.path.isfile(path):
        return None
    with open(path, "r") as handle:
        return json.load(handle)


# --------------------------------------------------------------------------
# Verdict derivation
# --------------------------------------------------------------------------

def _should_fix_count(unresolved: List[Dict]) -> int:
    return sum(1 for finding in unresolved if finding.get("severity") == "SHOULD-FIX")


def _has_must_fix(unresolved: List[Dict]) -> bool:
    return any(finding.get("severity") == "MUST-FIX" for finding in unresolved)


def chain_should_fix_carry(parent_fingerprint: Optional[str]) -> int:
    """Sum unresolved SHOULD-FIX up the parent chain to the nearest approved HOLD.

    A GO ancestor or an approved-HOLD ancestor is the boundary: its own count
    is included and the walk stops there. A missing ancestor stops the walk
    with nothing more added (`check` is what flags a broken chain as invalid).
    """
    total = 0
    fingerprint = parent_fingerprint
    while fingerprint:
        receipt = load_receipt(fingerprint)
        if receipt is None:
            break
        total += _should_fix_count(receipt.get("unresolved", []))
        verdict = receipt.get("verdict")
        if verdict == "GO" or (verdict == "HOLD" and receipt.get("hold_approved_by")):
            break
        fingerprint = receipt.get("parent")
    return total


def derive_verdict(outcome: Dict, tree: str, parent: Optional[str]) -> Tuple[str, int]:
    unresolved = outcome.get("unresolved", [])
    should_fix = _should_fix_count(unresolved)
    if parent:
        should_fix += chain_should_fix_carry(parent)

    if _has_must_fix(unresolved) or outcome.get("design_verdict") == "STOP" or outcome["tests"]["exit"] != 0:
        return "STOP", should_fix
    if should_fix > 3 or outcome.get("design_verdict") == "HOLD":
        return "HOLD", should_fix
    return "GO", should_fix


# --------------------------------------------------------------------------
# write
# --------------------------------------------------------------------------

def cmd_write(args: argparse.Namespace) -> None:
    if not os.path.isfile(args.outcome):
        die(f"invalid outcome — file not found: {args.outcome}")
    with open(args.outcome, "r") as handle:
        try:
            outcome = json.load(handle)
        except json.JSONDecodeError as exc:
            die(f"invalid outcome — not valid JSON: {exc}")

    base, tree, fingerprint = compute_fingerprint(None)

    try:
        validate_outcome(outcome, tree)
    except ReceiptError as exc:
        die(str(exc))

    scope = outcome["scope"]
    is_delta = isinstance(scope, list)
    if is_delta and not args.parent:
        die("invalid outcome — scope: a delta scope requires --parent")
    if not is_delta and args.parent:
        die("invalid outcome — scope: a full scope must not carry --parent")
    if args.parent and load_receipt(args.parent) is None:
        die(f"invalid outcome — parent: no stored receipt {args.parent}")

    verdict, _ = derive_verdict(outcome, tree, args.parent)
    policy = policy_hash()
    head = _git("rev-parse", "HEAD") if _run(["git", "rev-parse", "--verify", "--quiet", "HEAD"]).returncode == 0 else ""

    receipt = {
        "schema": SCHEMA,
        "fingerprint": fingerprint,
        "base": base,
        "head": head,
        "tree": tree,
        "policy": policy,
        "scope": scope,
        "parent": args.parent,
        "reviewers": outcome["reviewers"],
        "tests": outcome["tests"],
        "unresolved": outcome.get("unresolved", []),
        "design_verdict": outcome["design_verdict"],
        "verdict": verdict,
        "hold_approved_by": None,
        "written_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    receipt_path = os.path.join(receipts_dir(), f"{fingerprint}.json")
    _atomic_write(receipt_path, receipt)
    _atomic_write(pointer_path(), {"fingerprint": fingerprint, "tree": tree, "base": base})

    print(f"receipt: written {fingerprint[:8]} verdict {verdict} policy {policy}")


# --------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------

def _link_valid(receipt: Dict, expected_policy: str) -> bool:
    if receipt.get("schema") != SCHEMA:
        return False
    if receipt.get("policy") != expected_policy:
        return False
    verdict = receipt.get("verdict")
    return verdict == "GO" or (verdict == "HOLD" and bool(receipt.get("hold_approved_by")))


def _chain_valid(receipt: Dict, expected_policy: str) -> Tuple[bool, Optional[str]]:
    """Walk a receipt's own parent chain. Returns (valid, bad_fingerprint)."""
    if not _link_valid(receipt, expected_policy):
        return False, receipt.get("fingerprint")
    parent_fp = receipt.get("parent")
    while parent_fp:
        parent = load_receipt(parent_fp)
        if parent is None or not _link_valid(parent, expected_policy):
            return False, parent_fp
        parent_fp = parent.get("parent")
    return True, None


def cmd_check(args: argparse.Namespace) -> None:
    base, tree, fingerprint = compute_fingerprint(args.base)
    policy = policy_hash()

    receipt = load_receipt(fingerprint)
    if receipt is not None:
        if receipt.get("schema") != SCHEMA:
            print(f"receipt: stale schema", file=sys.stdout)
            sys.exit(3)
        if receipt.get("policy") != policy:
            print(f"receipt: stale policy-changed", file=sys.stdout)
            sys.exit(3)
        verdict = receipt.get("verdict")
        if verdict == "STOP":
            print("receipt: stale verdict STOP")
            sys.exit(3)
        if verdict == "HOLD" and not receipt.get("hold_approved_by"):
            print("receipt: stale verdict HOLD")
            sys.exit(3)
        valid, bad_fp = _chain_valid(receipt, policy)
        if not valid:
            print(f"receipt: stale parent-invalid {bad_fp}")
            sys.exit(3)
        label = "GO" if verdict == "GO" else "HOLD-approved"
        print(f"receipt: valid {label} {fingerprint[:8]} policy {policy}")
        sys.exit(0)

    pointer = load_pointer()
    if pointer is None:
        print("receipt: stale missing")
        sys.exit(3)

    parent_receipt = load_receipt(pointer["fingerprint"])
    if parent_receipt is None:
        print("receipt: stale missing")
        sys.exit(3)
    chain_ok, _ = _chain_valid(parent_receipt, policy)
    if not chain_ok:
        print("receipt: stale missing")
        sys.exit(3)

    tree_delta = diff_paths(pointer["tree"], tree)
    current_diff = diff_paths(base, tree)
    delta = [path for path in tree_delta if path in set(current_diff)]

    parts = [f"receipt: stale diff-changed parent {pointer['fingerprint'][:8]}"]
    if delta:
        parts.append("delta " + " ".join(delta))
    print(" ".join(parts))
    sys.exit(3)


# --------------------------------------------------------------------------
# approve
# --------------------------------------------------------------------------

def cmd_approve(args: argparse.Namespace) -> None:
    receipt = load_receipt(args.fingerprint)
    if receipt is None:
        die(f"no such receipt {args.fingerprint}")
    if receipt.get("verdict") != "HOLD":
        die("only HOLD can be approved")
    receipt["hold_approved_by"] = args.by
    _atomic_write(os.path.join(receipts_dir(), f"{args.fingerprint}.json"), receipt)
    print(f"receipt: approved {args.fingerprint[:8]} by {args.by}")


# --------------------------------------------------------------------------
# fingerprint
# --------------------------------------------------------------------------

def cmd_fingerprint(args: argparse.Namespace) -> None:
    base, tree, fingerprint = compute_fingerprint(args.base)
    print(f"{base} {tree} {fingerprint}")


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="receipt.py")
    sub = parser.add_subparsers(dest="command", required=True)

    fp = sub.add_parser("fingerprint")
    fp.add_argument("--base")
    fp.set_defaults(func=cmd_fingerprint)

    write = sub.add_parser("write")
    write.add_argument("--outcome", required=True)
    write.add_argument("--parent")
    write.set_defaults(func=cmd_write)

    check = sub.add_parser("check")
    check.add_argument("--base")
    check.set_defaults(func=cmd_check)

    approve = sub.add_parser("approve")
    approve.add_argument("--fingerprint", required=True)
    approve.add_argument("--by", required=True)
    approve.set_defaults(func=cmd_approve)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except ReceiptError as exc:
        die(str(exc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
