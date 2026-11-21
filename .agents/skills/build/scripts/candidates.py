#!/usr/bin/env python3
"""candidates.py — several Builders on one slice, one winner by fixed rules
(specs/parallel-candidates.md).

    candidates.py open    --slice N --count K
    candidates.py rank    --spec PATH --slice N --branch B --base SHA [--run-id ID]
                          [--ledger DIR] [--agent cK=true|false|unknown]... -- <verification command...>
    candidates.py discard --slice N

`open` creates K detached worktrees at HEAD through bootstrap-worktree.sh, at
`<toplevel>/../<repo>-slice-<N>-c<k>`, one `candidates: c<k> <path>` line each.
`rank` stages and measures every candidate against the commit it started at,
runs the verification through slice_outcome.py inside it, ranks them by a
lexicographic key — eligible (slice_result True), checks passed, diff lines,
paths outside the slice's Surface, candidate number — records every candidate
with its reason in the run ledger, applies the winner's diff to this tree and
removes every candidate worktree, also when it is terminated. `discard`
removes them when the build stops before `rank`. `open` is all-or-nothing,
cancellation included; removal goes through git only, so a locked worktree is
kept and reported, never deleted behind git's back.

Exit status: 0 done (rank: a winner applied); 1 refused (no eligible
candidate, leftovers or an existing path on open, no candidates on rank, a
diff that does not apply, a candidate git would not remove); 2 usage.
"""

from __future__ import annotations

import argparse
import importlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Sequence, Set, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "slice" / "scripts"))
from run_ledger import DEFAULT_LEDGER, Refused, add_candidates, run_id_arg, sha_arg  # noqa: E402
from slice_outcome import AGENT_VALUES, EXIT_FOR, FALSE, TRUE, derive, split_argv  # noqa: E402

_slice_script = importlib.import_module("slice")  # slice.py: the Surface resolver /build already uses
from registry.globs import SpecPathError, match_path  # noqa: E402  (path set up by slice.py)

BOOTSTRAP = HERE / "bootstrap-worktree.sh"
SLICE_OUTCOME = HERE / "slice_outcome.py"
META = "jplugin-candidate.json"  # in each candidate's own git dir: base commit and setup paths
OUTCOME_RE = re.compile(r"^slice-outcome: agent_result=(\S+) verification_result=(\S+) slice_result=(\S+) (\S+)$")
KEY_NAMES = ("eligibility", "checks passed", "diff_lines", "outside_surface", "candidate number")
SETTLE_SECONDS = 2  # grace a cancelled bootstrap gets after TERM, before KILL
CANCEL_SIGNALS = tuple(getattr(signal, n) for n in ("SIGTERM", "SIGHUP", "SIGINT") if hasattr(signal, n))


@dataclass(frozen=True)
class Candidate:
    """One candidate's recorded measurements — the only input to the ranking."""
    number: int
    agent_result: str
    verification_result: str
    diff_lines: int
    outside_surface: int

    @property
    def slice_result(self) -> str:
        return derive(self.agent_result, self.verification_result)[0]

    @property
    def label(self) -> str:
        return derive(self.agent_result, self.verification_result)[1]

    @property
    def name(self) -> str:
        return f"c{self.number}"

    @property
    def eligible(self) -> bool:
        return self.slice_result == TRUE

    @property
    def checks_passed(self) -> int:
        return [self.agent_result, self.verification_result].count(TRUE)

    def key(self) -> Tuple[bool, int, int, int, int]:
        return (not self.eligible, -self.checks_passed, self.diff_lines, self.outside_surface, self.number)

    def shown(self, index: int) -> str:
        return [("ineligible" if not self.eligible else "eligible"), str(self.checks_passed),
                str(self.diff_lines), str(self.outside_surface), self.name][index]


class Failed(Exception):
    """An expected refusal: printed as one line, exit 1."""


# --------------------------------------------------------------------------
# Ranking — pure, so the same candidate set always ranks the same.

def _deciding(a: Candidate, b: Candidate) -> int:
    return next(i for i, (x, y) in enumerate(zip(a.key(), b.key())) if x != y)


def _reason(ranked: List[Candidate], i: int) -> str:
    me = ranked[i]
    if not me.eligible:
        return f"ineligible: {me.label}"
    if i == 0:
        if len(ranked) < 2 or not ranked[1].eligible:
            return "selected: only eligible candidate"
        k = _deciding(me, ranked[1])
        return f"selected: ahead of {ranked[1].name} on {KEY_NAMES[k]} ({me.shown(k)} vs {ranked[1].shown(k)})"
    above = ranked[i - 1]
    k = _deciding(above, me)
    return f"behind {above.name} on {KEY_NAMES[k]} ({me.shown(k)} vs {above.shown(k)})"


def rank_entries(candidates: Sequence[Candidate]) -> List[Dict[str, object]]:
    ranked = sorted(candidates, key=Candidate.key)
    return [{
        "candidate": c.name, "rank": i + 1, "selected": i == 0 and c.eligible, "eligible": c.eligible,
        "agent_result": c.agent_result, "verification_result": c.verification_result,
        "slice_result": c.slice_result, "label": c.label, "checks_passed": c.checks_passed,
        "diff_lines": c.diff_lines, "outside_surface": c.outside_surface, "reason": _reason(ranked, i),
    } for i, c in enumerate(ranked)]


def render(entry: Dict[str, object]) -> str:
    return (f"candidates: {entry['candidate']} rank={entry['rank']} "
            f"{'selected' if entry['selected'] else 'discarded'} "
            f"{'eligible' if entry['eligible'] else 'ineligible'} checks={entry['checks_passed']}/2 "
            f"diff_lines={entry['diff_lines']} outside_surface={entry['outside_surface']} "
            f"{entry['label']} — {entry['reason']}")


# --------------------------------------------------------------------------
# Worktrees

def _git(*args: str, cwd: Path, data: Optional[bytes] = None) -> bytes:
    proc = subprocess.run(("git", *args), cwd=cwd, input=data, capture_output=True)
    if proc.returncode != 0:
        raise Failed(f"candidates: git {' '.join(args)} failed in {cwd}: "
                     f"{proc.stderr.decode('utf-8', 'replace').strip()}")
    return proc.stdout


def _toplevel() -> Path:
    return Path(_git("rev-parse", "--show-toplevel", cwd=Path.cwd()).decode().strip()).resolve()


def _candidate_path(top: Path, slice_no: int, k: int) -> Path:
    return top.parent / f"{top.name}-slice-{slice_no}-c{k}"


def _registered(top: Path) -> Set[Path]:
    return {Path(line[len("worktree "):]).resolve()
            for line in _git("worktree", "list", "--porcelain", cwd=top).decode().splitlines()
            if line.startswith("worktree ")}


def existing(top: Path, slice_no: int) -> Dict[int, Path]:
    """The slice's registered candidate worktrees, by candidate number."""
    pattern = re.compile(re.escape(f"{top.name}-slice-{slice_no}-c") + r"(\d+)$")
    found: Dict[int, Path] = {}
    for path in _registered(top):
        match = pattern.match(path.name)
        if match and path.parent == top.parent:
            found[int(match.group(1))] = path
    return dict(sorted(found.items()))


def _meta_path(wt: Path) -> Path:
    return Path(_git("rev-parse", "--absolute-git-dir", cwd=wt).decode().strip()) / META


def remove(top: Path, paths: Sequence[Path]) -> List[str]:
    """Remove candidate worktrees through git; return one error line per path git kept.

    Never deletes a registered worktree's directory behind git's back, so a
    `git worktree lock` holds and the directory survives with its registration.
    A path counts as removed only once git no longer lists it and it is gone."""
    reasons = {}
    for path in paths:
        proc = subprocess.run(("git", "worktree", "remove", "--force", str(path)), cwd=top,
                              capture_output=True, text=True, errors="replace")
        reasons[path] = proc.stderr.strip()
    prune = subprocess.run(("git", "worktree", "prune"), cwd=top, capture_output=True, text=True, errors="replace")
    left = _registered(top)
    errors = [f"candidates: could not remove {path.name.rsplit('-', 1)[-1]} {path}: "
              f"{reasons[path] or 'still present after git worktree remove'}"
              for path in paths if path.resolve() in left or path.exists()]
    if prune.returncode != 0:
        errors.append(f"candidates: git worktree prune failed in {top}: {prune.stderr.strip()}")
    return errors


def _report_cleanup(errors: Sequence[str]) -> None:
    for line in errors:
        print(line, file=sys.stderr)


@contextmanager
def cancellable() -> Iterator[None]:
    """TERM, HUP and INT raise SystemExit, so every `finally` cleanup runs."""
    def terminate(signum, _frame):
        raise SystemExit(128 + signum)
    previous = {sig: signal.signal(sig, terminate) for sig in CANCEL_SIGNALS}
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


_SIGMASK = getattr(signal, "pthread_sigmask", None)


@contextmanager
def _signals_held() -> Iterator[None]:
    """Hold cancellation while a child starts, so its handle is never lost."""
    if _SIGMASK:
        _SIGMASK(signal.SIG_BLOCK, CANCEL_SIGNALS)
    try:
        yield
    finally:
        if _SIGMASK:
            _SIGMASK(signal.SIG_UNBLOCK, CANCEL_SIGNALS)


def _unblock_in_child() -> None:
    """A forked child inherits the held mask; release it before exec so it can be stopped."""
    _SIGMASK(signal.SIG_UNBLOCK, CANCEL_SIGNALS)


def _settle(child: subprocess.Popen) -> None:
    """Stop a bootstrap and everything it started, and wait for it.

    On POSIX the child leads its own process group: TERM the group, give it
    SETTLE_SECONDS, then KILL the group — always, because a descendant that
    ignores TERM outlives its leader and would write into the worktree after
    it is removed. Windows has no process groups: the child alone is stopped."""
    if not hasattr(os, "killpg"):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=SETTLE_SECONDS)
            except subprocess.TimeoutExpired:
                child.kill()
        child.wait()
        return
    deadline = time.monotonic() + SETTLE_SECONDS
    _signal_group(child.pid, signal.SIGTERM)
    while time.monotonic() < deadline and (child.poll() is None or _signal_group(child.pid, 0)):
        time.sleep(0.05)
    _signal_group(child.pid, signal.SIGKILL)
    child.wait()


def _signal_group(pgid: int, sig: int) -> bool:
    """Send `sig` to the process group; False once the group is gone."""
    try:
        os.killpg(pgid, sig)
        return True
    except ProcessLookupError:
        return False


def _bootstrap(top: Path, path: Path, k: int) -> None:
    child = None
    try:  # entered before the unmask, so a cancellation pending at the unmask still settles the child
        with _signals_held():
            child = subprocess.Popen(("bash", str(BOOTSTRAP), "--detach-head", str(path)), cwd=top,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                     errors="replace", start_new_session=hasattr(os, "killpg"),
                                     preexec_fn=_unblock_in_child if _SIGMASK else None)
        out, err = child.communicate()
    finally:
        if child is not None:
            _settle(child)
    if child.returncode != 0:
        raise Failed(f"candidates: could not create c{k}: {err.strip() or out.strip()}")


def _discard_owned(top: Path, owned: Sequence[Path]) -> None:
    """Undo an `open`: every path in `owned` did not exist before this run."""
    registered = _registered(top)
    errors = remove(top, [p for p in owned if p.resolve() in registered])
    for path in owned:
        if path.resolve() not in registered and path.exists():
            shutil.rmtree(path, ignore_errors=True)
    _report_cleanup(errors)


def cmd_open(args: argparse.Namespace) -> int:
    top = _toplevel()
    if existing(top, args.slice):
        raise Failed(f"candidates: slice {args.slice} already has candidate worktrees — "
                     f"run `candidates.py discard --slice {args.slice}` first")
    base = _git("rev-parse", "HEAD", cwd=top).decode().strip()
    owned: List[Path] = []  # owned before its bootstrap starts, so a failure or signal undoes it
    with cancellable():
        try:
            for k in range(1, args.count + 1):
                path = _candidate_path(top, args.slice, k)
                if os.path.lexists(path):
                    raise Failed(f"candidates: c{k} path already exists, not created by this run: {path}")
                owned.append(path)
                _bootstrap(top, path, k)
                setup = _git("ls-files", "--others", "--exclude-standard", "-z", cwd=path).decode().split("\0")
                _meta_path(path).write_text(json.dumps({"base": base, "setup": [p for p in setup if p]}))
        except BaseException:
            _discard_owned(top, owned)
            raise
    for k, path in enumerate(owned, 1):
        print(f"candidates: c{k} {path}")
    return 0


def cmd_discard(args: argparse.Namespace) -> int:
    top = _toplevel()
    found = existing(top, args.slice)
    errors = remove(top, list(found.values()))
    kept = _registered(top)
    for k, path in found.items():
        if path not in kept and not path.exists():
            print(f"candidates: removed c{k} {path}")
    if not found:
        print(f"candidates: slice {args.slice} has no candidate worktrees")
    _report_cleanup(errors)
    return 1 if errors else 0


# --------------------------------------------------------------------------
# Measuring and verifying one candidate

def _measure(wt: Path, surface: Sequence[str]) -> Tuple[int, int, bytes]:
    """(diff lines, paths outside the Surface, binary patch) against the candidate's base."""
    meta = json.loads(_meta_path(wt).read_text())
    _git("add", "-A", cwd=wt)
    if meta["setup"]:  # files the bootstrap copied in (.env, node_modules) are not the Builder's work
        _git("reset", "-q", "--", *meta["setup"], cwd=wt)
    lines = 0
    for row in _git("diff", "--cached", "--numstat", meta["base"], cwd=wt).decode().splitlines():
        added, deleted, _ = row.split("\t", 2)
        lines += 1 if added == "-" else int(added) + int(deleted)
    names = _git("diff", "--cached", "--name-only", "-z", meta["base"], cwd=wt).decode().split("\0")
    outside = sum(1 for n in names if n and not any(match_path(p, n) for p in surface))
    return lines, outside, _git("diff", "--cached", "--binary", meta["base"], cwd=wt)


def _verify(wt: Path, agent: str, command: Sequence[str]) -> Tuple[str, str]:
    """(agent_result, verification_result) from slice_outcome.py, trusted only when consistent.

    The summary counts only if the wrapper exited with the status its own
    outcome maps to, the agent value is the claim passed in, and the labels
    follow from `derive`. Anything else — a wrapper killed after its command
    printed a success-shaped line, say — is a failed verification."""
    claim = AGENT_VALUES[agent]
    proc = subprocess.run((sys.executable, str(SLICE_OUTCOME), "--agent", agent, "--", *command),
                          cwd=wt, capture_output=True, text=True, errors="replace")
    lines = [m for m in map(OUTCOME_RE.match, proc.stdout.splitlines()) if m]
    if lines:
        got_agent, verification, slice_result, label = lines[-1].groups()
        if (got_agent == claim and verification in EXIT_FOR
                and derive(claim, verification) == (slice_result, label)
                and proc.returncode == EXIT_FOR[slice_result]):
            return claim, verification
    print(f"candidates: {wt.name}: slice_outcome.py exited {proc.returncode} without a consistent "
          "outcome — verification counted as failed", file=sys.stderr)
    return claim, FALSE


def _surface(spec: str, slice_no: int) -> Sequence[str]:
    try:
        slices = _slice_script.resolve_slices(spec, Path(spec).stem)
    except (SpecPathError, _slice_script.SliceError, OSError) as exc:
        raise Failed(f"candidates: {exc}") from exc
    if slice_no not in slices:
        raise Failed(f"candidates: no slice {slice_no} in {spec}")
    return slices[slice_no].surface


def cmd_rank(args: argparse.Namespace, command: Sequence[str]) -> int:
    top = _toplevel()
    found = existing(top, args.slice)
    if not found:
        raise Failed(f"candidates: slice {args.slice} has no candidate worktrees — run `open` first")
    surface = _surface(args.spec, args.slice)  # before the try: a bad --spec must not discard the work
    with cancellable():
        try:
            status = _rank_and_apply(top, args, command, found, surface)
        finally:
            errors = remove(top, list(found.values()))
            _report_cleanup(errors)
    if errors:
        raise Failed("candidates: some candidate worktrees could not be removed — see above")
    return status


def _rank_and_apply(top: Path, args: argparse.Namespace, command: Sequence[str],
                    found: Dict[int, Path], surface: Sequence[str]) -> int:
    measured, patches = [], {}
    for k, wt in found.items():
        lines, outside, patches[f"c{k}"] = _measure(wt, surface)
        agent, verification = _verify(wt, args.agent.get(k, "unknown"), command)
        measured.append(Candidate(k, agent, verification, lines, outside))
    entries = rank_entries(measured)
    for entry in entries:
        print(render(entry))
    winner = entries[0]
    try:  # the winner lands first, so a ledger failure cannot cost its work
        if winner["selected"]:
            _apply(top, args.slice, winner["candidate"], patches[winner["candidate"]])
    finally:
        add_candidates(args.ledger, args.branch, args.base, args.run_id, str(args.slice), entries)
    if not winner["selected"]:
        raise Failed("candidates: no eligible candidate — nothing applied")
    print(f"candidates: applied {winner['candidate']}")
    return 0


def _apply(top: Path, slice_no: int, name: str, patch: bytes) -> None:
    if not patch:
        return
    proc = subprocess.run(("git", "apply", "--whitespace=nowarn", "-"), cwd=top, input=patch, capture_output=True)
    if proc.returncode != 0:
        kept = top / "tasks" / "tmp" / f"candidates-slice-{slice_no}-{name}.patch"
        kept.parent.mkdir(parents=True, exist_ok=True)
        kept.write_bytes(patch)
        raise Failed(f"candidates: {name}'s diff does not apply — kept at {kept}: "
                     f"{proc.stderr.decode('utf-8', 'replace').strip()}")


# --------------------------------------------------------------------------
# CLI

def _positive(value: str) -> int:
    if not value.isdigit() or int(value) < 1:
        raise argparse.ArgumentTypeError(f"{value!r} is not a positive integer")
    return int(value)


def _count(value: str) -> int:
    if not value.isdigit() or int(value) < 2:
        raise argparse.ArgumentTypeError(f"--count {value!r}: candidates need at least 2")
    return int(value)


def _agent(value: str) -> Tuple[int, str]:
    match = re.fullmatch(r"c(\d+)=(true|false|unknown)", value)
    if not match:
        raise argparse.ArgumentTypeError(f"--agent {value!r} is not c<k>=true|false|unknown")
    return int(match.group(1)), match.group(2)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="candidates.py", allow_abbrev=False,
                                     description="Run several candidates for one slice and keep the best.")
    sub = parser.add_subparsers(dest="command", required=True)
    op = sub.add_parser("open", allow_abbrev=False, help="create the candidate worktrees")
    op.add_argument("--count", required=True, type=_count)
    rk = sub.add_parser("rank", allow_abbrev=False, help="verify, rank, record, apply the winner, clean up")
    rk.add_argument("--spec", required=True)
    rk.add_argument("--branch", required=True)
    rk.add_argument("--base", required=True, type=sha_arg)
    rk.add_argument("--run-id", type=run_id_arg)
    rk.add_argument("--ledger", type=Path, default=Path(DEFAULT_LEDGER))
    rk.add_argument("--agent", type=_agent, action="append", default=[])
    sub.add_parser("discard", allow_abbrev=False, help="remove the slice's candidate worktrees")
    for p in sub.choices.values():
        p.add_argument("--slice", required=True, type=_positive)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    own, command = split_argv(sys.argv[1:] if argv is None else argv)
    args = build_parser().parse_args(own)
    try:
        if args.command == "rank":
            args.agent = dict(args.agent)
            return cmd_rank(args, command)
        return {"open": cmd_open, "discard": cmd_discard}[args.command](args)
    except (Failed, Refused) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
