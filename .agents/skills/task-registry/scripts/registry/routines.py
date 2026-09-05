"""Routine selection — which routine, if any, owns an issue.

`specs/category-routines.md` replaced a policy lattice that computed how much
autonomy an issue permitted. The lattice derived its inputs from untrusted prose,
so it needed a monotonicity guarantee, a claim schema, a downgrade ledger and a
radius tripwire — 923 lines of policy that produced three unattended halts in one
week, two of them from routing preconditions rather than from the work.

A schedule already answers the autonomy question. So the only question left is
selection, and selection is a total function over one label axis:

    labels -> routine name, or None

None is an ordinary answer. An issue with no kind label has not been triaged, and
an issue already carrying the claim label is in flight. Neither is an error, and
neither is a routine's problem.

Everything here reads the *project's* vocabulary through :class:`Config`, which
owns both the shipped defaults and their validation. This module holds only
behaviour, so there is exactly one place each name is defined.
"""

from __future__ import annotations

from typing import Iterable, List, Optional, Sequence, Tuple

from .model import by_priority

__all__ = [
    "routine_for_label",
    "select_routine",
    "select_candidates",
    "missing_routine_labels",
    "matched_label",
    "unclassified",
]




def routine_for_label(label: str, config) -> Optional[str]:
    """The routine that selects `label`, or None when no routine claims it."""
    for routine, labels in config.routine_selectors.items():
        if label in labels:
            return routine
    return None


def select_routine(labels: Iterable[str], config) -> Optional[str]:
    """The routine that owns an issue carrying `labels`, or None.

    Precedence is first-match-wins over the configured chain, so an issue with
    two kind labels resolves deterministically instead of being claimed twice.
    That determinism is not this function's to assert — `load_config` refuses a
    configuration where two routines claim one label, so an ambiguous chain
    cannot reach here. The claim label short-circuits everything: an in-flight
    issue is not a candidate, however it is labelled.
    """
    present = set(labels or ())
    if config.claim_label in present:
        return None
    for label in config.kind_precedence:
        if label in present:
            return routine_for_label(label, config)
    return None


def missing_routine_labels(config, known_labels: Sequence[str]) -> Sequence[str]:
    """Labels the routine machinery needs that the tracker does not have.

    `known_labels` is deliberately NOT optional. A provider that cannot enumerate
    its vocabulary returns None from `known_labels()`, and that is a third state —
    "not checked" — which must never be representable here as an empty result. The
    caller branches on None before it has a vocabulary to check; the type is what
    stops the next caller from reading "could not check" as "nothing missing".
    """
    known = set(known_labels)
    needed = {label for labels in config.routine_selectors.values() for label in labels}
    #: The claim label belongs here, not just the selectors. It is the only guard
    #: against two runs of one routine picking the same issue, and `select_routine`
    #: excludes on it by *presence* -- so a claim label the tracker never created is
    #: written, silently dropped, and never read back. That failure looks exactly
    #: like a clean backlog, which is what this check exists to make impossible.
    needed.add(config.claim_label)
    return tuple(sorted(label for label in needed if label not in known))


def select_candidates(tasks: Iterable, config, routine: str) -> Sequence:
    """Every open task this routine may claim, best candidate first.

    The three exclusions are the contract's step 1, in one place so that no
    routine host re-derives them: an issue is out if another routine's label
    outranks this one, if it already carries the claim label, or if a routine
    pull request for it is still open. The last is a read rather than a write,
    and it is strictly more accurate than closing the issue on PR creation —
    it also suppresses re-picking while a PR sits in review.
    """
    candidates = [
        task
        for task in tasks
        if not task.is_terminal
        and select_routine(task.labels, config) == routine
        and task.extra.get("unresolved_linked_pr") != "true"
    ]
    return sorted(candidates, key=by_priority)


def matched_label(task, config) -> Optional[str]:
    """The label that won precedence for this task — what the routine records."""
    present = set(task.labels)
    for label in config.kind_precedence:
        if label in present:
            return label
    return None


def unclassified(tasks: Iterable, config) -> Sequence:
    """Open tasks no routine can select, because nobody has triaged them.

    Reported rather than silently dropped. Four such issues sitting unselected
    look identical to a broken selector until someone counts them.
    """
    ranked = set(config.kind_precedence)
    return tuple(
        task for task in tasks if not task.is_terminal and not (set(task.labels) & ranked)
    )
