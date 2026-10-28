"""Provider registry.

A dict, not an if-chain: adding a tracker means adding an entry, and nothing in
the core has to learn its name (AGENTS.md § *SOLID*, open/closed).
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
from .local import LocalMarkdownProvider

PROVIDER_CLASSES: Dict[str, Type[TrackerProvider]] = {
    "github": GitHubProvider,
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


def keyword_reference(raw: str, provider: Optional[str] = None) -> Optional[str]:
    """The reference a PR writes after `Closes` for `raw`, or None when no tracker closes it.

    Names a provider when the caller knows the owner (an external reference);
    otherwise the first provider whose grammar reads `raw` answers.
    """
    classes = [PROVIDER_CLASSES[provider]] if provider in PROVIDER_CLASSES else PROVIDER_CLASSES.values()
    return next((ref for ref in (c.keyword_reference(raw) for c in classes) if ref), None)


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
    "keyword_reference",
    "preserve_labels",
    "provider_for_url",
    "reference_label",
]
