"""Provider registry.

A dict, not an if-chain: adding a tracker means adding an entry, and nothing in
the core has to learn its name (CLAUDE.md § Open/Closed).
"""

from __future__ import annotations

from typing import Dict, Optional, Type

from .base import (
    Capabilities,
    LinkResult,
    ProviderError,
    ProviderStatus,
    ProviderUnavailable,
    TrackerProvider,
    WriteGate,
    WriteNotAuthorized,
    preserve_labels,
)
from .github import GitHubProvider
from .jira import JiraProvider
from .local import LocalMarkdownProvider

PROVIDER_CLASSES: Dict[str, Type[TrackerProvider]] = {
    "github": GitHubProvider,
    "jira": JiraProvider,
    "local": LocalMarkdownProvider,
}


def build_provider(name: str, config, gate: Optional[WriteGate] = None) -> TrackerProvider:
    try:
        provider_class = PROVIDER_CLASSES[name]
    except KeyError:
        raise ProviderError(
            f"unknown provider {name!r} (available: {', '.join(sorted(PROVIDER_CLASSES))})"
        ) from None
    return provider_class(config, gate)


__all__ = [
    "Capabilities",
    "GitHubProvider",
    "JiraProvider",
    "LinkResult",
    "LocalMarkdownProvider",
    "PROVIDER_CLASSES",
    "ProviderError",
    "ProviderStatus",
    "ProviderUnavailable",
    "TrackerProvider",
    "WriteGate",
    "WriteNotAuthorized",
    "build_provider",
    "preserve_labels",
]
