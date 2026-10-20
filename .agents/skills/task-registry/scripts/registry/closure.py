"""Close what a merged pull request's closing keywords left open (#146).

The routines contract lets the tracker close an issue when its PR merges, and
GitHub does — unless the merge was made with a workflow's GITHUB_TOKEN, which
fires no closing keyword at all. The automation that merged is the only actor
that can see "merged, issue still open", so it runs this right after its merge
call: every linked issue still open is closed through the provider's gated
close, and any that cannot be closed is named with a non-zero exit instead of
waiting for a human to notice.
"""

from __future__ import annotations

from typing import Tuple

from .providers.base import ProviderError


def close_merged(registry, pr_ref) -> Tuple[str, int]:
    """(output, exit code) for `closes <pr>`: 0 when nothing linked stays open."""
    if not pr_ref:
        return "task-registry: `closes` requires the merged pull request, e.g. '#141'", 2
    provider = registry.provider
    lines, failed = [], False
    for ref in provider.closing_references(pr_ref):
        label = provider.reference_label(ref)
        try:
            task = provider.get_task(ref)
        except ProviderError as exc:
            # Unread is not open: an issue transferred or deleted since the
            # merge must not send the reader looking for an open one.
            failed = True
            lines.append(f"closes: could not read {label}, linked by {pr_ref} — {exc}")
            continue
        if task.is_terminal:
            continue
        try:
            provider.close_task(task)
        except ProviderError as exc:  # a refused write is a ProviderError too
            failed = True
            lines.append(f"closes: {label} is still open after {pr_ref} merged — {exc}")
            continue
        lines.append(f"closes: closed {label} — {pr_ref} merged without closing it")
    if not lines:
        return f"closes: {pr_ref} leaves no linked issue open — nothing to do", 0
    return "\n".join(lines), 1 if failed else 0
