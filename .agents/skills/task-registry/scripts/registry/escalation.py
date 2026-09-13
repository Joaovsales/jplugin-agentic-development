"""Monotonic investigation escalation for one authoritative parent task."""

from __future__ import annotations

import datetime
import json
import os
import re
import uuid
from dataclasses import dataclass, replace
from typing import Optional, Tuple

from .config import ConfigError, DEFERRED_ROUTINES, confine
from .index import load_index_strict
from .model import METADATA_BEGIN, METADATA_END, Task
from .providers.base import ProviderError, ProviderUnavailable, has_label
from .redaction import redactor_for
from .routines import is_escalated, routine_for_label
from .upsert import UpsertDisposition, UpsertResult, derive_id, upsert_task_result

REASONS = ("inconclusive", "execution-blocked", "verification-blocked")
STATES = ("reproduced", "not-reproduced", "unverified")
BLOCKER_FIELDS = {
    "version", "source", "title", "summary", "handling",
    "reproduction", "proposed_fix", "criteria",
}
FIELD_SHAPE = re.compile(
    r"^(?:-\s*)?(?:status|priority|labels|area|updated|created)\s*:", re.I
)


class EscalationError(ValueError):
    """The request cannot safely enter the escalation write sequence."""


@dataclass(frozen=True)
class EscalationRequest:
    parent_ref: str
    reason: str
    reproduction_state: str
    run_at: str
    repro_command: str
    observed: str
    evidence: Tuple[str, ...]
    evidence_unavailable: Optional[str]
    blocker_file: Optional[str]

    def __post_init__(self) -> None:
        for name in ("parent_ref", "reason", "reproduction_state", "run_at", "repro_command", "observed"):
            if not str(getattr(self, name) or "").strip():
                raise EscalationError(f"{name.replace('_', '-')} must be nonblank")
        _validate_reason_state(self.reason, self.reproduction_state)
        object.__setattr__(self, "run_at", _utc_timestamp(self.run_at))
        evidence = tuple(item.strip() for item in self.evidence if item and item.strip())
        unavailable = (self.evidence_unavailable or "").strip() or None
        if bool(evidence) == bool(unavailable):
            raise EscalationError("pass exactly one of --evidence or --evidence-unavailable")
        object.__setattr__(self, "evidence", evidence)
        object.__setattr__(self, "evidence_unavailable", unavailable)


@dataclass(frozen=True)
class BlockerRequest:
    source: str
    title: str
    summary: str
    handling: str
    reproduction: Tuple[str, ...]
    proposed_fix: Tuple[str, ...]
    criteria: Tuple[str, ...]


def _validate_reason_state(reason: str, state: str) -> None:
    if reason not in REASONS or state not in STATES:
        raise EscalationError(f"invalid reason/reproduction-state: {reason}/{state}")
    allowed = {
        "inconclusive": ("not-reproduced", "unverified"),
        "execution-blocked": ("unverified",),
        "verification-blocked": ("reproduced",),
    }
    if state not in allowed[reason]:
        raise EscalationError(f"{reason} requires reproduction-state {', '.join(allowed[reason])}")


def _utc_timestamp(raw: str) -> str:
    try:
        parsed = datetime.datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise EscalationError("run-at must be a timezone-aware ISO-8601 timestamp") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise EscalationError("run-at must include a timezone offset")
    return parsed.astimezone(datetime.timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_blocker(path: str, root: str) -> BlockerRequest:
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise EscalationError(f"blocker-file: {exc}") from exc
    if not isinstance(payload, dict) or set(payload) != BLOCKER_FIELDS:
        raise EscalationError("blocker-file fields must be exactly: " + ", ".join(sorted(BLOCKER_FIELDS)))
    valid_version = type(payload["version"]) is int and payload["version"] == 1
    if not valid_version or payload["handling"] not in ("routine", "human"):
        raise EscalationError("blocker-file version must be 1 and handling must be routine or human")
    source = _safe_line("source", payload["source"])
    if os.path.isabs(source):
        raise EscalationError("blocker-file source must be repository-relative")
    confine(root, source, "blocker source")
    return BlockerRequest(
        source, _safe_line("title", payload["title"]),
        _safe_line("summary", payload["summary"]), payload["handling"],
        _safe_lines("reproduction", payload["reproduction"]),
        _safe_lines("proposed_fix", payload["proposed_fix"]),
        _safe_lines("criteria", payload["criteria"]),
    )


def _safe_lines(field: str, values) -> Tuple[str, ...]:
    if not isinstance(values, list) or not values:
        raise EscalationError(f"blocker-file {field} must be a nonempty list")
    return tuple(_safe_line(field, value) for value in values)


def _safe_line(field: str, value) -> str:
    if not isinstance(value, str) or not value.strip() or len(value.splitlines()) != 1:
        raise EscalationError(f"blocker-file {field} must contain nonblank single-line strings")
    value = value.strip()
    if METADATA_BEGIN in value or METADATA_END in value or value.startswith("#") or FIELD_SHAPE.match(value):
        raise EscalationError(f"blocker-file {field} contains an unsafe Markdown field shape")
    return value


def escalate_task(registry, request: EscalationRequest, apply: bool) -> Tuple[str, int]:
    blocker, blocker_error = _optional_blocker(request, registry.config.root)
    redact = redactor_for(registry.config)
    blocker_error = redact(blocker_error) if blocker_error else None
    try:
        parent = _authoritative_parent(registry, request.parent_ref)
    except (EscalationError, ProviderError, ProviderUnavailable) as exc:
        lines = [f"parent: refused — {redact(exc)}", "hold: unconfirmed", "blocker: skipped", "comment: skipped"]
        safe_request = replace(request, parent_ref=redact(request.parent_ref))
        return _finish(registry.config.root, safe_request, lines, apply, redact)
    request = replace(request, parent_ref=parent.id)
    if parent.is_terminal:
        lines = [
            f"parent: refused — {request.parent_ref} is {parent.status}",
            "hold: unconfirmed", "blocker: skipped", "comment: skipped",
        ]
        return _finish(registry.config.root, request, lines, apply, redact)
    if not apply:
        state = "failed" if blocker_error else ("preview" if blocker else "none")
        detail = f" — {blocker_error}" if blocker_error else ""
        return "\n".join(("hold: preview", f"blocker: {state}{detail}", "comment: preview")), 0
    return _apply_escalation(registry, parent, request, blocker, blocker_error, redact)


def _authoritative_parent(registry, raw: str) -> Task:
    provider = registry.provider
    status = provider.discover()
    if not status.available:
        raise EscalationError(f"{provider.name} is unavailable: {status.detail}")
    reference = provider.resolve_reference(raw)
    if reference is None:
        index_path = registry.config.path(registry.config.index_path)
        row = load_index_strict(index_path, registry.config.index_path).by_id(raw)
        reference = row.task.external if row else None
    if reference is None:
        matches = [task for task in provider.list_tasks() if task.id == raw]
        if provider.result_truncated or len(matches) != 1:
            raise EscalationError(f"cannot resolve exactly one authoritative parent for {raw!r}")
        reference = matches[0].external
    if reference is None or reference.provider != provider.name:
        raise EscalationError("parent reference belongs to a different provider")
    if reference.url:
        checked = provider.resolve_reference(reference.url)
        if checked is None or checked.id != reference.id:
            raise EscalationError("parent reference belongs to a different repository")
        reference = checked
    parent = provider.get_task(reference)
    if not raw.lstrip("#").isdigit() and "/issues/" not in raw and parent.id != raw:
        raise EscalationError(f"authoritative parent id {parent.id!r} does not match {raw!r}")
    return parent


def _optional_blocker(request, root):
    if not request.blocker_file:
        return None, None
    try:
        return load_blocker(request.blocker_file, root), None
    except (ConfigError, EscalationError, ValueError) as exc:
        return None, str(exc)


def _apply_escalation(registry, parent, request, blocker, blocker_error, redact):
    request = replace(request, parent_ref=parent.id)
    hold_detail = ""
    try:
        registry.provider.add_labels(parent, (registry.config.escalation_label,))
    except Exception as exc:
        hold_detail = redact(exc)
    try:
        readback = registry.provider.get_task(parent.external)
    except Exception as exc:
        readback, hold_detail = parent, "; ".join(
            filter(None, (hold_detail, f"readback failed: {redact(exc)}"))
        )
    hold = _hold_state(readback, registry.config)
    may_file = hold == "confirmed" and not readback.is_terminal
    blocker_result = _file_blocker(registry, readback, request, blocker) if may_file and blocker else None
    blocker_line = redact(
        "blocker: skipped — parent became terminal"
        if readback.is_terminal else _blocker_line(blocker_result, blocker_error, hold)
    )
    lines = [f"hold: {hold}" + (f" — {hold_detail}" if hold_detail else ""), blocker_line]
    body = _comment_body(request, lines, blocker_result)
    try:
        registry.provider.comment(readback, body)
        lines.append("comment: delivered")
    except Exception as exc:
        lines.append(f"comment: unknown — {redact(exc)}")
    return _finish(registry.config.root, request, lines, True, redact, blocker_result)


def _hold_state(task: Task, config) -> str:
    if is_escalated(task.labels, config):
        return "confirmed"
    return "claim-only" if has_label(task.labels, config.claim_label) else "unconfirmed"


def _file_blocker(registry, parent, request, blocker: BlockerRequest) -> UpsertResult:
    parent_ref = parent.external.display() if parent.external else parent.id
    if blocker.handling == "routine":
        labels = tuple(label for label, kind in registry.config.kind_labels.items() if kind == "bug")[:1]
        if not labels or routine_for_label(labels[0], registry.config) in (None, *DEFERRED_ROUTINES):
            return UpsertResult(
                UpsertDisposition.FAILED,
                detail="routine blocker has no runnable bug selector",
                code=1,
            )
        kind = "bug"
    else:
        labels, kind = (registry.config.escalation_label,), "operational"
    evidence = tuple(request.evidence) or (f"evidence unavailable: {request.evidence_unavailable}",)
    task = Task(
        id=derive_id("routine-blocker", blocker.source, blocker.title), title=blocker.title,
        kind=kind, source_path=blocker.source, labels=labels,
        summary=f"{blocker.summary} Originating parent: {parent_ref}.",
        reproduction=blocker.reproduction, proposed_fix=blocker.proposed_fix,
        acceptance_criteria=blocker.criteria,
        evidence=evidence + (f"originating parent: {parent_ref}",),
    )
    return upsert_task_result(registry, task, apply=True)


def _blocker_line(result, error, hold):
    if error:
        return f"blocker: failed — {error}"
    if result is None:
        return "blocker: skipped — hold unconfirmed" if hold != "confirmed" else "blocker: none"
    line = f"blocker: {result.disposition} — {result.reference_summary()}"
    return line + (f"; {result.detail}" if result.detail else "")


def _comment_body(request, stage_lines, blocker_result) -> str:
    payload = {
        "parent_ref": request.parent_ref,
        "reason": request.reason, "reproduction_state": request.reproduction_state,
        "run_at": request.run_at, "repro_command": request.repro_command,
        "observed": request.observed, "evidence": list(request.evidence),
        "evidence_unavailable": request.evidence_unavailable,
        "stages": stage_lines, "blocker_disposition": blocker_result.disposition if blocker_result else None,
    }
    encoded = json.dumps(payload, ensure_ascii=True, indent=2).replace("<", "\\u003c")
    return (
        "Investigation escalated; no verified fix is being claimed. Human re-triage "
        "and explicit hold removal are required. Evidence references are not uploaded "
        "automatically; redact secrets before sharing.\n\n```json\n" + encoded + "\n```"
    )


def _finish(root, request, lines, apply, redact, blocker_result=None):
    if not apply:
        return "\n".join(lines), 0
    try:
        artifact = _write_artifact(root, request, lines, blocker_result)
        lines.append(f"artifact: {artifact}")
    except (ConfigError, OSError) as exc:
        lines.append(f"artifact: failed — {redact(exc)}")
    return "\n".join(lines), 1


def _write_artifact(root, request, lines, blocker_result) -> str:
    directory = confine(root, "tasks/routine-runs", "routine run artifacts")
    os.makedirs(directory, exist_ok=True)
    stamp = request.run_at.replace("-", "").replace(":", "")
    name = f"{stamp}-{uuid.uuid4().hex}.md"
    path = os.path.join(directory, name)
    payload = _comment_body(request, lines, blocker_result)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write("# Routine escalation\n\n" + payload + "\n")
    return os.path.relpath(path, root).replace(os.sep, "/")
