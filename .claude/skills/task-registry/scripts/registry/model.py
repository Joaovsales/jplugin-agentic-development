"""Provider-neutral task record.

This module knows nothing about GitHub, Jira, or Markdown. Everything a provider
adapter needs in order to round-trip a task without losing information is here:
the canonical vocabulary, the record itself, and the identity block that carries
the stable ID across the boundary.

Identity rule: a provider issue number is an *address*, never an identity. The
stable ID is minted locally and travels inside the task body, so a task survives
being renumbered, migrated between providers, or closed and reopened.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field, replace
from typing import Iterable, Mapping, Optional, Sequence, Tuple

KINDS: Tuple[str, ...] = (
    "epic",
    "feature",
    "bug",
    "decision",
    "research",
    "operational",
    "task",
)

STATUSES: Tuple[str, ...] = ("open", "in_progress", "blocked", "done", "cancelled")

PRIORITIES: Tuple[str, ...] = ("high", "medium", "low")

#: Statuses that mean "no longer on the frontier".
TERMINAL_STATUSES: Tuple[str, ...] = ("done", "cancelled")

DEFAULT_KIND = "task"
DEFAULT_STATUS = "open"

METADATA_BEGIN = "<!-- task-registry:begin -->"
METADATA_END = "<!-- task-registry:end -->"

_ID_RE = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")


class TaskModelError(ValueError):
    """A value does not belong to the canonical vocabulary.

    Raised rather than coerced: silently downgrading an unknown status to `open`
    is the failure mode that makes a registry lie about what is in flight.
    """


def _validate(value: Optional[str], allowed: Sequence[str], field_name: str) -> Optional[str]:
    if value is None:
        return None
    normalized = value.strip().lower().replace("-", "_")
    if normalized not in allowed:
        raise TaskModelError(
            f"unknown {field_name}: {value!r} (canonical values: {', '.join(allowed)})"
        )
    return normalized


def normalize_kind(value: Optional[str]) -> str:
    return _validate(value, KINDS, "kind") or DEFAULT_KIND


def normalize_status(value: Optional[str]) -> str:
    return _validate(value, STATUSES, "status") or DEFAULT_STATUS


def normalize_priority(value: Optional[str]) -> Optional[str]:
    if value is None or str(value).strip() == "":
        return None
    return _validate(value, PRIORITIES, "priority")


def slugify_id(*parts: str) -> str:
    """Mint a stable ID from human text.

    Dotted segments are the hierarchy hint (`recipe.morph-live-grid`); they are
    not parsed as one, they just read well in a flat index.
    """
    cleaned = []
    for part in parts:
        if not part:
            continue
        text = re.sub(r"[^a-zA-Z0-9]+", "-", part.strip().lower()).strip("-")
        if text:
            cleaned.append(text)
    slug = ".".join(cleaned)
    return slug or "task"


def is_valid_id(value: str) -> bool:
    return bool(value) and bool(_ID_RE.match(value))


@dataclass(frozen=True)
class ExternalRef:
    """Where a task lives in a provider. Address, not identity."""

    provider: str
    id: str
    url: str = ""

    def display(self) -> str:
        return f"{self.provider}:{self.id}"


@dataclass(frozen=True)
class Task:
    """One unit of tracked work, normalized across providers.

    Frozen: adapters and the reconciler hand records around freely, and an
    in-place mutation in one of them would silently change what another already
    reported. Use :func:`dataclasses.replace` (re-exported as :meth:`with_`).
    """

    id: str
    title: str
    kind: str = DEFAULT_KIND
    status: str = DEFAULT_STATUS
    priority: Optional[str] = None
    labels: Tuple[str, ...] = ()
    area: Optional[str] = None
    parent: Optional[str] = None
    depends_on: Tuple[str, ...] = ()
    source_path: Optional[str] = None
    spec_path: Optional[str] = None
    external: Optional[ExternalRef] = None
    summary: str = ""
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    acceptance_criteria: Tuple[str, ...] = ()
    evidence: Tuple[str, ...] = ()
    #: Provider payload the normalized model has no field for. Carried so a
    #: round trip through this model is lossless even for fields it never reads.
    extra: Mapping[str, str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.title.strip():
            raise TaskModelError("task title must not be empty")
        object.__setattr__(self, "kind", normalize_kind(self.kind))
        object.__setattr__(self, "status", normalize_status(self.status))
        object.__setattr__(self, "priority", normalize_priority(self.priority))
        object.__setattr__(self, "labels", tuple(self.labels))
        object.__setattr__(self, "depends_on", tuple(self.depends_on))
        object.__setattr__(self, "acceptance_criteria", tuple(self.acceptance_criteria))
        object.__setattr__(self, "evidence", tuple(self.evidence))

    def with_(self, **changes) -> "Task":
        return replace(self, **changes)

    @property
    def is_terminal(self) -> bool:
        return self.status in TERMINAL_STATUSES

    @property
    def is_linked(self) -> bool:
        return self.external is not None


def render_metadata_block(task: Task) -> str:
    """The identity block written into an external task body.

    Only registry-owned facts go here. Everything a human wrote in the body stays
    outside the markers and is never touched.
    """
    lines = [METADATA_BEGIN, "<!-- Managed by /task-registry. Edit the fields, not the markers. -->"]
    lines.append(f"task-id: {task.id}")
    lines.append(f"kind: {task.kind}")
    if task.parent:
        lines.append(f"parent: {task.parent}")
    if task.depends_on:
        lines.append(f"depends-on: {', '.join(task.depends_on)}")
    if task.spec_path:
        lines.append(f"spec: {task.spec_path}")
    if task.source_path:
        lines.append(f"source: {task.source_path}")
    if task.evidence:
        lines.append(f"evidence: {', '.join(task.evidence)}")
    lines.append(METADATA_END)
    return "\n".join(lines)


def parse_metadata_block(body: str) -> dict:
    """Read the identity block back. Returns {} when absent."""
    if not body or METADATA_BEGIN not in body:
        return {}
    after = body.split(METADATA_BEGIN, 1)[1]
    inner = after.split(METADATA_END, 1)[0] if METADATA_END in after else after
    fields: dict = {}
    for line in inner.splitlines():
        line = line.strip()
        if not line or line.startswith("<!--") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip().lower()
        value = value.strip()
        if key in ("depends-on", "evidence"):
            fields[key] = tuple(v.strip() for v in value.split(",") if v.strip())
        elif value:
            fields[key] = value
    return fields


def upsert_metadata_block(body: str, task: Task) -> str:
    """Replace the identity block in-place, or append one, preserving all else.

    Losslessness lives here: the only region of a provider body this whole
    capability ever rewrites is between the two markers.

    A body may contain a *stray* marker — someone quoted the format in prose, or
    an earlier write was interrupted. Splitting naively on the first BEGIN and
    the first END would then span from the stray marker to the real one and
    delete every human line between them, so the pair is located together. A body
    with no pair at all is treated as having no block: appending is recoverable,
    deleting somebody's text is not.
    """
    block = render_metadata_block(task)
    body = body or ""
    bounds = _metadata_bounds(body)
    if bounds is not None:
        start, end = bounds
        return f"{body[:start]}{block}{body[end:]}"
    separator = "\n\n" if body.strip() else ""
    return f"{body.rstrip()}{separator}{block}\n" if body.strip() else f"{block}\n"


def _metadata_bounds(body: str) -> Optional[Tuple[int, int]]:
    """Span of the innermost well-formed BEGIN..END pair, or None if there is none.

    Searching from the last BEGIN backwards is what makes a stray marker harmless:
    the pair chosen is the one with no other BEGIN inside it, which is the block
    this tool actually wrote, and everything before it stays untouched.
    """
    starts = []
    position = body.find(METADATA_BEGIN)
    while position != -1:
        starts.append(position)
        position = body.find(METADATA_BEGIN, position + len(METADATA_BEGIN))
    for start in reversed(starts):
        inner = start + len(METADATA_BEGIN)
        end = body.find(METADATA_END, inner)
        if end != -1 and METADATA_BEGIN not in body[inner:end]:
            return start, end + len(METADATA_END)
    return None


def safe_task(source: str, **fields) -> Tuple[Task, Tuple[str, ...]]:
    """Build a Task, defaulting any value outside the canonical vocabulary.

    A provider record is *foreign data*: a human can type `kind: chore` into an
    issue body, and one such record must not take down every command. But
    silently accepting it would make the vocabulary meaningless, so each rejected
    value is defaulted and *reported* — the caller turns the report into a
    Problem carrying this record's source.

    :func:`Task` itself stays strict (AC-1). Tolerance belongs at the boundary
    where foreign data arrives, not in the model that defines the vocabulary.
    """
    notes: list = []
    for name, allowed, fallback in (
        ("kind", KINDS, DEFAULT_KIND),
        ("status", STATUSES, DEFAULT_STATUS),
        ("priority", PRIORITIES, None),
    ):
        if name not in fields:
            continue
        try:
            _validate(fields[name], allowed, name)
        except TaskModelError as exc:
            notes.append(f"{source}: {exc}; read as {fallback or 'unset'}")
            fields[name] = fallback
    title = (fields.get("title") or "").strip()
    if not title:
        notes.append(f"{source}: task has an empty title; read as its id")
        fields["title"] = fields.get("id") or "(untitled)"
    return Task(**fields), tuple(notes)


def task_from_metadata(
    *,
    title: str,
    body: str,
    external: Optional[ExternalRef],
    status: str,
    labels: Iterable[str] = (),
    fallback_id: Optional[str] = None,
    **overrides,
) -> Task:
    """Build a Task from a provider payload plus its embedded identity block."""
    meta = parse_metadata_block(body)
    task_id = meta.get("task-id") or fallback_id or slugify_id(title)
    summary = overrides.pop("summary", "") or _first_prose_line(body)
    extra = dict(overrides.pop("extra", {}))
    if not meta.get("task-id") and not fallback_id:
        extra["registry_identity"] = "provisional-title-slug"
    return Task(
        id=task_id,
        title=title,
        kind=meta.get("kind", overrides.pop("kind", DEFAULT_KIND)),
        status=status,
        labels=tuple(labels),
        parent=meta.get("parent"),
        depends_on=meta.get("depends-on", ()),
        spec_path=meta.get("spec"),
        source_path=meta.get("source"),
        evidence=meta.get("evidence", ()),
        external=external,
        summary=summary,
        extra=extra,
        **overrides,
    )


def _first_prose_line(body: str) -> str:
    for line in (body or "").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("<!--", "#", "|", "-", "*")):
            continue
        return stripped[:160]
    return ""
