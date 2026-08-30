"""The tracker interface every provider implements.

Narrow on purpose. Ten operations and one capability record is everything the
reconciler is allowed to know about a tracker; anything wider leaks GitHub's or
Jira's shape into the core and makes the next provider a rewrite.

Capability degradation is explicit rather than emulated. A provider that cannot
express a dependency natively says so, the dependency is preserved in the task's
metadata block, and the result is reported as `inferred`. Nothing here ever
presents an inferred link as a native one.
"""

from __future__ import annotations

import abc
from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence

from ..model import ExternalRef, Task


class ProviderError(Exception):
    """A provider operation failed. Always names the provider and the cause."""


class ProviderUnavailable(ProviderError):
    """The provider cannot be reached or is not authenticated."""


class WriteNotAuthorized(ProviderError):
    """A write was attempted without `--apply` (or without configured approval)."""


@dataclass(frozen=True)
class Capabilities:
    """What a provider can do natively. Read by the reconciler, shown to the user."""

    native_hierarchy: bool = False
    native_dependencies: bool = False
    comments: bool = False
    labels: bool = False
    offline: bool = False
    atomic_updates: bool = False

    def missing(self) -> Sequence[str]:
        return tuple(name for name, value in vars(self).items() if not value)

    def render(self) -> str:
        return ", ".join(
            f"{name}={'yes' if value else 'no'}" for name, value in vars(self).items()
        )


@dataclass(frozen=True)
class ProviderStatus:
    """Reachability. `detail` is user-facing and must already be redacted."""

    available: bool
    detail: str


@dataclass(frozen=True)
class LinkResult:
    """Outcome of a hierarchy or dependency link.

    `native` false means the relationship is preserved in the task metadata
    because the provider has no first-class link — a real limitation, surfaced.
    """

    relation: str
    source: str
    target: str
    native: bool
    detail: str = ""

    def render(self) -> str:
        how = "native" if self.native else "inferred (stored in task metadata)"
        return f"{self.relation}: {self.source} -> {self.target} [{how}]"


class WriteGate:
    """The single place that decides whether an external write may happen.

    Dry-run is the default for every command, so the gate is closed unless the
    caller passed `--apply`. A project may additionally require approval; then
    `--apply` alone is not enough and the reason says which knob to flip.
    """

    def __init__(self, apply: bool = False, require_approval: bool = True, approved: bool = False):
        self.apply = apply
        self.require_approval = require_approval
        self.approved = approved

    @property
    def open(self) -> bool:
        if not self.apply:
            return False
        return self.approved or not self.require_approval

    def authorize(self, action: str, provider: str, external: bool = True) -> None:
        """Raise unless this write may proceed.

        `external` false means the write lands inside this repository, where the
        approval requirement has no subject: there is no third-party tracker to
        confirm before touching, and the change is visible in `git diff` like any
        other. `--apply` still gates it.
        """
        if self.apply and not external:
            return
        if self.open:
            return
        if not self.apply:
            raise WriteNotAuthorized(
                f"{provider}: refusing to {action} — dry-run is the default, pass --apply"
            )
        raise WriteNotAuthorized(
            f"{provider}: refusing to {action} — external writes need approval; "
            "re-run with --approve after reviewing what will be sent"
        )


class TrackerProvider(abc.ABC):
    """Provider-facing contract. Implementations hold all tracker specifics."""

    name: str = "abstract"
    capabilities: Capabilities = Capabilities()
    #: URL fragments that identify a task URL belonging to this tracker. Knowing
    #: that `github.com` means GitHub is the provider's knowledge, not the index
    #: parser's — an index that hard-codes it has to be edited for every new
    #: tracker (CLAUDE.md § Open/Closed).
    url_markers: Sequence[str] = ()

    @classmethod
    def owns_url(cls, url: str) -> bool:
        return any(marker in url for marker in cls.url_markers)

    @classmethod
    def reference_label(cls, ref: ExternalRef) -> str:
        """How this tracker's reference is written in prose. `PROJ-7`, `#42`, ..."""
        return ref.id

    def __init__(self, config, gate: Optional[WriteGate] = None) -> None:
        self.config = config
        self.gate = gate or WriteGate()
        #: Degradations encountered this run. Surfaced by the CLI, never swallowed.
        self.limitations: List[str] = []
        #: True when a read came back at its page limit, so more tasks may exist.
        #: A write that assumed it had seen every task would create duplicates of
        #: the ones past the cut, so callers must refuse to publish while set.
        self.result_truncated = False

    def _note(self, detail: str) -> None:
        if detail not in self.limitations:
            self.limitations.append(detail)

    # -- discovery -----------------------------------------------------------
    @abc.abstractmethod
    def discover(self) -> ProviderStatus:
        """Can this provider be used right now, and if not, why not."""

    # -- reads ---------------------------------------------------------------
    @abc.abstractmethod
    def list_tasks(self) -> List[Task]:
        ...

    @abc.abstractmethod
    def get_task(self, ref: ExternalRef) -> Task:
        ...

    @abc.abstractmethod
    def resolve_reference(self, raw: str) -> Optional[ExternalRef]:
        """Turn '#42', 'PROJ-7', or a URL into a reference this provider owns."""

    # -- writes --------------------------------------------------------------
    @abc.abstractmethod
    def create_task(self, task: Task) -> Task:
        ...

    @abc.abstractmethod
    def update_task(self, task: Task) -> Task:
        ...

    @abc.abstractmethod
    def close_task(self, task: Task, resolution: str = "done") -> Task:
        ...

    @abc.abstractmethod
    def comment(self, task: Task, body: str) -> None:
        ...

    @abc.abstractmethod
    def link_parent(self, child: Task, parent: Task) -> LinkResult:
        ...

    @abc.abstractmethod
    def add_dependency(self, task: Task, depends_on: Task) -> LinkResult:
        ...

    # -- shared helpers ------------------------------------------------------
    def describe(self) -> str:
        return f"{self.name} ({self.capabilities.render()})"


def preserve_labels(existing: Iterable[str], additions: Iterable[str] = ()) -> Sequence[str]:
    """Union that keeps original order and never drops an existing label.

    Label vocabulary belongs to the project, not to this tool. Every `area/*`,
    every maintenance label, every label nobody mapped survives a round trip.
    """
    ordered: List[str] = []
    for label in list(existing) + list(additions):
        if label and label not in ordered:
            ordered.append(label)
    return tuple(ordered)
