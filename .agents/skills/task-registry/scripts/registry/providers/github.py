"""GitHub provider, driven through the `gh` CLI.

`gh` rather than an SDK: the harness already assumes it (`/wrap-up-session` opens
PRs with it), it carries the user's existing auth, and it adds no dependency to
install. Every call is `gh api` against the REST API, never `gh issue`, `gh
label`, `gh repo` or `gh auth`: those speak GraphQL, which the Claude Code cloud
sandbox's proxy refuses while REST goes through. Every call is argv-style — no
shell string interpolation anywhere.

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
from typing import Dict, List, Optional, Sequence, Tuple

from ..config import github_remote
from ..model import (
    BLOCK_STATE_NOTES,
    ExternalRef,
    Task,
    TaskModelError,
    metadata_block_state,
    section,
    task_from_metadata,
    upsert_metadata_block,
)
from ..redaction import redactor_for
from .base import (
    Capabilities,
    LinkResult,
    ProviderError,
    ProviderStatus,
    ProviderUnavailable,
    TrackerProvider,
    add_unique_labels,
    has_label,
    preserve_labels,
)

#: Transitional until the timeline read lands: the linked-PR exclusion still
#: reads `closedByPullRequestsReferences` and `stateReason` off an issue entry
#: that carries them, and `linked_pr_exclusion_available()` still keys on them.
OPTIONAL_ISSUE_FIELDS = ("closedByPullRequestsReferences", "stateReason")
#: `gh` lists an issue's closing pull requests without their state, so the
#: states come from one GraphQL read per batch of node ids; `nodes(ids:)`
#: accepts at most 100.
PR_STATE_QUERY = "query($ids: [ID!]!) { nodes(ids: $ids) { ... on PullRequest { id state } } }"
PR_STATE_BATCH = 100
#: Issues are read `PAGE_SIZE` at a time (REST's maximum) up to this many.
#: Reaching the cap exactly is indistinguishable from "there were more", so it
#: is treated as truncation.
PAGE_SIZE = 100
LIST_LIMIT = 500
#: Same reasoning for the label vocabulary. It backs a pass/fail gate now, so a
#: silently truncated read would report existing labels as missing.
LABEL_LIST_LIMIT = 1000
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
            code, output = self._run(["gh", "api", "user"], check=False)
        except ProviderUnavailable as exc:
            return ProviderStatus(False, str(exc))
        if code != 0:
            return ProviderStatus(
                False,
                "gh is unavailable or unauthenticated — run `gh auth login` "
                f"({self.redact(output.strip().splitlines()[-1]) if output.strip() else 'no output'})",
            )
        try:
            self._repo()
        except ProviderError as exc:
            return ProviderStatus(False, str(exc))
        return ProviderStatus(True, f"gh authenticated for {self.repository}")

    # -------------------------------------------------------------------- reads
    def list_tasks(self) -> List[Task]:
        return [self._to_task(issue) for issue in self._list_issues()]

    def list_tasks_with_linked_prs(self) -> List[Task]:
        issues = self._list_issues()
        pr_states = self._read_pr_states(issues)
        return [self._to_task(issue, self._linked_pr_state(issue, pr_states)) for issue in issues]

    def _list_issues(self) -> List[Dict]:
        """Every issue in the repository, paged; pull requests dropped.

        REST lists pull requests among the issues, marked by a `pull_request`
        key. They count against the cap -- it bounds what this run read, not
        what it kept -- and are discarded before normalization.
        """
        entries, complete = self._paged("issues", LIST_LIMIT, "state=all")
        if not complete:
            self.result_truncated = True
            self._note(
                f"issue list came back at the {LIST_LIMIT}-issue page limit, so this run "
                "has not seen every issue — publishing now could duplicate the ones past "
                "the cut; narrow the repository or raise LIST_LIMIT"
            )
        return [entry for entry in entries if "pull_request" not in entry]

    def get_task(self, ref: ExternalRef) -> Task:
        payload = self._json(["gh", "api", self._path("issues", self._number(ref))])
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
        if parsed.hostname != "github.com" or len(parts) != 4 or parts[2] != "issues":
            raise ProviderError(f"github: {candidate!r} is not a canonical GitHub issue URL")
        if not self._is_this_repo(parts[0], parts[1]):
            raise ProviderError(
                f"github: issue URL belongs to {'/'.join(parts[:2])}, not {self._repo()}"
            )
        return ExternalRef("github", parts[3], candidate) if parts[3].isdigit() else None

    def closing_references(self, raw: str) -> List[ExternalRef]:
        """The issues a merged PR's closing keywords name, whatever their state.

        GitHub fires those keywords only for some mergers: a merge made with a
        workflow's GITHUB_TOKEN closes nothing (#146), so this read is how the
        merger finds out what the merge still owes.
        """
        number = self._number(ExternalRef("github", str(raw)))
        payload = self._json(
            ["gh", "pr", "view", "--repo", self._repo(),
             "--json", "state,closingIssuesReferences", "--", number]
        )
        state = payload.get("state") or "unknown"
        if state != "MERGED":
            raise ProviderError(
                f"github: #{number} is not merged (state {state}) — run this after the merge"
            )
        here, elsewhere = [], []
        for issue in payload.get("closingIssuesReferences") or []:
            owner, name = self._node_repo(issue)
            if self._is_this_repo(owner, name):
                here.append(ExternalRef("github", str(issue.get("number")), issue.get("url", "")))
            else:
                elsewhere.append(f"{owner}/{name}#{issue.get('number')}")
        if elsewhere:
            raise ProviderError(
                f"github: #{number} closes {', '.join(elsewhere)}, outside {self._repo()} — "
                "close those there; nothing was closed"
            )
        return here

    # ------------------------------------------------------------------- writes
    def create_task(self, task: Task) -> Task:
        self.gate.authorize(f"create issue for {task.id}", self.name)
        created = self._write("POST", self._path("issues"), {
            "title": task.title,
            "body": self._body_for(task, existing=""),
            "labels": list(self._writable_labels(task)),
        })
        ref = self.resolve_reference(str(created.get("html_url") or ""))
        if ref is None:
            raise ProviderError(
                f"github: issue created for {task.id} but the response carried no issue "
                f"URL: {self.redact(json.dumps(created)[:200])}"
            )
        return task.with_(external=ref)

    def update_task(self, task: Task) -> Task:
        if task.external is None:
            raise ProviderError(f"github: cannot update {task.id} — it has no issue reference")
        self.gate.authorize(f"update issue #{task.external.id} for {task.id}", self.name)
        number = self._number(task.external)
        current = self._json(["gh", "api", self._path("issues", number)])
        existing_labels = [label["name"] for label in current.get("labels", [])]
        payload = {"body": self._body_for(task, existing=current.get("body") or "")}
        if task.title.strip() and task.title.strip() != (current.get("title") or "").strip():
            payload["title"] = task.title
        additions = [
            label for label in self._writable_labels(task) if not has_label(existing_labels, label)
        ]
        self._write("PATCH", self._path("issues", number), payload)
        if not additions:
            return task
        # REST has no single call that edits a body and adds labels. A failure
        # here lands after the PATCH, so it says what already happened: the
        # operator retries the labels, not a body the issue already carries.
        try:
            self._add_issue_labels(number, additions)
        except ProviderError as exc:
            raise ProviderError(
                f"github: issue #{number}: body written, but adding label(s) "
                f"{', '.join(additions)} failed — {_unprefixed(exc)}"
            ) from exc
        return task

    def add_labels(self, task: Task, labels: Sequence[str]) -> None:
        if task.external is None:
            raise ProviderError(f"github: cannot label {task.id} — it has no issue reference")
        requested = tuple(label.strip() for label in labels)
        if not requested or any(not label for label in requested):
            raise ProviderError("github: additive labels must be nonblank")
        self.gate.authorize(f"add labels to issue #{task.external.id}", self.name)
        known = {label.casefold(): label for label in self.known_labels() or ()}
        missing = [label for label in requested if label.casefold() not in known]
        if missing:
            raise ProviderError("github: cannot add unknown label(s): " + ", ".join(missing))
        present = {label.casefold() for label in task.labels}
        additions = list(add_unique_labels(
            (), (known[label.casefold()] for label in requested if label.casefold() not in present)
        ))
        if not additions:
            return
        self._add_issue_labels(self._number(task.external), additions)

    def close_task(self, task: Task, resolution: str = "done") -> Task:
        if task.external is None:
            raise ProviderError(f"github: cannot close {task.id} — it has no issue reference")
        self.gate.authorize(f"close issue #{task.external.id}", self.name)
        self._write("PATCH", self._path("issues", self._number(task.external)), {
            "state": "closed",
            "state_reason": "not_planned" if resolution == "cancelled" else "completed",
        })
        return task.with_(status="done" if resolution != "cancelled" else "cancelled")

    def comment(self, task: Task, body: str) -> None:
        if task.external is None:
            raise ProviderError(f"github: cannot comment on {task.id} — no issue reference")
        self.gate.authorize(f"comment on issue #{task.external.id}", self.name)
        self._write("POST", self._path("issues", self._number(task.external), "comments"), {"body": body})

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
    def _to_task(self, issue: Dict, linked_prs: Optional[Dict[str, str]] = None) -> Task:
        labels = tuple(label["name"] for label in issue.get("labels", []))
        state = (issue.get("state") or "open").lower()
        status = self._status_for(state, labels, issue)
        number = str(issue.get("number", ""))
        ref = ExternalRef("github", number, issue.get("html_url", ""))
        self._note_block_state(number, issue.get("body") or "")
        extra = dict(linked_prs or {})
        if issue.get("state_reason"):
            extra["state_reason"] = issue["state_reason"]
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
            created_at=issue.get("created_at"),
            updated_at=issue.get("updated_at"),
            extra=extra,
        )

    def _note_block_state(self, number: str, body: str) -> None:
        note = BLOCK_STATE_NOTES.get(metadata_block_state(body))
        if note:
            self._note(f"issue #{number}: {note}")

    def _linked_pr_state(self, issue: Dict, pr_states: Dict[str, str]) -> Dict[str, str]:
        """What an open issue's closing pull requests say about it, given their states.

        A pull request whose state could not be read counts as open: assuming it
        resolved would re-pick an issue that may still be under review.
        """
        if not self._is_open(issue) or "closedByPullRequestsReferences" not in issue:
            return {}
        references = issue.get("closedByPullRequestsReferences") or []
        states = [pr_states.get(reference.get("id"), "UNKNOWN") for reference in references]
        unresolved = any(state not in ("MERGED", "CLOSED") for state in states)
        extra = {"unresolved_linked_pr": "true" if unresolved else "false"}
        # Open after its closing PR here merged, with nothing else in flight and
        # no human reopening it: the merge fired no closing keyword (#146). A PR
        # in another repository is out of `closes`' reach, so it never counts.
        merged = [
            reference for reference, state in zip(references, states)
            if state == "MERGED" and self._is_this_repo(*self._node_repo(reference))
        ]
        if merged and not unresolved and issue.get("stateReason") != "REOPENED":
            extra["merged_linked_pr"] = f"#{merged[0].get('number')}"
        return extra

    def _read_pr_states(self, issues: Sequence[Dict]) -> Dict[str, str]:
        """The state of every open issue's closing pull requests, by node id."""
        ids = sorted({
            reference["id"]
            for issue in issues
            if self._is_open(issue)
            for reference in issue.get("closedByPullRequestsReferences") or []
            if reference.get("id")
        })
        states: Dict[str, str] = {}
        for start in range(0, len(ids), PR_STATE_BATCH):
            command = ["gh", "api", "graphql", "-f", f"query={PR_STATE_QUERY}"]
            for node_id in ids[start:start + PR_STATE_BATCH]:
                command += ["-f", f"ids[]={node_id}"]
            for node in (self._json(command).get("data") or {}).get("nodes") or []:
                if node and node.get("id"):
                    states[node["id"]] = str(node.get("state") or "")
        return states

    @staticmethod
    def _is_open(issue: Dict) -> bool:
        return (issue.get("state") or "OPEN").upper() == "OPEN"

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
        try:
            return upsert_metadata_block(base, task)
        except TaskModelError as exc:
            raise ProviderError(f"github: issue body for {task.id}: {exc}") from exc

    def _writable_labels(self, task: Task) -> Sequence[str]:
        """Labels we may pass to gh: every existing one, plus mapped ones that exist.

        A mapped label that does not exist in the repository is *reported*, not
        created — creating it would mutate the project's vocabulary during an
        ordinary sync.
        """
        desired = preserve_labels(task.labels, self._mapped_labels(task))
        known = self.known_labels()
        if known is None:
            return tuple(task.labels)
        canonical = {label.casefold(): label for label in known}
        writable = []
        for label in desired:
            if has_label(known, label):
                writable.append(canonical[label.casefold()])
            elif self.config.allow_label_creation and self._create_label(label):
                writable.append(label)
            else:
                self._note(
                    f"label {label!r} does not exist in {self._repo()} and "
                    "allow_label_creation is off — issue written without it"
                )
        return tuple(add_unique_labels((), writable))

    def _create_label(self, label: str) -> bool:
        """Add one label to the repository vocabulary. Only ever reached via config.

        Creation is a mutation of the *project's* vocabulary, so it is gated twice:
        `allow_label_creation` must be on, and the write gate must be open like any
        other external write.
        """
        self.gate.authorize(f"create label {label!r}", self.name)
        try:
            self._write("POST", self._path("labels"), {"name": label})
        except ProviderError as exc:
            self._note(f"could not create label {label!r} — {_unprefixed(exc)}")
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

    def known_labels(self) -> Optional[Sequence[str]]:
        """GitHub can enumerate its vocabulary, so the selector check is real here.

        GitHub always has a label vocabulary, so this never returns None. A listing
        that FAILS raises instead: "gh could not answer" and "this tracker has no
        labels" are different facts, and collapsing them into None let an expired
        token report the same clean exit as a genuine pass.
        """
        if self._known_labels is not None:
            return self._known_labels
        try:
            payload, complete = self._paged("labels", LABEL_LIST_LIMIT)
        except ProviderError as exc:
            self._note(f"could not list labels ({exc}); existing labels preserved, none added")
            raise
        if not complete:
            # Reaching the cap exactly is indistinguishable from "there were more",
            # and a partial vocabulary makes the selector check report labels as
            # missing that exist -- a loud halt on a label the operator can see.
            raise ProviderError(
                f"github: label listing hit its {LABEL_LIST_LIMIT}-label cap, so the "
                "vocabulary is partial and the selector check would be wrong"
            )
        self._known_labels = tuple(entry["name"] for entry in payload)
        return self._known_labels

    def linked_pr_exclusion_available(self) -> Optional[bool]:
        """False once `gh` has proved too old to answer -- see OPTIONAL_ISSUE_FIELDS."""
        return not self._unsupported_fields.intersection(OPTIONAL_ISSUE_FIELDS)

    # ------------------------------------------------------------- gh plumbing
    def _number(self, ref: ExternalRef) -> str:
        """The issue or pull request number as a path segment, or a refusal.

        Every call site puts the number inside a REST path, so a value that is
        not a number has no business reaching `gh` at all: unchecked, a crafted
        reference would become a path segment.
        """
        number = str(ref.id).lstrip("#").strip()
        if not REF_RE.match(number):
            raise ProviderError(
                f"github: {ref.id!r} is not an issue or pull request number — "
                "refusing to pass it to gh"
            )
        return number

    def _is_this_repo(self, owner: str, name: str) -> bool:
        """GitHub owner and repository names are case-insensitive."""
        return f"{owner}/{name}".lower() == self._repo().lower()

    @staticmethod
    def _node_repo(node: Dict) -> Tuple[str, str]:
        """The (owner, name) of the repository an issue or pull request node lives in."""
        repository = node.get("repository") or {}
        return (repository.get("owner") or {}).get("login", ""), repository.get("name", "")

    def _path(self, *parts: str) -> str:
        """A REST path under this repository: `repos/<owner>/<name>/<parts...>`."""
        return "/".join(["repos", self._repo(), *parts])

    def _paged(self, route: str, cap: int, *params: str) -> Tuple[List[Dict], bool]:
        """A REST list read `PAGE_SIZE` at a time, and whether it was complete.

        Paging stops at the first short page or at `cap` entries. Reaching the
        cap exactly is indistinguishable from "there were more", so the caller
        treats an incomplete read as truncation, never as the whole list.
        """
        entries: List[Dict] = []
        for page in range(1, cap // PAGE_SIZE + 1):
            query = "&".join([*params, f"per_page={PAGE_SIZE}", f"page={page}"])
            batch = self._json(["gh", "api", self._path(f"{route}?{query}")])
            entries.extend(batch)
            if len(batch) < PAGE_SIZE:
                return entries, True
        return entries, False

    def _write(self, method: str, path: str, payload: Dict):
        """One REST write. The JSON payload travels on stdin through `--input -`,
        never as `-f` fields: argv is capped near 32K on Windows and issue
        bodies reach 64K, and `labels` is a list."""
        command = ["gh", "api", "--method", method, path, "--input", "-"]
        return self._json(command, input=json.dumps(payload))

    def _add_issue_labels(self, number: str, labels: Sequence[str]) -> None:
        """`POST /issues/{n}/labels` -- additive, the issue's other labels untouched."""
        self._write("POST", self._path("issues", number, "labels"), {"labels": list(labels)})

    def _repo(self) -> str:
        """The `owner/name` every gh call targets, parsed from the remote on demand.

        Provider selection already chose GitHub because the checkout has a remote,
        so a missing `repository =` line is the ordinary case, not a fault. The
        lookup lives here rather than in `discover()` alone so that `select`,
        `claim` and `workflow` — which never run `discover()` — resolve the same
        repository `doctor` reports reachable (#124).
        """
        if self.repository:
            return self.repository
        remote = github_remote(self.config.root)
        if not remote:
            raise ProviderError(
                "github: no repository configured — set `repository = owner/name` in the "
                "task-tracking configuration, or run inside a repo with a GitHub remote"
            )
        self.repository = remote
        return self.repository

    def _run(self, command: Sequence[str], check: bool = True, input: Optional[str] = None):
        try:
            completed = subprocess.run(
                list(command),
                input=input,
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
                f"github: `{_describe(command)}` exited {completed.returncode} — "
                f"{self.redact(output.strip()) or 'no output'}"
            )
        return completed.returncode, output

    def _json(self, command: Sequence[str], input: Optional[str] = None):
        _, output = self._run(command, input=input)
        payload = output[output.find("[") :] if output.lstrip().startswith("[") else output
        try:
            return json.loads(payload.strip() or "[]")
        except json.JSONDecodeError as exc:
            raise ProviderError(
                f"github: could not parse gh JSON output — {exc}; got: "
                f"{self.redact(output.strip()[:200])}"
            ) from exc


def _describe(command: Sequence[str]) -> str:
    """`gh api <METHOD> <path>` for a REST call; the first three words otherwise."""
    words = list(command)
    if words[:2] != ["gh", "api"]:
        return " ".join(words[:3])
    method, path = "GET", ""
    for index, word in enumerate(words[2:], start=2):
        if word in ("--method", "-X") and index + 1 < len(words):
            method = words[index + 1]
        elif not word.startswith("-") and not path and words[index - 1] not in ("--method", "-X", "--input"):
            path = word
    return f"gh api {method} {path}"


def _unprefixed(exc: Exception) -> str:
    """An error's text without its leading `github: `, for nesting in another."""
    text = str(exc)
    return text[len("github: "):] if text.startswith("github: ") else text


def _seed_body(task: Task) -> str:
    """The initial body for a brand-new issue.

    Sections in the order a reader works through them: what is wrong, how to
    see it, what to do, how to know it is done, and what the filer saw. Empty
    sections are omitted rather than rendered as bare headings.
    """
    parts: List[str] = []
    if task.summary:
        parts += [task.summary.strip(), ""]
    parts += section("## Reproduction", [f"{n}. {s}" for n, s in enumerate(task.reproduction, 1)])
    parts += section("## Proposed fix", [f"- {step}" for step in task.proposed_fix])
    parts += section("## Acceptance Criteria", [f"- [ ] {item}" for item in task.acceptance_criteria])
    parts += section("## Evidence", [f"- {item}" for item in task.evidence])
    if task.spec_path:
        parts += [f"Spec: `{task.spec_path}`", ""]
    return "\n".join(parts)
