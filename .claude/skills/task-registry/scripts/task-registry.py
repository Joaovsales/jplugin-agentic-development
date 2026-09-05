#!/usr/bin/env python3
"""task-registry — provider-agnostic task tracking for this harness.

    task-registry reconcile [--apply]   compare the local index against the provider
    task-registry publish   [--apply]   create/update provider tasks for local rows
    task-registry pull      [--apply]   refresh local rows from provider state
    task-registry frontier              dependency-aware ready/blocked list
    task-registry show <task-id>        full detail for exactly one task
    task-registry migrate   [--apply]   classify a pre-registry repository
    task-registry doctor                which provider is selected, and why
    task-registry selectors             routine selector vocabulary, checked upstream
    task-registry select --routine R    the next issue routine R may claim
    task-registry claim <ref> --routine R  write the claim label onto one issue

Dry-run is the default for every command. `--apply` is the only way anything is
written, and external writes additionally honour `require_write_approval`.

Exit codes: 0 success · 1 failure or partial failure · 2 usage error.

Stdlib only, Python 3.8+. No SDK for either tracker.
"""

from __future__ import annotations

import argparse
import os
import sys
import traceback

# Set before the package is imported, and deliberately: this package lives inside
# a *skills tree*, where `.agents/skills/` and `.claude/skills/` are pinned
# byte-identical by tests/test-skill-parity.sh. Bytecode written next to the
# source would appear in one tree and not the other and fail that guard, and
# would litter every downstream checkout besides.
sys.dont_write_bytecode = True

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from registry.config import ConfigError, load_config, select_provider  # noqa: E402
from registry.migrate import apply_migration, plan_migration  # noqa: E402
from registry.providers import build_provider  # noqa: E402
from registry.providers.base import (  # noqa: E402
    ProviderError,
    ProviderUnavailable,
    WriteGate,
    WriteNotAuthorized,
)
from registry.model import Task, TaskModelError  # noqa: E402
from registry.reconcile import Registry  # noqa: E402
from registry.routines import (  # noqa: E402
    matched_label,
    missing_routine_labels,
    select_candidates,
    select_routine,
    unclassified,
)
from registry.redaction import Redactor, redactor_for  # noqa: E402
from registry.upsert import derive_id, upsert_task  # noqa: E402

COMMANDS = (
    "reconcile", "publish", "pull", "frontier", "show", "migrate", "doctor", "upsert",
    "selectors", "select", "claim",
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="task-registry",
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument(
        "task_id", nargs="?", help="task id, required by `show`; issue ref for `claim`"
    )
    parser.add_argument("--repo", default=".", help="project root (default: cwd)")
    parser.add_argument(
        "--apply", action="store_true", help="perform writes (default: dry-run)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="explicit no-write mode; overrides --apply if both are given",
    )
    parser.add_argument(
        "--approve",
        action="store_true",
        help="satisfy require_write_approval for this run (external writes only)",
    )
    parser.add_argument(
        "--provider", help="override the selected provider (github|jira|local)"
    )
    parser.add_argument(
        "--routine", help="routine name, required by `select`"
    )
    parser.add_argument("--verbose", action="store_true", help="print every finding")
    parser.add_argument("--report", help="also write the output to this file")
    # `upsert` content. Structured rather than a free-form body file: every one of
    # these round-trips through the local provider's metadata block and managed
    # sections, so re-running the command replaces the record instead of
    # accreting a second copy of it beside the first.
    parser.add_argument("--title", help="task title (upsert)")
    parser.add_argument("--kind", help="task kind (upsert), e.g. research")
    parser.add_argument("--spec", help="spec path this task is about (upsert)")
    parser.add_argument("--summary", default="", help="one-paragraph summary (upsert)")
    parser.add_argument(
        "--evidence", action="append", default=[],
        help="evidence line (upsert); repeatable",
    )
    parser.add_argument(
        "--criterion", action="append", default=[],
        help="acceptance criterion (upsert); repeatable",
    )
    parser.add_argument(
        "--label", action="append", default=[], help="label (upsert); repeatable"
    )
    parser.add_argument(
        "--derive-id",
        metavar="NAMESPACE",
        help="derive the task id as NAMESPACE.<normalized --spec path> (upsert); "
        "use instead of the positional id so two runs cannot normalize differently",
    )
    return parser


def main(argv=None) -> int:
    """Entry point. Every escape from here is redacted before it is printed."""
    redact = Redactor()
    try:
        return _run(argv, redact.adopt)
    except SystemExit:
        raise
    except Exception:  # noqa: BLE001 - deliberate, see below
        # An unexpected traceback is still output, and this tool's output can
        # carry a Jira token or an Authorization header picked up along the way.
        # Crashing raw would print it, so the trace is scrubbed first. The
        # failure stays loud and still exits non-zero.
        print(redact(traceback.format_exc()), file=sys.stderr)
        print(
            "task-registry: unexpected failure (trace above, credentials masked)",
            file=sys.stderr,
        )
        return 1


def _run(argv, set_redactor) -> int:
    args = build_parser().parse_args(argv)
    root = os.path.abspath(args.repo)
    if not os.path.isdir(root):
        print(f"task-registry: no such directory: {args.repo}", file=sys.stderr)
        return 2
    if args.command == "show" and not args.task_id:
        print("task-registry: `show` requires a task id", file=sys.stderr)
        return 2
    if args.command == "upsert":
        if bool(args.task_id) == bool(args.derive_id):
            print(
                "task-registry: `upsert` needs exactly one of a task id or "
                "--derive-id NAMESPACE (with --spec)",
                file=sys.stderr,
            )
            return 2
        if args.derive_id and not args.spec:
            print("task-registry: `--derive-id` requires --spec", file=sys.stderr)
            return 2
        if not args.title:
            print("task-registry: `upsert` requires --title", file=sys.stderr)
            return 2

    routine_fault = None
    try:
        config = load_config(root)
    except ConfigError as exc:
        if args.command != "doctor":
            print(f"task-registry: {exc}", file=sys.stderr)
            return 1
        routine_fault = str(exc)
        config = load_config(root, validate_routines=False)
    set_redactor(redactor_for(config))

    selection = select_provider(config)
    provider_name = args.provider or selection.provider
    reason = (
        f"--provider {provider_name}" if args.provider else selection.reason
    )
    apply_writes = args.apply and not args.dry_run
    gate = WriteGate(
        apply=apply_writes,
        require_approval=config.require_write_approval,
        approved=args.approve,
    )

    try:
        provider = build_provider(provider_name, config, gate)
    except ProviderError as exc:
        print(f"task-registry: {exc}", file=sys.stderr)
        return 2

    registry = Registry(config, provider, selection_reason=reason)
    try:
        args.routine_fault = routine_fault
        output, code = _dispatch(args, config, registry, apply_writes)
    except WriteNotAuthorized as exc:
        print(f"task-registry: {exc}", file=sys.stderr)
        return 1
    except (ProviderError, ProviderUnavailable) as exc:
        print(f"task-registry: {exc}", file=sys.stderr)
        return 1
    except ConfigError as exc:
        print(f"task-registry: {exc}", file=sys.stderr)
        return 1

    print(output)
    if args.report:
        _write_report(args.report, output)
    return code


def _dispatch(args, config, registry: Registry, apply_writes: bool):
    command = args.command
    if command == "show":
        return registry.show(args.task_id)
    if command == "upsert":
        try:
            task = Task(
                id=args.task_id or derive_id(args.derive_id, args.spec),
                title=args.title,
                kind=args.kind or "task",
                spec_path=args.spec,
                summary=args.summary,
                evidence=tuple(args.evidence),
                acceptance_criteria=tuple(args.criterion),
                labels=tuple(args.label),
            )
        except TaskModelError as exc:
            return (f"task-registry: {exc}", 2)
        lines, code = upsert_task(registry, task, apply_writes)
        return ("\n".join(lines), code)
    if command == "doctor":
        return _doctor(registry, args.routine_fault), (1 if args.routine_fault else 0)
    if command == "selectors":
        return _selectors(registry)
    if command == "select":
        return _select(registry, args.routine)
    if command == "claim":
        return _claim(registry, args.routine, args.task_id, apply_writes)
    if command == "migrate":
        plan = plan_migration(config)
        # Applying does not make malformed rows readable: the same rows are still
        # unparsed afterwards, so both branches report the same failure.
        exit_code = 1 if plan.problems else 0
        if apply_writes:
            actions = apply_migration(config, plan)
            rendered = plan.render() + "\n\n" + "\n".join(f"  {a}" for a in actions)
            return rendered, exit_code
        return plan.render(), exit_code

    runner = {
        "reconcile": registry.reconcile,
        "publish": registry.publish,
        "pull": registry.pull,
    }.get(command)
    if runner is not None:
        report = runner(apply_writes)
    else:
        report = registry.frontier()
    return report.render(verbose=args.verbose), report.exit_code


def _doctor(registry: Registry, routine_fault=None) -> str:
    """Answer 'which tracker am I talking to, and why' without touching anything."""
    status = registry.provider.discover()
    config = registry.config
    lines = [
        f"provider:       {registry.provider.name}",
        f"selected because: {registry.selection_reason}",
        f"configuration:  {config.source_path or 'none (defaults + local fallback)'}",
        f"index:          {config.index_path}",
        f"capabilities:   {registry.provider.capabilities.render()}",
        f"reachable:      {'yes' if status.available else 'no'} — {status.detail}",
        f"write approval: {'required' if config.require_write_approval else 'not required'}"
        + (
            " (configuration asked to drop it; ignored — approval is a floor)"
            if config.approval_relaxation_ignored
            else ""
        ),
        f"label creation: {'allowed' if config.allow_label_creation else 'blocked'}",
        f"offline reads:  {config.offline_reads}",
    ]
    if routine_fault:
        lines.append(
            f"routines:       MISCONFIGURED — {routine_fault}\n"
            "  Every command except this one refuses to run until it is fixed."
        )
    else:
        lines.append(f"routines:       {' > '.join(config.kind_precedence)}")
    return "\n".join(lines)


def _selectors(registry: Registry):
    """Report the routine selector vocabulary, and check it against the tracker.

    Two outcomes must not share an exit code. "No issue matched" is an ordinary,
    successful, silent result — a routine with nothing to do is not a failure.
    "The label you configured does not exist upstream" is the halt that opened
    specs/category-routines.md, and it exits non-zero naming the label.
    """
    # No validate call here: load_config already refused an inconsistent
    # configuration, so every command inherits the guarantee rather than this one.
    verdict, code = _selector_upstream_check(registry)
    return "\n".join(_selector_vocabulary(registry.config) + [verdict]), code


def _select(registry: Registry, routine):
    """The next issue a routine may claim, or silence.

    Exit 0 with no candidate line is the ordinary answer — a routine with nothing
    to do is not a failure, and making it one would page somebody every night the
    backlog happened to be clean. An unknown routine name is the opposite: that is
    a configuration mistake, and it exits 2 rather than looking like an empty day.
    """
    config = registry.config
    if not routine:
        return "task-registry: `select` requires --routine <name>", 2
    if routine not in config.routine_selectors:
        known = ", ".join(sorted(config.routine_selectors)) or "none configured"
        return (
            f"task-registry: unknown routine {routine!r} — configured routines: {known}"
        ), 2

    # The routine contract states three preconditions and calls them asserted "once
    # at routine start". `select` IS routine start -- it is the only one of these
    # commands a routine runs -- so they are asserted here. A precondition checked
    # only by a command nobody invokes is prose, which is the failure this whole
    # spec is a response to.
    verdict, code = _selector_upstream_check(registry)
    if code:
        return verdict, code

    tasks = registry.provider.list_tasks()

    if registry.provider.result_truncated:
        return (
            f"task-registry: refusing to select — {registry.provider.name} returned a "
            "truncated read, so the candidate pool is partial and 'nothing to claim' "
            "would be indistinguishable from 'there were more'"
        ), 1

    # Checked AFTER the read: a provider only learns its own degradations by querying.
    if registry.provider.linked_pr_exclusion_available() is False:
        return (
            f"task-registry: refusing to select — {registry.provider.name} could not "
            "report linked pull request state (`closedByPullRequestsReferences` needs "
            "gh >= 2.73.0), so the in-flight exclusion cannot be evaluated. Selecting "
            "anyway re-picks every issue already under review and races on its branch."
        ), 1

    lines = [f"unclassified:  {len(unclassified(tasks, config))} open issue(s) carry no kind label"]
    candidates = select_candidates(tasks, config, routine)
    if not candidates:
        lines.append(f"candidate:     none — {routine} has nothing to claim")
        return "\n".join(lines), 0

    best = candidates[0]
    reference = best.external.id if best.external else best.id
    lines.append(f"candidate:     {reference} — {best.title}")
    lines.append(f"matched label: {matched_label(best, config)}")
    lines.append(
        f"claim label:   {config.claim_label} — write it with "
        f"`task-registry claim {reference} --routine {routine} --apply --approve` "
        "before branching"
    )
    lines.append(f"remaining:     {len(candidates) - 1} other candidate(s) in this pool")
    return "\n".join(lines), 0


def _claim(registry: Registry, routine, task_ref, apply_writes: bool):
    """Write the claim label onto one issue — the routine spine's step 2.

    This is the contract's only write, and the only thing that stops two runs of
    one routine picking the same top candidate. `select` excludes on the label's
    PRESENCE, so without a way to put it there the exclusion could only ever fire
    on a label a human applied by hand.

    Idempotent: an issue already carrying the label is reported and left alone, so
    a retried routine does not need to know whether its first attempt got through.
    """
    config = registry.config
    if not routine:
        return "task-registry: `claim` requires --routine <name>", 2
    if routine not in config.routine_selectors:
        known = ", ".join(sorted(config.routine_selectors)) or "none configured"
        return (
            f"task-registry: unknown routine {routine!r} — configured routines: {known}"
        ), 2
    if not task_ref:
        return "task-registry: `claim` requires the issue this routine is claiming", 2

    tasks = registry.provider.list_tasks()
    matches = [
        task for task in tasks
        if task.id == task_ref or (task.external and task.external.id == str(task_ref))
    ]
    if not matches:
        return f"task-registry: no open task matches {task_ref!r}", 1
    task = matches[0]

    if config.claim_label in task.labels:
        return f"claim: {task_ref} already carries {config.claim_label} — nothing to do", 0

    actual = select_routine(task.labels, config)
    if actual != routine:
        owner = actual or "no routine — it carries no kind label"
        return (
            f"task-registry: refusing to claim {task_ref} for {routine!r} — it belongs "
            f"to {owner}. Claiming across routines is how two routines end up on one "
            "issue, which is the collision the claim label exists to prevent."
        ), 1

    registry.provider.update_task(task.with_(labels=tuple(task.labels) + (config.claim_label,)))
    return f"claim: wrote {config.claim_label} to {task_ref} for routine {routine}", 0


def _selector_vocabulary(config) -> list:
    """The configured routine vocabulary, as the operator wrote it."""
    lines = [
        f"claim label:    {config.claim_label}",
        f"precedence:     {' > '.join(config.kind_precedence)}",
        "selectors:",
    ]
    for routine in sorted(config.routine_selectors):
        lines.append(f"  {routine:<8} {', '.join(config.routine_selectors[routine])}")
    return lines


def _selector_upstream_check(registry: Registry):
    """Does the tracker actually have every label a routine selects on?"""
    try:
        known = registry.provider.known_labels()
    except (ProviderError, ProviderUnavailable) as exc:
        # Tried and failed. That is a broken check, not an absent one, and it must
        # not share an exit code with a tracker that has no vocabulary to read.
        return (
            f"upstream check: COULD NOT RUN — {registry.provider.name} has a label "
            f"vocabulary but did not answer: {exc}"
        ), 1
    if known is None:
        # Not a pass. The check did not run, and saying so is the floor.
        return (
            f"upstream check: NOT RUN — {registry.provider.name} cannot enumerate "
            "its label vocabulary"
        ), 0

    missing = missing_routine_labels(registry.config, known)
    if not missing:
        return f"upstream check: every selector label exists in {registry.provider.name}", 0

    return (
        "upstream check: FAILED — these configured routine labels do not exist in "
        f"{registry.provider.name}: {', '.join(missing)}\n"
        "  A routine selecting on a label the tracker does not have finds nothing "
        "and exits 0. That is the halt this check exists to make loud."
    ), 1


def _write_report(path: str, text: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
