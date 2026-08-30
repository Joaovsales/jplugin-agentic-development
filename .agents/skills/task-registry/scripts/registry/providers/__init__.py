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


#: Where an unrecognised URL lands. Local is the safe answer: it is the provider
#: that never leaves the machine, so a misclassified link cannot cause a call to
#: somebody else's tracker.
FALLBACK_PROVIDER = "local"


def provider_for_url(url: str) -> str:
    """Which tracker owns this task URL. Asks the providers; never pattern-matches here."""
    for name, provider_class in PROVIDER_CLASSES.items():
        if provider_class.owns_url(url):
            return name
    return FALLBACK_PROVIDER


def reference_label(ref) -> str:
    """Render an external reference the way its own tracker writes it."""
    provider_class = PROVIDER_CLASSES.get(ref.provider)
    return provider_class.reference_label(ref) if provider_class else ref.id


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
    "provider_for_url",
    "reference_label",
]
