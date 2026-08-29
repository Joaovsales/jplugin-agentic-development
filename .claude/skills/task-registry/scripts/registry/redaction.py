"""Credential redaction.

Applied at the boundary where provider text becomes user-visible text — error
messages, verbose traces, reports — rather than trusted to each call site. A
credential leaks exactly once and then has to be rotated, so the redactor errs
toward over-masking: any Authorization header, any Basic/Bearer payload, and any
literal secret value the configuration knows about.
"""

from __future__ import annotations

import re
import urllib.parse
from typing import Iterable, Sequence

MASK = "***REDACTED***"

_PATTERNS: Sequence["re.Pattern[str]"] = (
    # The whole rest of the line, not just the next token: an Authorization value
    # is `Basic <payload>`, and masking only the word `Basic` leaves the payload.
    re.compile(r"(?im)^(.*?authorization\s*[:=]\s*)(.+)$"),
    re.compile(r"(?i)\b(bearer|basic)\s+([A-Za-z0-9._~+/=-]{8,})"),
    re.compile(r"(?i)(api[_-]?token|password|secret)(\s*[:=]\s*)([^\s,'\"]+)"),
    re.compile(r"(?i)(https?://)([^/\s:@]+):([^/\s@]+)@"),
)


class Redactor:
    """Masks known secret values plus anything that looks like a credential."""

    def __init__(self, secrets: Iterable[str] = ()) -> None:
        self._secrets = tuple(
            sorted({s for s in secrets if s and len(s) >= 4}, key=len, reverse=True)
        )

    def adopt(self, other: "Redactor") -> None:
        """Take on another redactor's secrets.

        The top-level handler has to exist *before* configuration is read, since
        reading it is one of the things that can fail. Adopting afterwards is how
        that handler learns the credentials it must mask without the caller
        having to remember to re-wrap every later print.
        """
        self._secrets = tuple(
            sorted(set(self._secrets) | set(other._secrets), key=len, reverse=True)
        )

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
    secrets += _url_credentials(getattr(config, "jira_base_url", ""))
    return Redactor(secrets)


def _url_credentials(url: str) -> Sequence[str]:
    """Userinfo embedded in a configured URL.

    A base URL of `https://user:token@site` puts a live credential into every
    message that names the site — including error text where it appears without
    the scheme, which no generic pattern can recognise. Naming it as a known
    secret is the only reliable way to mask it.
    """
    if "@" not in (url or ""):
        return ()
    parsed = urllib.parse.urlsplit(url)
    return tuple(part for part in (parsed.password, parsed.username) if part)
