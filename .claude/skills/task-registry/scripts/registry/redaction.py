"""Credential redaction.

Applied at the boundary where provider text becomes user-visible text — error
messages, verbose traces, reports — rather than trusted to each call site. A
credential leaks exactly once and then has to be rotated, so the redactor errs
toward over-masking: any Authorization header, any Basic/Bearer payload, and any
literal secret value the configuration knows about.
"""

from __future__ import annotations

import re
from typing import Iterable, Sequence

MASK = "***REDACTED***"

_PATTERNS: Sequence["re.Pattern[str]"] = (
    re.compile(r"(?i)(authorization\s*[:=]\s*)([^\s,'\"]+)"),
    re.compile(r"(?i)\b(bearer|basic)\s+([A-Za-z0-9._~+/=-]{8,})"),
    re.compile(r"(?i)(api[_-]?token|password|secret)(\s*[:=]\s*)([^\s,'\"]+)"),
    re.compile(r"(?i)(https?://)([^/\s:@]+):([^/\s@]+)@"),
)


class Redactor:
    """Masks known secret values plus anything that looks like a credential."""

    def __init__(self, secrets: Iterable[str] = ()) -> None:
        self._secrets = tuple(sorted({s for s in secrets if s and len(s) >= 4}, key=len, reverse=True))

    def __call__(self, text: str) -> str:
        return self.scrub(text)

    def scrub(self, text: str) -> str:
        if text is None:
            return ""
        scrubbed = str(text)
        for secret in self._secrets:
            scrubbed = scrubbed.replace(secret, MASK)
        scrubbed = _PATTERNS[0].sub(lambda m: m.group(1) + MASK, scrubbed)
        scrubbed = _PATTERNS[1].sub(lambda m: m.group(1) + " " + MASK, scrubbed)
        scrubbed = _PATTERNS[2].sub(lambda m: m.group(1) + m.group(2) + MASK, scrubbed)
        scrubbed = _PATTERNS[3].sub(lambda m: m.group(1) + m.group(2) + ":" + MASK + "@", scrubbed)
        return scrubbed


def redactor_for(config) -> Redactor:
    """Build a redactor from whatever credentials this project's config holds."""
    secrets = []
    token = getattr(config, "jira_token", None)
    if token is not None and getattr(token, "reveal", None):
        secrets.append(token.reveal())
    return Redactor(secrets)
