#!/usr/bin/env python3
"""closure.py — the closure loop's transition engine.

`/wrap-up-session` Step 4 on drives a repair-and-close loop: check the quality
receipt, commit, push, open or re-sync the PR, watch mergeability and CI,
repair within bounds, verify deployment, and record an honest outcome. This
script is the pure state machine behind that loop (specs/quality-receipt-closure.md
§ Transitions — closure `phase`): no `gh`, no `git`, no network. The skill
performs the actions this prints; this file only decides what happens next.

    python3 closure.py step --state <state.json> --observe '<json>'
    # stdout: action <name> [key=value ...]
    #       | terminal <complete|partial|stopped> state=<label> reason=<text> [draft=<yes|failed|none>]

The state file is created with the defaults below on first use, at
`<git-common-dir>/closure/<sanitized branch>.json` (the caller resolves that
path; this script only reads and writes whatever path it is given):

    {"phase": "receipt", "pr_open": false, "gated": false,
     "ci_rounds": 0, "conflict_rounds": 0, "deploy_reentries": 0}

Bounds (Constraints row *Bounded closure*): 2 CI rounds, 1 conflict round, 1
deployment re-entry, 1 gate run per tree (`gated`, reset whenever a
tree-changing repair returns to `receipt` from `merge`, `repair` or `deploy`).
Reaching a bound turns the next repair into `mark-draft` instead of retrying.
There is no global step budget (Decision C1): every cycle in the transition
table consumes one of these counters (or `gated`, for the one-gate-run cycle),
which `table()`'s caller walks and verifies.

Observation shapes (one dict key per phase, JSON on --observe):

    receipt:   {"receipt": "valid"} | {"receipt": "stale", "scope": "delta"|"full"}
    gate:      {"gate": "GO"|"HOLD-approved"|"HOLD"|"STOP"|"none"}
    suite:     {"suite": "green"|"red"|"blocked"}
    push:      {"push": "ok"} | {"push": "non-ff", "branch": "<name>"} | {"push": "denied"}
    pr:        {"pr": <number>} | {"pr": "failed"}
    mergeable: {"mergeable": "clean"} | {"mergeable": "conflicting", "base": "<name>"} | {"mergeable": "unknown"}
    merge:     {"merge": "resolved"} | {"merge": "unresolved"}
    ci:        {"ci": "pass"} | {"ci": "none"} | {"ci": "fail", "checks": [...]} | {"ci": "timeout"}
    repair:    {"debug": "fixed"} | {"debug": "not-fixed"}
    deploy:    {"deploy": "pass", "head-moved": bool} | {"deploy": "n/a", "reason": "<text>"} | {"deploy": "fail"}
    record:    {"record": "recorded"} | {"record": "record-failed"}
    partial:   {"partial": "drafted"|"draft-failed"|"no-pr"}

[AMBIGUITY] the spec's own examples name receipt/ci/deploy/pr observations
under a key matching the phase, but write the record and partial phases'
values bare ("recorded", "drafted") with no key at all | options: A) keep the
two phases keyless, as a special case B) give every phase's observation a key
named after the phase, including record and partial | picked: B | reason: one
parsing rule for every phase reads simpler than two phases needing a special
case, and nothing outside this file has committed to the bare form yet.

Standard library only, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Callable, Dict, List, Optional

DEFAULT_STATE = {
    "phase": "receipt",
    "pr_open": False,
    "gated": False,
    "ci_rounds": 0,
    "conflict_rounds": 0,
    "deploy_reentries": 0,
}

CI_ROUND_LIMIT = 2
CONFLICT_ROUND_LIMIT = 1
DEPLOY_REENTRY_LIMIT = 1


class ClosureError(Exception):
    """An observation the current phase does not accept."""


def load_state(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return dict(DEFAULT_STATE)
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_state(path: str, state: Dict[str, Any]) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, sort_keys=True)
    os.replace(tmp, path)


def action_line(name: str, args: Optional[Dict[str, Any]] = None) -> str:
    rendered = " ".join(f"{key}={value}" for key, value in (args or {}).items())
    return f"action {name} {rendered}".rstrip()


def terminal_line(outcome: str, label: str, reason: str, draft: Optional[str] = None) -> str:
    parts = [f"terminal {outcome}", f"state={label}", f"reason={reason}"]
    if draft is not None:
        parts.append(f"draft={draft}")
    return " ".join(parts)


def go_end(state: Dict[str, Any], reason: str, label: Optional[str] = None) -> str:
    """A `-> end(r)` row: stopped before a PR exists, drafted after (spec § Transitions)."""
    label = label or state["phase"]
    if not state["pr_open"]:
        return terminal_line("stopped", label, reason)
    state["reason"] = reason
    state["label"] = label
    state["phase"] = "partial"
    return action_line("mark-draft", {"reason": reason})


# Each row is (phase, match(obs)->bool, guard(state)->bool, to). `to` encodes
# what happens next: a bare phase name for a plain move, `RESET:<counter>` for
# a tree-changing return to `receipt` that also consumes a bound and clears
# `gated`, `END:<reason>[:<label>]` / `ENDF:<obs-key>` for a `-> end(r)` row,
# `COMPLETE` for the one terminal-complete row, and `PARTIAL:<draft>` for the
# `partial` phase's three exits. `guard` defaults to always-true.
_ALWAYS = lambda state: True  # noqa: E731


def _rows() -> List[Any]:
    return [
        ("receipt", lambda o: o.get("receipt") == "valid", _ALWAYS, "suite"),
        ("receipt", lambda o: o.get("receipt") == "stale", lambda s: not s["gated"], "gate"),
        (
            "receipt",
            lambda o: o.get("receipt") == "stale",
            lambda s: s["gated"],
            "END:receipt not written after gate",
        ),
        ("gate", lambda o: o.get("gate") in ("GO", "HOLD-approved"), _ALWAYS, "receipt"),
        ("gate", lambda o: o.get("gate") in ("HOLD", "STOP", "none"), _ALWAYS, "ENDF:gate"),
        ("suite", lambda o: o.get("suite") == "green", _ALWAYS, "push"),
        ("suite", lambda o: o.get("suite") == "red", _ALWAYS, "END:tests"),
        ("suite", lambda o: o.get("suite") == "blocked", _ALWAYS, "END:suite lock held"),
        ("push", lambda o: o.get("push") == "ok", _ALWAYS, "pr"),
        (
            "push",
            lambda o: o.get("push") == "non-ff",
            lambda s: s["conflict_rounds"] < CONFLICT_ROUND_LIMIT,
            "merge",
        ),
        (
            "push",
            lambda o: o.get("push") == "non-ff",
            lambda s: s["conflict_rounds"] >= CONFLICT_ROUND_LIMIT,
            "END:push non-fast-forward",
        ),
        ("push", lambda o: o.get("push") == "denied", _ALWAYS, "END:push denied"),
        ("pr", lambda o: isinstance(o.get("pr"), int), _ALWAYS, "mergeable"),
        ("pr", lambda o: o.get("pr") == "failed", _ALWAYS, "END:pr-sync failed"),
        ("mergeable", lambda o: o.get("mergeable") == "clean", _ALWAYS, "ci"),
        (
            "mergeable",
            lambda o: o.get("mergeable") == "conflicting",
            lambda s: s["conflict_rounds"] < CONFLICT_ROUND_LIMIT,
            "merge",
        ),
        (
            "mergeable",
            lambda o: o.get("mergeable") == "conflicting",
            lambda s: s["conflict_rounds"] >= CONFLICT_ROUND_LIMIT,
            "END:mergeable conflicting",
        ),
        ("mergeable", lambda o: o.get("mergeable") == "unknown", _ALWAYS, "END:mergeable unknown"),
        ("merge", lambda o: o.get("merge") == "resolved", _ALWAYS, "RESET:conflict_rounds"),
        ("merge", lambda o: o.get("merge") == "unresolved", _ALWAYS, "END:merge unresolved"),
        ("ci", lambda o: o.get("ci") in ("pass", "none"), _ALWAYS, "deploy"),
        (
            "ci",
            lambda o: o.get("ci") == "fail",
            lambda s: s["ci_rounds"] < CI_ROUND_LIMIT,
            "repair",
        ),
        (
            "ci",
            lambda o: o.get("ci") == "fail",
            lambda s: s["ci_rounds"] >= CI_ROUND_LIMIT,
            "END:ci fail",
        ),
        ("ci", lambda o: o.get("ci") == "timeout", _ALWAYS, "END:ci timeout:ci-pending"),
        ("repair", lambda o: o.get("debug") == "fixed", _ALWAYS, "RESET:ci_rounds"),
        ("repair", lambda o: o.get("debug") == "not-fixed", _ALWAYS, "END:debug not-fixed"),
        (
            "deploy",
            lambda o: o.get("deploy") == "pass" and o.get("head-moved") is False,
            _ALWAYS,
            "record",
        ),
        (
            "deploy",
            lambda o: o.get("deploy") == "pass" and o.get("head-moved") is True,
            lambda s: s["deploy_reentries"] < DEPLOY_REENTRY_LIMIT,
            "RESET:deploy_reentries",
        ),
        (
            "deploy",
            lambda o: o.get("deploy") == "pass" and o.get("head-moved") is True,
            lambda s: s["deploy_reentries"] >= DEPLOY_REENTRY_LIMIT,
            "END:deployment re-entry exhausted",
        ),
        ("deploy", lambda o: o.get("deploy") == "n/a", _ALWAYS, "record"),
        ("deploy", lambda o: o.get("deploy") == "fail", _ALWAYS, "END:deployment failed"),
        ("record", lambda o: o.get("record") == "recorded", _ALWAYS, "COMPLETE"),
        ("record", lambda o: o.get("record") == "record-failed", _ALWAYS, "END:record failed"),
        ("partial", lambda o: o.get("partial") == "drafted", _ALWAYS, "PARTIAL:yes"),
        ("partial", lambda o: o.get("partial") == "draft-failed", _ALWAYS, "PARTIAL:failed"),
        ("partial", lambda o: o.get("partial") == "no-pr", _ALWAYS, "PARTIAL:none"),
    ]


ROWS = _rows()

ACTION_BY_PHASE = {
    "receipt": "check-receipt",
    "gate": "quality-gate",
    "suite": "run-suite",
    "push": "commit-push",
    "pr": "pr-sync",
    "mergeable": "mergeability",
    "merge": "merge-base",
    "ci": "watch-ci",
    "repair": "debug-ci",
    "deploy": "verify-deploy",
    "record": "record-closure",
}


def _action_args(to_phase: str, obs: Dict[str, Any], from_phase: str) -> Dict[str, Any]:
    if to_phase == "gate":
        return {"scope": obs.get("scope", "full")}
    if to_phase == "merge" and from_phase == "push":
        return {"ref": f"origin/{obs.get('branch', '')}"}
    if to_phase == "merge" and from_phase == "mergeable":
        return {"ref": f"origin/{obs.get('base', '')}"}
    if to_phase == "repair":
        return {"checks": ",".join(obs.get("checks", []))}
    if to_phase == "record" and obs.get("deploy") == "n/a":
        return {"note": f"not applicable — {obs.get('reason', '')}"}
    return {}


def find_row(phase: str, obs: Dict[str, Any], state: Dict[str, Any]) -> Optional[Any]:
    matches = [row for row in ROWS if row[0] == phase and row[1](obs) and row[2](state)]
    if len(matches) != 1:
        return None
    return matches[0]


def _dispatch_action(to_phase: str, obs: Dict[str, Any], from_phase: str, state: Dict[str, Any]) -> str:
    state["phase"] = to_phase
    if to_phase == "pr":
        state["pr_open"] = True
    if to_phase == "gate":
        state["gated"] = True
    return action_line(ACTION_BY_PHASE[to_phase], _action_args(to_phase, obs, from_phase))


def apply_row(row: Any, obs: Dict[str, Any], state: Dict[str, Any]) -> str:
    from_phase = state["phase"]
    to = row[3]
    if to == "COMPLETE":
        return terminal_line("complete", "record", "closure recorded")
    if to.startswith("RESET:"):
        counter = to[len("RESET:") :]
        state[counter] = state[counter] + 1
        state["gated"] = False
        return _dispatch_action("receipt", obs, from_phase, state)
    if to.startswith("END:"):
        reason, _, label = to[len("END:") :].partition(":")
        return go_end(state, reason, label or None)
    if to.startswith("ENDF:"):
        verdict = obs.get(to[len("ENDF:") :])
        return go_end(state, f"review {verdict}", from_phase)
    if to.startswith("PARTIAL:"):
        draft = to[len("PARTIAL:") :]
        return terminal_line("partial", state.get("label", "partial"), state.get("reason", ""), draft=draft)
    return _dispatch_action(to, obs, from_phase, state)


def step(state_path: str, observe_json: str) -> str:
    state = load_state(state_path)
    obs = json.loads(observe_json)
    row = find_row(state["phase"], obs, state)
    if row is None:
        raise ClosureError(f"closure: observation {observe_json} not valid in phase {state['phase']}")
    line = apply_row(row, obs, state)
    save_state(state_path, state)
    return line


def table() -> List[Dict[str, Any]]:
    """A JSON-serializable view of every row, for the cycle-check test.

    `to` collapses every dynamic destination to the phase a *repeated* visit
    would land in: `RESET:*` reports the counter it consumes and lands back in
    `receipt`; `END:*`/`ENDF:*` land in `partial` (the only case that can ever
    recur, once a PR is open); `COMPLETE`/`PARTIAL:*` are real exits with no
    outgoing edge, reported as `TERMINAL`.
    """
    rows = []
    for phase, _match, _guard, to in ROWS:
        if to == "COMPLETE" or to.startswith("PARTIAL:"):
            rows.append({"phase": phase, "to": "TERMINAL", "counter": None})
        elif to.startswith("RESET:"):
            rows.append({"phase": phase, "to": "receipt", "counter": to[len("RESET:") :]})
        elif to.startswith("END:") or to.startswith("ENDF:"):
            rows.append({"phase": phase, "to": "partial", "counter": None})
        elif to == "gate":
            rows.append({"phase": phase, "to": to, "counter": "gated"})
        else:
            rows.append({"phase": phase, "to": to, "counter": None})
    return rows


def cmd_step(args: argparse.Namespace) -> int:
    try:
        print(step(args.state, args.observe))
        return 0
    except ClosureError as exc:
        print(str(exc), file=sys.stderr)
        return 2


def cmd_table(_args: argparse.Namespace) -> int:
    print(json.dumps(table()))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="closure.py")
    sub = parser.add_subparsers(dest="command", required=True)

    step_parser = sub.add_parser("step")
    step_parser.add_argument("--state", required=True)
    step_parser.add_argument("--observe", required=True)
    step_parser.set_defaults(func=cmd_step)

    table_parser = sub.add_parser("table")
    table_parser.set_defaults(func=cmd_table)

    parsed = parser.parse_args(argv)
    return parsed.func(parsed)


if __name__ == "__main__":
    sys.exit(main())
