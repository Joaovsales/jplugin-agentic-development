#!/usr/bin/env python3
"""task-registry — provider-agnostic task tracking for this harness.

    task-registry reconcile [--apply]   compare the local index against the provider
    task-registry publish   [--apply]   create/update provider tasks for local rows
    task-registry pull      [--apply]   refresh local rows from provider state
    task-registry frontier              dependency-aware ready/blocked list
    task-registry show <task-id>        full detail for exactly one task
    task-registry migrate   [--apply]   classify a pre-registry repository
    task-registry doctor                which provider is selected, and why

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
from registry.reconcile import Registry  # noqa: E402
from registry.redaction import Redactor, redactor_for  # noqa: E402

COMMANDS = ("reconcile", "publish", "pull", "frontier", "show", "migrate", "doctor")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="task-registry",
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("task_id", nargs="?", help="task id, required by `show`")
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
    parser.add_argument("--verbose", action="store_true", help="print every finding")
    parser.add_argument("--report", help="also write the output to this file")
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

    try:
        config = load_config(root)
    except ConfigError as exc:
        print(f"task-registry: {exc}", file=sys.stderr)
        return 1
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
    if command == "doctor":
        return _doctor(registry), 0
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


def _doctor(registry: Registry) -> str:
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
    return "\n".join(lines)


def _write_report(path: str, text: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
