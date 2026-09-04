"""GitHub provider, driven through the `gh` CLI.

`gh` rather than an SDK: the harness already assumes it (`/wrap-up-session` opens
PRs with it), it carries the user's existing auth, and it adds no dependency to
install. Every call is argv-style — no shell string interpolation anywhere.

Two rules this adapter exists to keep:

* **The label vocabulary is the project's, not ours.** `bug`, `enhancement`,
  `design-decision`, `question`, `now`, `next`, `area/*`, `documentation`,
  `tech-debt` are *read* into the normalized model and written back untouched. An
  ordinary sync never creates, renames, or removes a label; a label the mapping
  does not know is preserved verbatim and the task still gets a kind.
* **A number is not an identity.** Matching is by the `task-id` in the body or by
  a recorded reference. Never by title.
"""

from __future__ import annotations

import json
import re
import subprocess
import urllib.parse
from typing import Dict, List, Optional, Sequence

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

REQUIRED_ISSUE_FIELDS = (
    "number", "title", "body", "labels", "state", "url",
    "createdAt", "updatedAt", "assignees",
)
#: Fields a recent `gh` exposes and an older one does not.
#: `closedByPullRequestsReferences` arrived in gh 2.73.0, and `gh` validates
#: `--json` names client-side — so asking an older one for it fails the whole
#: query rather than omitting the field. Absent it, `_linked_pr_state` already
#: reports linked-PR state as unknown, which routing reads as a downgrade. That
#: is the correct degradation; dying is not.
OPTIONAL_ISSUE_FIELDS = ("closedByPullRequestsReferences",)
UNKNOWN_FIELD_RE = re.compile(r'Unknown JSON field: "([^"]+)"')
#: `gh` paginates internally up to this many issues. Reaching it exactly is
#: indistinguishable from "there were more", so it is treated as truncation.
LIST_LIMIT = 500
#: GitHub issue references are numbers. Enforced before a reference reaches argv,
#: so a crafted index row cannot smuggle a second flag into a `gh` invocation.
REF_RE = re.compile(r"^[0-9]+$")


class GitHubProvider(TrackerProvider):
    name = "github"
    #: Sub-issues and issue dependencies exist in GitHub's newer API surface but
    #: are not uniformly available through `gh` across accounts and repo types.
    #: Claiming them here would let the registry report an inferred link as
    #: native, which is the one thing capability degradation must never do.
    capabilities = Capabilities(
        native_hierarchy=False,
        native_dependencies=False,
        comments=True,
        labels=True,
        offline=False,
        atomic_updates=False,
    )
    url_markers = ("github.com",)

    @classmethod
    def reference_label(cls, ref: ExternalRef) -> str:
        return ref.id if ref.id.startswith("#") else f"#{ref.id}"

    def __init__(self, config, gate=None) -> None:
        super().__init__(config, gate)
        self.repository = config.repository
        self.redact = redactor_for(config)
        self._known_labels: Optional[Sequence[str]] = None
        self._unsupported_fields: set = set()

    # ---------------------------------------------------------------- discovery
    def discover(self) -> ProviderStatus:
        try:
            code, output = self._run(["gh", "auth", "status"], check=False)
        except ProviderUnavailable as exc:
            return ProviderStatus(False, str(exc))
        if code != 0:
            return ProviderStatus(
                False,
                "gh is unavailable or unauthenticated — run `gh auth login` "
                f"({self.redact(output.strip().splitlines()[-1]) if output.strip() else 'no output'})",
            )
        if not self.repository:
            try:
                code, output = self._run(
                    ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                    check=False,
                )
            except ProviderUnavailable as exc:
                return ProviderStatus(False, str(exc))
            if code != 0:
                return ProviderStatus(False, "no repository configured and `gh repo view` failed")
            self.repository = output.strip()
        return ProviderStatus(True, f"gh authenticated for {self.repository}")

    # -------------------------------------------------------------------- reads
    def list_tasks(self) -> List[Task]:
        payload = self._issue_json(
            lambda fields: [
                "gh", "issue", "list",
                "--repo", self._repo(),
                "--state", "all",
                "--limit", str(LIST_LIMIT),
                "--json", fields,
            ]
        )
        if len(payload) >= LIST_LIMIT:
            self.result_truncated = True
            self._note(
                f"issue list came back at the {LIST_LIMIT}-issue page limit, so this run "
                "has not seen every issue — publishing now could duplicate the ones past "
                "the cut; narrow the repository or raise LIST_LIMIT"
            )
        return [self._to_task(issue) for issue in payload]

    def get_task(self, ref: ExternalRef) -> Task:
        payload = self._issue_json(
            lambda fields: ["gh", "issue", "view", "--repo", self._repo(), "--json", fields,
                            "--", self._number(ref)]
        )
        return self._to_task(payload)

    def resolve_reference(self, raw: str) -> Optional[ExternalRef]:
        if not raw:
            return None
        candidate = raw.strip()
        if candidate.startswith("http"):
            return self._url_reference(candidate)
        number = candidate.lstrip("#")
        if not number.isdigit():
            return None
        return ExternalRef(
            "github", number, f"https://github.com/{self._repo()}/issues/{number}"
        )

    def _url_reference(self, candidate: str) -> Optional[ExternalRef]:
        parsed = urllib.parse.urlsplit(candidate)
        parts = [part for part in parsed.path.split("/") if part]
        expected_repo = self._repo().lower().split("/")
        if parsed.hostname != "github.com" or len(parts) != 4 or parts[2] != "issues":
            raise ProviderError(f"github: {candidate!r} is not a canonical GitHub issue URL")
        if [part.lower() for part in parts[:2]] != expected_repo:
            raise ProviderError(
                f"github: issue URL belongs to {'/'.join(parts[:2])}, not {self._repo()}"
            )
        return ExternalRef("github", parts[3], candidate) if parts[3].isdigit() else None

    # ------------------------------------------------------------------- writes
    def create_task(self, task: Task) -> Task:
        self.gate.authorize(f"create issue for {task.id}", self.name)
        labels = self._writable_labels(task)
        command = [
            "gh", "issue", "create",
            "--repo", self._repo(),
            "--title", task.title,
            "--body", self._body_for(task, existing=""),
        ]
        for label in labels:
            command += ["--label", label]
        _, output = self._run(command)
        ref = self.resolve_reference(output.strip().splitlines()[-1] if output.strip() else "")
        if ref is None:
            raise ProviderError(
                f"github: issue created for {task.id} but the URL could not be parsed from "
                f"gh output: {self.redact(output.strip())}"
            )
        return task.with_(external=ref)

    def update_task(self, task: Task) -> Task:
        if task.external is None:
            raise ProviderError(f"github: cannot update {task.id} — it has no issue reference")
        self.gate.authorize(f"update issue #{task.external.id} for {task.id}", self.name)
        current = self._json(
            [
                "gh", "issue", "view",
                "--repo", self._repo(), "--json", "body,labels,title",
                "--", self._number(task.external),
            ]
        )
        existing_labels = [label["name"] for label in current.get("labels", [])]
        number = self._number(task.external)
        command = [
            "gh", "issue", "edit",
            "--repo", self._repo(),
            "--body", self._body_for(task, existing=current.get("body", "")),
        ]
        if task.title.strip() and task.title.strip() != (current.get("title") or "").strip():
            command += ["--title", task.title]
        for label in self._writable_labels(task):
            if label not in existing_labels:
                command += ["--add-label", label]
        self._run(command + ["--", number])
        return task

    def close_task(self, task: Task, resolution: str = "done") -> Task:
        if task.external is None:
            raise ProviderError(f"github: cannot close {task.id} — it has no issue reference")
        self.gate.authorize(f"close issue #{task.external.id}", self.name)
        command = ["gh", "issue", "close", "--repo", self._repo()]
        if resolution == "cancelled":
            command += ["--reason", "not planned"]
        self._run(command + ["--", self._number(task.external)])
        return task.with_(status="done" if resolution != "cancelled" else "cancelled")

    def comment(self, task: Task, body: str) -> None:
        if task.external is None:
            raise ProviderError(f"github: cannot comment on {task.id} — no issue reference")
        self.gate.authorize(f"comment on issue #{task.external.id}", self.name)
        self._run(
            [
                "gh", "issue", "comment",
                "--repo", self._repo(), "--body", body,
                "--", self._number(task.external),
            ]
        )

    def link_parent(self, child: Task, parent: Task) -> LinkResult:
        """Hierarchy is preserved in metadata; GitHub issues have no native parent."""
        self.update_task(child.with_(parent=parent.id))
        detail = "GitHub issues expose no parent link through gh; stored as `parent:` metadata"
        self._note(detail)
        return LinkResult("parent", child.id, parent.id, native=False, detail=detail)

    def add_dependency(self, task: Task, depends_on: Task) -> LinkResult:
        merged = tuple(dict.fromkeys(tuple(task.depends_on) + (depends_on.id,)))
        self.update_task(task.with_(depends_on=merged))
        detail = "GitHub has no native issue dependency; stored as `depends-on:` metadata"
        self._note(detail)
        return LinkResult("dependency", task.id, depends_on.id, native=False, detail=detail)

    # ------------------------------------------------- normalization (read-only)
    def _to_task(self, issue: Dict) -> Task:
        labels = tuple(label["name"] for label in issue.get("labels", []))
        state = (issue.get("state") or "OPEN").lower()
        status = self._status_for(state, labels, issue)
        number = str(issue.get("number", ""))
        ref = ExternalRef("github", number, issue.get("url", ""))
        return task_from_metadata(
            title=issue.get("title", "") or f"issue #{number}",
            body=issue.get("body", "") or "",
            external=ref,
            status=status,
            labels=labels,
            fallback_id="",
            kind=self._kind_for(labels),
            priority=self._priority_for(labels),
            area=self._area_for(labels),
            created_at=issue.get("createdAt"),
            updated_at=issue.get("updatedAt"),
            extra=self._linked_pr_state(issue),
        )

    @staticmethod
    def _linked_pr_state(issue: Dict) -> Dict[str, str]:
        if "closedByPullRequestsReferences" not in issue:
            return {}
        references = issue.get("closedByPullRequestsReferences") or []
        unresolved = any(
            str(reference.get("state", "")).upper() not in ("MERGED", "CLOSED")
            for reference in references
        )
        return {"unresolved_linked_pr": "true" if unresolved else "false"}

    def _kind_for(self, labels: Sequence[str]) -> str:
        for label in labels:
            mapped = self.config.kind_labels.get(label)
            if mapped:
                return mapped
        return "task"

    def _priority_for(self, labels: Sequence[str]) -> Optional[str]:
        for label in labels:
            mapped = self.config.priority_labels.get(label)
            if mapped:
                return mapped
        return None  # no queue label means unset, not "low"

    @staticmethod
    def _area_for(labels: Sequence[str]) -> Optional[str]:
        for label in labels:
            if label.startswith("area/"):
                return label[len("area/") :]
        return None

    def _status_for(self, state: str, labels: Sequence[str], issue: Dict) -> str:
        """open/closed maps to open/done. Anything richer must be configured.

        `in_progress` and `blocked` have no representation in GitHub's issue state,
        so inferring them would be invention. They come only from a source the
        project named in `[status]`.
        """
        base = "done" if state == "closed" else "open"
        if base == "done":
            return base
        for status, source in self.config.status_sources.items():
            if self._status_source_matches(source, labels, issue):
                return status
        return base

    def _status_source_matches(self, source: str, labels: Sequence[str], issue: Dict) -> bool:
        source = (source or "").strip()
        if source.startswith("label:"):
            return source[len("label:") :].strip() in labels
        if source == "assignee":
            return bool(issue.get("assignees"))
        if source.startswith("field:"):
            self._note(
                f"status source {source!r} needs a GitHub Projects field, which this "
                "adapter cannot read through gh — status left at the issue state"
            )
            return False
        if source:
            self._note(f"unrecognized status source {source!r} — ignored, status left at issue state")
        return False

    # -------------------------------------------------------- write-side helpers
    def _body_for(self, task: Task, existing: str) -> str:
        """Only the metadata block is ours. Everything a human wrote survives."""
        base = existing if existing.strip() else _seed_body(task)
        return upsert_metadata_block(base, task)

    def _writable_labels(self, task: Task) -> Sequence[str]:
        """Labels we may pass to gh: every existing one, plus mapped ones that exist.

        A mapped label that does not exist in the repository is *reported*, not
        created — creating it would mutate the project's vocabulary during an
        ordinary sync.
        """
        desired = preserve_labels(task.labels, self._mapped_labels(task))
        known = self._repo_labels()
        if known is None:
            return tuple(task.labels)
        writable = []
        for label in desired:
            if label in known:
                writable.append(label)
            elif self.config.allow_label_creation and self._create_label(label):
                writable.append(label)
            else:
                self._note(
                    f"label {label!r} does not exist in {self._repo()} and "
                    "allow_label_creation is off — issue written without it"
                )
        return tuple(writable)

    def _create_label(self, label: str) -> bool:
        """Add one label to the repository vocabulary. Only ever reached via config.

        Creation is a mutation of the *project's* vocabulary, so it is gated twice:
        `allow_label_creation` must be on, and the write gate must be open like any
        other external write.
        """
        self.gate.authorize(f"create label {label!r}", self.name)
        code, output = self._run(
            ["gh", "label", "create", "--repo", self._repo(), "--", label], check=False
        )
        if code != 0:
            self._note(
                f"could not create label {label!r} — {self.redact(output.strip()) or 'no output'}"
            )
            return False
        self._known_labels = tuple(self._known_labels or ()) + (label,)
        self._note(f"created label {label!r} because allow_label_creation is on")
        return True

    def _mapped_labels(self, task: Task) -> Sequence[str]:
        """The provider-facing labels implied by the normalized record."""
        implied = []
        for label, kind in self.config.kind_labels.items():
            if kind == task.kind:
                implied.append(label)
                break
        for label, priority in self.config.priority_labels.items():
            if task.priority and priority == task.priority:
                implied.append(label)
                break
        if task.area:
            implied.append(f"area/{task.area}")
        return tuple(implied)

    def _repo_labels(self) -> Optional[Sequence[str]]:
        if self._known_labels is not None:
            return self._known_labels
        try:
            payload = self._json(
                ["gh", "label", "list", "--repo", self._repo(), "--limit", "200", "--json", "name"]
            )
        except ProviderError as exc:
            self._note(f"could not list labels ({exc}); existing labels preserved, none added")
            return None
        self._known_labels = tuple(entry["name"] for entry in payload)
        return self._known_labels

    # ------------------------------------------------------------- gh plumbing
    def _number(self, ref: ExternalRef) -> str:
        """The issue number as a positional argument, or a refusal.

        Every call site also passes `--` before its positionals; this is the other
        half of the same guard, because a value that is not a number has no
        business reaching `gh` at all.
        """
        number = str(ref.id).lstrip("#").strip()
        if not REF_RE.match(number):
            raise ProviderError(
                f"github: {ref.id!r} is not an issue number — refusing to pass it to gh"
            )
        return number

    def _repo(self) -> str:
        if not self.repository:
            raise ProviderError(
                "github: no repository configured — set `repository = owner/name` in the "
                "task-tracking configuration, or run inside a repo with a GitHub remote"
            )
        return self.repository

    def _run(self, command: Sequence[str], check: bool = True):
        try:
            completed = subprocess.run(
                list(command),
                cwd=self.config.root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=60,
            )
        except FileNotFoundError as exc:
            raise ProviderUnavailable(
                "github: the `gh` CLI is not installed — install it or set provider = local"
            ) from exc
        except subprocess.SubprocessError as exc:
            raise ProviderUnavailable(f"github: gh invocation failed — {self.redact(str(exc))}") from exc
        output = (completed.stdout or "") + (completed.stderr or "")
        if check and completed.returncode != 0:
            raise ProviderError(
                f"github: `{' '.join(command[:3])}` exited {completed.returncode} — "
                f"{self.redact(output.strip()) or 'no output'}"
            )
        return completed.returncode, output

    def _issue_fields(self) -> str:
        optional = [f for f in OPTIONAL_ISSUE_FIELDS if f not in self._unsupported_fields]
        return ",".join(list(REQUIRED_ISSUE_FIELDS) + optional)

    def _issue_json(self, build):
        """Read issues, degrading once if this `gh` predates an optional field.

        `build(fields)` returns the argv for the read. A required field that `gh`
        rejects is still a hard failure: dropping it would hand the caller a task
        with a silently missing identity, which is worse than the refusal.
        """
        try:
            return self._json(build(self._issue_fields()))
        except ProviderError as exc:
            match = UNKNOWN_FIELD_RE.search(str(exc))
            field = match.group(1) if match else ""
            if field not in OPTIONAL_ISSUE_FIELDS or field in self._unsupported_fields:
                raise
            self._unsupported_fields.add(field)
            self._note(
                f"this gh does not support the `{field}` issue field, so linked pull "
                "request state is unknown for every issue this run; upgrade to gh 2.73.0 "
                "or newer to restore it"
            )
            return self._json(build(self._issue_fields()))

    def _json(self, command: Sequence[str]):
        _, output = self._run(command)
        payload = output[output.find("[") :] if output.lstrip().startswith("[") else output
        try:
            return json.loads(payload.strip() or "[]")
        except json.JSONDecodeError as exc:
            raise ProviderError(
                f"github: could not parse gh JSON output — {exc}; got: "
                f"{self.redact(output.strip()[:200])}"
            ) from exc


def _seed_body(task: Task) -> str:
    """The initial body for a brand-new issue: summary, criteria, spec link."""
    parts: List[str] = []
    if task.summary:
        parts += [task.summary.strip(), ""]
    if task.acceptance_criteria:
        parts.append("## Acceptance Criteria")
        parts.append("")
        parts += [f"- [ ] {item}" for item in task.acceptance_criteria]
        parts.append("")
    if task.spec_path:
        parts += [f"Spec: `{task.spec_path}`", ""]
    return "\n".join(parts)
