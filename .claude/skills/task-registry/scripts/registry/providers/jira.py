"""Jira provider over a small stdlib HTTP seam.

Optional and never implicit: a reachable Jira is not permission to write to a
company tracker, so this adapter runs only when the project configuration names
`provider = jira`.

No SDK. `urllib.request` behind a one-method transport is the entire dependency
surface, which keeps the harness installable anywhere Python is. The REST v2
endpoints are used deliberately: v3 takes descriptions as Atlassian Document
Format, and round-tripping ADF would mean this adapter owns a rich-text model it
has no business owning — the metadata block has to survive byte-for-byte.

Every error path passes through the redactor before it becomes text.
"""

from __future__ import annotations

import base64
import http.client
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional, Sequence, Tuple

from ..config import ConfigError, require_secure_transport
from ..model import ExternalRef, Task, task_from_metadata, upsert_metadata_block
from ..redaction import redactor_for
from .base import (
    Capabilities,
    LinkResult,
    ProviderError,
    ProviderStatus,
    ProviderUnavailable,
    TrackerProvider,
    preserve_labels,
)

API = "/rest/api/2"
BLOCKS_LINK_TYPE = "Blocks"
#: Jira issue keys: an uppercase project key, a hyphen, a number. Validated before
#: a key is ever interpolated into a request path.
KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*-[0-9]+$")
#: Pages of 100 issues, bounded. Unbounded paging against a large site would hang
#: a session; stopping is fine as long as the caller is told it happened.
PAGE_SIZE = 100
MAX_PAGES = 20


class _CredentialStrippingRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Drops the Authorization header when a redirect leaves the original origin.

    `urllib` replays every header it was given onto the redirect target, so a Jira
    site that answers with `302 https://attacker.example/` would be handed the
    Basic credentials verbatim. Same-origin redirects keep the header, because
    that is an ordinary Jira behaviour (trailing-slash and `/rest` rewrites).
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_request = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_request is None:
            return None
        if _origin(req.full_url) != _origin(newurl):
            for header in list(new_request.headers):
                if header.lower() in ("authorization", "cookie", "proxy-authorization"):
                    del new_request.headers[header]
        return new_request


def _origin(url: str) -> Tuple[str, str, Optional[int]]:
    parsed = urllib.parse.urlsplit(url)
    return (parsed.scheme, (parsed.hostname or "").lower(), parsed.port)


class HttpTransport:
    """The seam. One method, so a test or another harness can substitute it."""

    def __init__(self, timeout: int = 30) -> None:
        self.timeout = timeout
        self._opener = urllib.request.build_opener(_CredentialStrippingRedirectHandler())

    def request(
        self, method: str, url: str, headers: Dict[str, str], body: Optional[bytes]
    ) -> Tuple[int, str]:
        request = urllib.request.Request(url=url, data=body, method=method, headers=headers)
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                return response.status, response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as exc:
            raise ConnectionError(str(exc.reason)) from exc
        except http.client.HTTPException as exc:
            # A malformed base URL (`http.client.InvalidURL`) lands here. It has
            # to become a ConnectionError like every other unreachable-site case,
            # because only the caller redacts — and the message quotes the URL,
            # which is exactly where an embedded credential would be.
            raise ConnectionError(f"{type(exc).__name__}: {exc}") from exc
        except OSError as exc:
            raise ConnectionError(str(exc)) from exc


class JiraProvider(TrackerProvider):
    name = "jira"
    #: Hierarchy and dependencies are native *when the site allows them*. Both are
    #: attempted and degrade to metadata with `native=False` on refusal, because a
    #: team-managed project, a missing link type, or a permission gap all present
    #: as a failed link rather than an absent feature.
    capabilities = Capabilities(
        native_hierarchy=True,
        native_dependencies=True,
        comments=True,
        labels=True,
        offline=False,
        atomic_updates=False,
    )
    url_markers = ("/browse/",)

    def __init__(self, config, gate=None, transport: Optional[HttpTransport] = None) -> None:
        super().__init__(config, gate)
        self.transport = transport or HttpTransport()
        self.redact = redactor_for(config)

    # ---------------------------------------------------------------- discovery
    def discover(self) -> ProviderStatus:
        missing = [
            name
            for name, value in (
                ("JIRA_BASE_URL", self.config.jira_base_url),
                ("JIRA_EMAIL", self.config.jira_email),
                ("JIRA_API_TOKEN", self.config.jira_token.reveal()),
                ("project", self.config.project),
            )
            if not value
        ]
        if missing:
            return ProviderStatus(False, f"jira: missing {', '.join(missing)}")
        try:
            require_secure_transport(self.config.jira_base_url, os.environ)
        except ConfigError as exc:
            return ProviderStatus(False, str(exc))
        try:
            status, _ = self._call("GET", f"{API}/myself")
        except ProviderUnavailable as exc:
            return ProviderStatus(False, str(exc))
        if status == 401 or status == 403:
            return ProviderStatus(
                False, f"jira: authentication rejected (HTTP {status}) — check JIRA_EMAIL/JIRA_API_TOKEN"
            )
        if status >= 400:
            return ProviderStatus(False, f"jira: site returned HTTP {status}")
        return ProviderStatus(
            True, self.redact(f"jira {self.config.project} at {self.config.jira_base_url}")
        )

    # -------------------------------------------------------------------- reads
    def list_tasks(self) -> List[Task]:
        issues: List[Dict] = []
        for page in range(MAX_PAGES):
            query = urllib.parse.urlencode(
                {
                    "jql": f"project = {self.config.project} ORDER BY created DESC",
                    "startAt": str(page * PAGE_SIZE),
                    "maxResults": str(PAGE_SIZE),
                    "fields": (
                        "summary,description,status,labels,issuetype,"
                        "priority,parent,issuelinks"
                    ),
                }
            )
            payload = self._json("GET", f"{API}/search?{query}")
            batch = payload.get("issues", [])
            issues.extend(batch)
            total = payload.get("total")
            if len(batch) < PAGE_SIZE or (total is not None and len(issues) >= total):
                break
        else:
            self.result_truncated = True
            self._note(
                f"stopped after {MAX_PAGES * PAGE_SIZE} issues, so this run has not seen "
                "every issue in the project — publishing now could duplicate the rest"
            )
        return [self._to_task(issue) for issue in issues]

    def get_task(self, ref: ExternalRef) -> Task:
        return self._to_task(self._json("GET", f"{API}/issue/{self._key(ref)}"))

    def resolve_reference(self, raw: str) -> Optional[ExternalRef]:
        if not raw:
            return None
        candidate = raw.strip()
        if candidate.startswith("http"):
            key = candidate.rstrip("/").rsplit("/", 1)[-1]
            return ExternalRef("jira", key, candidate) if "-" in key else None
        if "-" not in candidate:
            return None
        return ExternalRef("jira", candidate, self._browse_url(candidate))

    # ------------------------------------------------------------------- writes
    def create_task(self, task: Task) -> Task:
        self.gate.authorize(f"create issue for {task.id}", self.name)
        fields = {
            "project": {"key": self.config.project},
            "summary": task.title,
            "description": upsert_metadata_block(_seed_body(task), task),
            "issuetype": {"name": self._issue_type_for(task.kind)},
            "labels": list(preserve_labels(task.labels)),
        }
        payload = self._json("POST", f"{API}/issue", {"fields": fields})
        key = payload.get("key")
        if not key:
            raise ProviderError(f"jira: create returned no issue key for {task.id}")
        return task.with_(external=ExternalRef("jira", key, self._browse_url(key)))

    def update_task(self, task: Task) -> Task:
        if task.external is None:
            raise ProviderError(f"jira: cannot update {task.id} — it has no issue reference")
        self.gate.authorize(f"update issue {task.external.id}", self.name)
        key = self._key(task.external)
        current = self._json("GET", f"{API}/issue/{key}")
        current_fields = current.get("fields", {})
        body = current_fields.get("description") or ""
        fields = {
            "description": upsert_metadata_block(body, task),
            "labels": list(preserve_labels(current_fields.get("labels", []), task.labels)),
        }
        # Only rewrite the summary when it actually differs, so a title edited in
        # Jira is not clobbered by a stale local row on every sync.
        if task.title.strip() and task.title.strip() != (current_fields.get("summary") or "").strip():
            fields["summary"] = task.title
        self._json("PUT", f"{API}/issue/{key}", {"fields": fields})
        return task

    def close_task(self, task: Task, resolution: str = "done") -> Task:
        if task.external is None:
            raise ProviderError(f"jira: cannot close {task.id} — it has no issue reference")
        self.gate.authorize(f"close issue {task.external.id}", self.name)
        key = self._key(task.external)
        available = self._json("GET", f"{API}/issue/{key}/transitions")
        wanted = "done" if resolution != "cancelled" else "cancel"
        for transition in available.get("transitions", []):
            name = (transition.get("name") or "").lower()
            category = (
                transition.get("to", {}).get("statusCategory", {}).get("key", "")
            ).lower()
            if wanted in name or category == "done":
                self._json(
                    "POST",
                    f"{API}/issue/{key}/transitions",
                    {"transition": {"id": transition["id"]}},
                )
                return task.with_(status="done" if resolution != "cancelled" else "cancelled")
        names = ", ".join(t.get("name", "?") for t in available.get("transitions", []))
        raise ProviderError(
            f"jira: no closing transition available for {task.external.id} "
            f"(offered: {names or 'none'}) — close it in Jira or configure a workflow transition"
        )

    def comment(self, task: Task, body: str) -> None:
        if task.external is None:
            raise ProviderError(f"jira: cannot comment on {task.id} — no issue reference")
        self.gate.authorize(f"comment on issue {task.external.id}", self.name)
        self._json(
            "POST", f"{API}/issue/{self._key(task.external)}/comment", {"body": body}
        )

    def link_parent(self, child: Task, parent: Task) -> LinkResult:
        if child.external is None or parent.external is None:
            raise ProviderError("jira: both tasks need issue references before linking")
        self.gate.authorize(f"link {child.external.id} under {parent.external.id}", self.name)
        status, text = self._call(
            "PUT",
            f"{API}/issue/{self._key(child.external)}",
            {"fields": {"parent": {"key": self._key(parent.external)}}},
        )
        if status < 400:
            return LinkResult("parent", child.id, parent.id, native=True)
        detail = (
            f"jira refused a native parent link (HTTP {status}) — this project's hierarchy "
            "may not allow it; stored as `parent:` metadata instead"
        )
        self._note(detail, text)
        self.update_task(child.with_(parent=parent.id))
        return LinkResult("parent", child.id, parent.id, native=False, detail=detail)

    def add_dependency(self, task: Task, depends_on: Task) -> LinkResult:
        if task.external is None or depends_on.external is None:
            raise ProviderError("jira: both tasks need issue references before linking")
        self.gate.authorize(
            f"link {depends_on.external.id} blocks {task.external.id}", self.name
        )
        status, text = self._call(
            "POST",
            f"{API}/issueLink",
            {
                "type": {"name": BLOCKS_LINK_TYPE},
                "inwardIssue": {"key": task.external.id},
                "outwardIssue": {"key": depends_on.external.id},
            },
        )
        if status < 400:
            return LinkResult("dependency", task.id, depends_on.id, native=True)
        detail = (
            f"jira refused a native '{BLOCKS_LINK_TYPE}' link (HTTP {status}) — "
            "stored as `depends-on:` metadata instead"
        )
        self._note(detail, text)
        merged = tuple(dict.fromkeys(tuple(task.depends_on) + (depends_on.id,)))
        self.update_task(task.with_(depends_on=merged))
        return LinkResult("dependency", task.id, depends_on.id, native=False, detail=detail)

    # ------------------------------------------------- normalization (read-only)
    def _to_task(self, issue: Dict) -> Task:
        fields = issue.get("fields", {})
        key = issue.get("key", "")
        labels = tuple(fields.get("labels", []) or ())
        return task_from_metadata(
            title=fields.get("summary", "") or key,
            body=fields.get("description") or "",
            external=ExternalRef("jira", key, self._browse_url(key)),
            status=self._status_for(fields, labels),
            labels=labels,
            fallback_id="",
            kind=self._kind_for(fields),
            priority=self._priority_for(fields),
            created_at=fields.get("created"),
            updated_at=fields.get("updated"),
        )

    def _kind_for(self, fields: Dict) -> str:
        name = (fields.get("issuetype") or {}).get("name", "")
        return self.config.jira_issue_types.get(name, "task")

    def _priority_for(self, fields: Dict) -> Optional[str]:
        name = (fields.get("priority") or {}).get("name", "")
        return self.config.jira_priorities.get(name)

    def _status_for(self, fields: Dict, labels: Sequence[str]) -> str:
        """Jira has native workflow state, so it maps directly — no inference."""
        for status, source in self.config.status_sources.items():
            if source.startswith("label:") and source[len("label:") :].strip() in labels:
                return status
        status_field = fields.get("status") or {}
        category = (status_field.get("statusCategory") or {}).get("key", "").lower()
        name = (status_field.get("name") or "").strip().lower()
        if name in ("blocked", "on hold"):
            return "blocked"
        if category == "done":
            return "cancelled" if name in ("cancelled", "canceled", "won't do") else "done"
        if category == "indeterminate":
            return "in_progress"
        return "open"

    def _issue_type_for(self, kind: str) -> str:
        for name, mapped in self.config.jira_issue_types.items():
            if mapped == kind:
                return name
        self._note(
            f"no Jira issue type is mapped to kind {kind!r}; created as Task "
            "(add one under [jira.issuetype] to change this)"
        )
        return "Task"

    # ------------------------------------------------------------ HTTP plumbing
    def _key(self, ref: ExternalRef) -> str:
        """The issue key, validated and percent-encoded before it becomes a path.

        A reference read out of `tasks/todo.md` is untrusted text; unchecked it
        could carry `../` or a query string and reach a different endpoint than
        the one the caller named.
        """
        key = str(ref.id).strip()
        if not KEY_RE.match(key):
            raise ProviderError(
                f"jira: {ref.id!r} is not an issue key (expected PROJ-123) — "
                "refusing to build a request path from it"
            )
        return urllib.parse.quote(key, safe="")

    def _browse_url(self, key: str) -> str:
        return f"{self.config.jira_base_url}/browse/{key}" if self.config.jira_base_url else ""

    def _headers(self) -> Dict[str, str]:
        raw = f"{self.config.jira_email}:{self.config.jira_token.reveal()}".encode("utf-8")
        return {
            "Authorization": "Basic " + base64.b64encode(raw).decode("ascii"),
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def _call(self, method: str, path: str, payload: Optional[Dict] = None) -> Tuple[int, str]:
        if not self.config.jira_base_url:
            raise ProviderUnavailable("jira: JIRA_BASE_URL is not set")
        url = self.config.jira_base_url + path
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        try:
            return self.transport.request(method, url, self._headers(), body)
        except ConnectionError as exc:
            raise ProviderUnavailable(
                self.redact(f"jira: cannot reach {self.config.jira_base_url} — {exc}")
            ) from exc

    def _json(self, method: str, path: str, payload: Optional[Dict] = None):
        status, text = self._call(method, path, payload)
        if status >= 400:
            raise ProviderError(
                f"jira: {method} {path.split('?')[0]} returned HTTP {status} — "
                f"{self.redact(text.strip()[:300]) or 'no body'}"
            )
        if not text.strip():
            return {}
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise ProviderError(
                f"jira: unparseable response from {path.split('?')[0]} — {exc}"
            ) from exc

    def _note(self, detail: str, context: str = "") -> None:
        message = detail if not context else f"{detail} [{self.redact(context.strip()[:160])}]"
        if message not in self.limitations:
            self.limitations.append(message)


def _seed_body(task: Task) -> str:
    parts: List[str] = []
    if task.summary:
        parts += [task.summary.strip(), ""]
    if task.acceptance_criteria:
        parts.append("Acceptance criteria:")
        parts += [f"* {item}" for item in task.acceptance_criteria]
        parts.append("")
    if task.spec_path:
        parts += [f"Spec: {task.spec_path}", ""]
    return "\n".join(parts)
