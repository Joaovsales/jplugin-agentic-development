#!/usr/bin/env python3
"""Pure policy engine for issue lane routing.

Perception supplies a complete structured claim. This module validates that
boundary and combines it with the provider-neutral task-registry record; it does
not inspect issue prose or contact a tracker.
"""

from __future__ import annotations

import enum
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass
from typing import Any, Mapping, TypedDict


REGISTRY_SCRIPTS = os.path.realpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "task-registry", "scripts")
)
if REGISTRY_SCRIPTS not in sys.path:
    sys.path.insert(0, REGISTRY_SCRIPTS)

from registry.config import Config, ConfigError, load_config, select_provider  # noqa: E402
from registry.model import KINDS as CLAIM_KINDS, Task, TaskModelError  # noqa: E402
from registry.providers import ProviderError, ProviderUnavailable, build_provider  # noqa: E402
from registry.reconcile import Registry, TaskLookupError  # noqa: E402


class ClaimError(ValueError):
    """The perception claim is incomplete or malformed."""


class RouteRefused(ValueError):
    """Known task state makes starting unsafe."""


class Autonomy(enum.IntEnum):
    GATED_AT_PLAN_AND_PRE_PUSH = 0
    GATED_AT_PLAN = 1
    AUTONOMOUS = 2


AUTONOMY_NAMES = {
    Autonomy.GATED_AT_PLAN_AND_PRE_PUSH: "gated-at-plan-and-pre-push",
    Autonomy.GATED_AT_PLAN: "gated-at-plan",
    Autonomy.AUTONOMOUS: "autonomous",
}


@dataclass(frozen=True)
class RouteRequest:
    claim: Mapping[str, Any]
    task: Task
    channel: str
    config: Config
    project_text: str


@dataclass(frozen=True)
class RouteInvocation:
    claim: Mapping[str, Any]
    task_ref: str
    channel: str
    root: str


@dataclass(frozen=True)
class _DecisionContext:
    channel_grant: Autonomy
    label_grant: Autonomy
    content_ceiling: Autonomy
    downgrades: list[dict[str, str]]
    judges: list[str]


@dataclass(frozen=True)
class _AutonomyPolicy:
    label: str | None
    cap: Autonomy


class RouteDecision(TypedDict):
    lane: str
    prelude: str
    auto_confirm: bool
    autonomy: str
    human_verification: dict[str, Any]
    verification_method: str
    reviewers: list[str]
    ceiling: dict[str, str]
    downgrades: list[dict[str, str]]
    ignored_directives: list[str]
    declared_radius: int
    declared_paths: list[str]
    author_association: str
    task_reference: str
    baseline_revision: str
    baseline_worktree: dict[str, str]
    decision_id: str
    runtime_tripwire: dict[str, Any]
    review_outcomes: dict[str, str]
    unresolved_review_findings: list[str]
    independently_dispatched_reviews: bool


BOOLEAN_FIELDS = (
    "has_acceptance_criteria",
    "acceptance_criteria_machine_checkable",
    "user_facing_behavior",
    "visual_output",
    "security_touching",
    "irreversible_or_outward_facing",
    "docs_only",
)
CLAIM_FIELDS = (
    "kind",
    "has_acceptance_criteria",
    "acceptance_criteria_machine_checkable",
    "blast_radius_subsystems",
    "declared_paths",
    "user_facing_behavior",
    "visual_output",
    "security_touching",
    "irreversible_or_outward_facing",
    "docs_only",
    "blocking_question",
    "lane_selecting_imperatives",
)


def _require_string_list(claim: Mapping[str, Any], field: str) -> None:
    value = claim[field]
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ClaimError(f"{field} must be a list of strings")


def validate_claim(claim: Mapping[str, Any]) -> None:
    if not isinstance(claim, Mapping):
        raise ClaimError("claim must be an object")
    for field in CLAIM_FIELDS:
        if field not in claim:
            raise ClaimError(f"missing required field: {field}")
    if not isinstance(claim["kind"], str) or claim["kind"] not in CLAIM_KINDS:
        raise ClaimError("kind must be a canonical task kind")
    for field in BOOLEAN_FIELDS:
        if type(claim[field]) is not bool:
            raise ClaimError(f"{field} must be boolean")
    radius = claim["blast_radius_subsystems"]
    if type(radius) is not int or radius < 0:
        raise ClaimError("blast_radius_subsystems must be a non-negative integer")
    _require_string_list(claim, "declared_paths")
    _require_string_list(claim, "lane_selecting_imperatives")
    question = claim["blocking_question"]
    if question is not None and not isinstance(question, str):
        raise ClaimError("blocking_question must be a string or null")


def _autonomy_label(config: Config) -> str | None:
    label = getattr(config, "autonomy_label", None)
    if label is not None and not isinstance(label, str):
        raise ValueError("task-registry autonomy_label must be a string or null")
    label = label.strip() if label else ""
    return label or None


def _trusted_grants(
    task: Task, channel: str, policy: _AutonomyPolicy
) -> tuple[Autonomy, Autonomy]:
    if channel not in ("interactive", "scheduled"):
        raise ValueError("channel must be interactive or scheduled")
    channel_grant = (
        Autonomy.AUTONOMOUS if channel == "scheduled" else Autonomy.GATED_AT_PLAN
    )
    label = policy.label
    label_grant = (
        Autonomy.AUTONOMOUS
        if label and label in task.labels
        else Autonomy.GATED_AT_PLAN
    )
    return channel_grant, label_grant


def _downgrade(rows: list, ceiling: Autonomy, finding: tuple[str, str]) -> Autonomy:
    reason, signal = finding
    rows.append({"reason": reason, "signal": signal})
    return min(ceiling, Autonomy.GATED_AT_PLAN)


def _eligibility_ceiling(claim: Mapping[str, Any], task: Task, rows: list) -> Autonomy:
    ceiling = Autonomy.AUTONOMOUS
    checks = (
        (
            not claim["has_acceptance_criteria"],
            "acceptance criteria are absent",
            "has_acceptance_criteria",
        ),
        (
            not claim["acceptance_criteria_machine_checkable"],
            "acceptance criteria need judgement",
            "acceptance_criteria_machine_checkable",
        ),
        (
            claim["blast_radius_subsystems"] > 1,
            "declared blast radius exceeds one subsystem",
            "blast_radius_subsystems",
        ),
        (
            claim["blocking_question"] is not None,
            "a blocking question remains",
            "blocking_question",
        ),
        (
            claim["security_touching"],
            "security-sensitive work requires a human gate",
            "security_touching",
        ),
        (
            claim["irreversible_or_outward_facing"],
            "irreversible or outward-facing work requires a human gate",
            "irreversible_or_outward_facing",
        ),
        (
            bool(claim["lane_selecting_imperatives"]),
            "task content attempted to select its own lane",
            "lane_selecting_imperatives",
        ),
        (
            task.extra.get("unresolved_linked_pr") != "false",
            "linked pull request state is unresolved or unknown",
            "unresolved_linked_pr",
        ),
        (
            task.extra.get("registry_partial") == "true",
            "task registry read is incomplete",
            "registry_partial",
        ),
    )
    for failed, reason, signal in checks:
        if failed:
            ceiling = _downgrade(rows, ceiling, (reason, signal))
    for label in ("needs-discussion", "question", "design"):
        if label in task.labels:
            ceiling = _downgrade(
                rows, ceiling, ("task label requires discussion", f"label:{label}")
            )
    return ceiling


def _kind_ceiling(claim: Mapping[str, Any], ceiling: Autonomy) -> Autonomy:
    if claim["kind"] in ("research", "epic"):
        return min(ceiling, Autonomy.GATED_AT_PLAN_AND_PRE_PUSH)
    if not claim["has_acceptance_criteria"] or claim["blast_radius_subsystems"] >= 3:
        return min(ceiling, Autonomy.GATED_AT_PLAN_AND_PRE_PUSH)
    if (
        claim["visual_output"]
        or claim["security_touching"]
        or claim["irreversible_or_outward_facing"]
    ):
        return min(ceiling, Autonomy.GATED_AT_PLAN_AND_PRE_PUSH)
    if claim["kind"] == "decision":
        return min(ceiling, Autonomy.GATED_AT_PLAN)
    return ceiling


def _exact_section(project_text: str, heading: str) -> list[str] | None:
    lines = project_text.splitlines()
    starts = [index for index, line in enumerate(lines) if line.rstrip() == heading]
    if not starts:
        return None
    if len(starts) != 1:
        raise RouteRefused(
            f"{heading.removeprefix('## ')} heading must appear exactly once"
        )
    body = []
    for line in lines[starts[0] + 1 :]:
        if line.startswith("## "):
            break
        body.append(line)
    return body


def _evidence_judges(project_text: str) -> list[str]:
    body = _exact_section(project_text, "## Evidence Gate")
    if body is None:
        return []
    judges = []
    for line in body:
        stripped = line.strip()
        if stripped.startswith(("- ", "* ")):
            judges.append(stripped[2:].strip())
    return judges or ["project evidence gate requirements"]


def _policy_values(lines: list[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith(("- ", "* ")) or ":" not in stripped:
            raise RouteRefused(
                "Autonomy Policy entries must be '- autonomy_label: ...' or '- autonomy_cap: ...'"
            )
        key, value = (part.strip() for part in stripped[2:].split(":", 1))
        if key not in ("autonomy_label", "autonomy_cap") or not value or key in values:
            raise RouteRefused(f"invalid Autonomy Policy entry: {stripped}")
        values[key] = value
    if not values:
        raise RouteRefused("Autonomy Policy heading has no policy entries")
    return values


def _autonomy_policy(project_text: str, config: Config) -> _AutonomyPolicy:
    body = _exact_section(project_text, "## Autonomy Policy")
    if body is None:
        return _AutonomyPolicy(_autonomy_label(config), Autonomy.AUTONOMOUS)
    values = _policy_values(body)
    raw_label = values.get("autonomy_label")
    label = (
        _autonomy_label(config)
        if raw_label is None
        else (None if raw_label == "none" else raw_label)
    )
    cap_name = values.get("autonomy_cap", "autonomous")
    caps = {name: autonomy for autonomy, name in AUTONOMY_NAMES.items()}
    if cap_name not in caps:
        raise RouteRefused(f"invalid Autonomy Policy autonomy_cap: {cap_name}")
    return _AutonomyPolicy(label, caps[cap_name])


def _verification(claim: Mapping[str, Any], evidence_gate: bool) -> str:
    if evidence_gate:
        return "project-evidence-gate"
    if claim["docs_only"]:
        return "link-check"
    if claim["user_facing_behavior"]:
        return "e2e"
    if claim["kind"] == "research":
        return "measurement"
    if claim["kind"] == "operational":
        return "deployment"
    return "tests"


def _reviewers(claim: Mapping[str, Any], autonomy: Autonomy) -> list[str]:
    reviewers = {"code-reviewer"}
    if autonomy == Autonomy.AUTONOMOUS or claim["kind"] in (
        "decision",
        "research",
        "epic",
    ):
        reviewers.add("critic")
    if (
        claim["kind"] == "epic"
        or claim["blast_radius_subsystems"] >= 3
        or not claim["has_acceptance_criteria"]
    ):
        reviewers.add("software-design-expert-review")
    if claim["security_touching"] or claim["irreversible_or_outward_facing"]:
        reviewers.add("security-reviewer")
    return sorted(reviewers)


def _refuse_if_blocked(task: Task) -> None:
    if task.extra.get("registry_identity") == "provisional-title-slug":
        raise RouteRefused(
            f"task {task.id} has no stable registry identity; register it or run /task-registry migrate"
        )
    if task.status == "blocked":
        raise RouteRefused(f"task {task.id} is blocked")
    unknown = task.extra.get("unknown_dependencies", "").strip()
    if unknown:
        raise RouteRefused(f"task {task.id} has unknown dependency: {unknown}")
    blocking = task.extra.get("blocking_dependencies", "").strip()
    if blocking:
        raise RouteRefused(f"task {task.id} waits on open dependency: {blocking}")


def _decision_context(request: RouteRequest) -> _DecisionContext:
    downgrades: list[dict[str, str]] = []
    policy = _autonomy_policy(request.project_text, request.config)
    grants = _trusted_grants(request.task, request.channel, policy)
    content = _eligibility_ceiling(request.claim, request.task, downgrades)
    content = _kind_ceiling(request.claim, content)
    if policy.cap < content:
        content = policy.cap
        downgrades.append(
            {
                "reason": "project autonomy policy caps execution",
                "signal": "project-autonomy-cap",
            }
        )
    judges = _evidence_judges(request.project_text)
    if judges:
        content = min(content, Autonomy.GATED_AT_PLAN_AND_PRE_PUSH)
        downgrades.append(
            {
                "reason": "project evidence requires human judgement",
                "signal": "project-evidence-gate",
            }
        )
    return _DecisionContext(*grants, content, downgrades, judges)


def _workflow_fields(
    request: RouteRequest,
    context: _DecisionContext,
    autonomy: Autonomy,
) -> dict[str, Any]:
    claim, task, judges = request.claim, request.task, context.judges
    return {
        "lane": AUTONOMY_NAMES[autonomy],
        "prelude": _prelude(claim),
        "auto_confirm": autonomy == Autonomy.AUTONOMOUS
        and claim["kind"] != "decision"
        and claim["blocking_question"] is None,
        "autonomy": AUTONOMY_NAMES[autonomy],
        "human_verification": {
            "needed": bool(judges or claim["visual_output"]),
            "judges": judges or (["visual output"] if claim["visual_output"] else []),
        },
        "verification_method": _verification(claim, bool(judges)),
        "reviewers": _reviewers(claim, autonomy),
        "ceiling": {
            "channel_grant": AUTONOMY_NAMES[context.channel_grant],
            "label_grant": AUTONOMY_NAMES[context.label_grant],
            "content_ceiling": AUTONOMY_NAMES[context.content_ceiling],
        },
        "downgrades": context.downgrades,
        "ignored_directives": list(claim["lane_selecting_imperatives"]),
        "declared_radius": claim["blast_radius_subsystems"],
        "declared_paths": list(claim["declared_paths"]),
        "author_association": _author_association(task),
        "task_reference": "",
    }


def _initial_runtime_fields() -> dict[str, Any]:
    return {
        "baseline_revision": "",
        "baseline_worktree": {},
        "decision_id": "",
        "runtime_tripwire": {"status": "pending"},
        "review_outcomes": {},
        "unresolved_review_findings": [],
        "independently_dispatched_reviews": False,
    }


def _render_decision(request: RouteRequest, context: _DecisionContext) -> RouteDecision:
    autonomy = min(context.channel_grant, context.label_grant, context.content_ceiling)
    return {**_workflow_fields(request, context, autonomy), **_initial_runtime_fields()}  # type: ignore[return-value]


def _prelude(claim: Mapping[str, Any]) -> str:
    kind = claim["kind"]
    if kind == "bug":
        return "/debug"
    needs_brainstorm = kind in ("decision", "research", "epic")
    needs_brainstorm = needs_brainstorm or claim["blast_radius_subsystems"] >= 3
    needs_brainstorm = needs_brainstorm or not claim["has_acceptance_criteria"]
    return "/brainstorm" if needs_brainstorm else "skip: not needed for this kind"


def _author_association(task: Task) -> str:
    if task.extra.get("author_association"):
        return task.extra["author_association"]
    return (
        "in-repo"
        if task.external is None or task.external.provider == "local"
        else "unknown"
    )


def decide_route(request: RouteRequest) -> RouteDecision:
    validate_claim(request.claim)
    if request.claim["kind"] != request.task.kind:
        raise ClaimError(
            f"claim kind disagrees with structured task kind: {request.claim['kind']} != {request.task.kind}"
        )
    _refuse_if_blocked(request.task)
    return _render_decision(request, _decision_context(request))


def _read_optional(path: str) -> str:
    if not os.path.isfile(path):
        return ""
    with open(path, "r", encoding="utf-8-sig") as handle:
        return handle.read()


def _atomic_write(path: str, content: str) -> None:
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=parent, delete=False
        ) as handle:
            temporary = handle.name
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except OSError:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
        raise


def _render_playbook(decision: RouteDecision) -> str:
    playbook = os.path.join(
        os.path.dirname(__file__), "..", "playbooks", f"{decision['lane']}.md"
    )
    rendered = _read_optional(os.path.realpath(playbook))
    if not rendered:
        raise RouteRefused(f"missing lane playbook: {decision['lane']}")
    rendered = rendered.replace("<skill | skip: reason>", decision["prelude"])
    method = decision["verification_method"]
    verification_step = (
        f"/verify --scope {method}"
        if method in ("e2e", "deployment")
        else f"/verify (evidence: {method})"
    )
    rendered = rendered.replace("<verification_step>", verification_step)
    return rendered.replace("<reviewers>", ", ".join(decision["reviewers"]))


def _merge_lane(existing: str, decision: RouteDecision, playbook: str) -> str:
    begin, end = "<!-- route-lane:begin -->", "<!-- route-lane:end -->"
    block = (
        f"{begin}\n## Routed lane — {decision['lane']}\n\n{playbook.rstrip()}\n{end}"
    )
    marker_counts = (existing.count(begin), existing.count(end))
    if marker_counts not in ((0, 0), (1, 1)):
        raise RouteRefused("malformed managed route lane block")
    if begin in existing and end in existing:
        prefix, remainder = existing.split(begin, 1)
        _, suffix = remainder.split(end, 1)
        return f"{prefix.rstrip()}\n\n{block}{suffix}"
    prefix = f"{existing.rstrip()}\n\n" if existing.strip() else ""
    return f"{prefix}{block}\n"


def _registry_task(root: str, task_ref: str) -> tuple[Config, Task]:
    config = load_config(root)
    selection = select_provider(config)
    provider = build_provider(selection.provider, config)
    registry = Registry(config, provider, selection_reason=selection.reason)
    return config, registry.resolve_task(task_ref)


def _decision_record(decision: RouteDecision) -> str:
    return f"# Route Decision\n\n```json\n{json.dumps(decision, indent=2, sort_keys=True)}\n```\n"


def _git_head(root: str) -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=10,
    )
    head = completed.stdout.strip()
    if completed.returncode != 0 or not head:
        detail = completed.stderr.strip() or "repository has no commit"
        raise RouteRefused(f"cannot record mandatory Git baseline: {detail}")
    return head


ROUTE_CONTROL_PATHS = {
    "tasks/todo.md",
    "tasks/route-decision.md",
    "tasks/.route-transaction.json",
}


def _git_paths(root: str, baseline: str) -> set[str]:
    commands = (
        ["git", "diff", "--name-only", baseline, "--"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    )
    paths: set[str] = set()
    for command in commands:
        completed = subprocess.run(
            command,
            cwd=root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        if completed.returncode != 0:
            raise RouteRefused(
                f"cannot inspect route diff: {completed.stderr.strip() or 'no output'}"
            )
        paths.update(completed.stdout.splitlines())
    return {path for path in paths if path and path not in ROUTE_CONTROL_PATHS}


def _fingerprint(root: str, path: str) -> str:
    absolute = os.path.join(root, path)
    try:
        metadata = os.lstat(absolute)
    except FileNotFoundError:
        return "<missing>"
    mode = stat.S_IMODE(metadata.st_mode)
    if stat.S_ISLNK(metadata.st_mode):
        return f"symlink:{mode:o}:{os.readlink(absolute)}"
    if not stat.S_ISREG(metadata.st_mode):
        raise RouteRefused(f"unsupported changed filesystem object: {path}")
    digest = hashlib.sha256()
    descriptor = os.open(absolute, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return f"file:{mode:o}:{digest.hexdigest()}"


def _worktree_snapshot(root: str, baseline: str) -> dict[str, str]:
    return {path: _fingerprint(root, path) for path in _git_paths(root, baseline)}


def _transaction_path(root: str) -> str:
    return os.path.join(root, "tasks", ".route-transaction.json")


def _canonical_state_path(root: str) -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "--git-path", "codex-route-state.json"],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=10,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise RouteRefused("cannot locate canonical route state in Git metadata")
    path = completed.stdout.strip()
    return path if os.path.isabs(path) else os.path.join(root, path)


def _write_route_state(root: str, decision: RouteDecision, todo: str) -> None:
    transaction = {"decision": _decision_record(decision), "todo": todo}
    transaction_path = _transaction_path(root)
    _atomic_write(transaction_path, json.dumps(transaction, sort_keys=True))
    _atomic_write(_canonical_state_path(root), transaction["decision"])
    _atomic_write(
        os.path.join(root, "tasks", "route-decision.md"), transaction["decision"]
    )
    _atomic_write(os.path.join(root, "tasks", "todo.md"), todo)
    os.unlink(transaction_path)


def _recover_route_state(root: str) -> None:
    transaction_path = _transaction_path(root)
    if not os.path.isfile(transaction_path):
        return
    payload = json.loads(_read_optional(transaction_path))
    if not isinstance(payload, dict) or not all(
        isinstance(payload.get(key), str) for key in ("decision", "todo")
    ):
        raise RouteRefused("malformed pending route transaction")
    _atomic_write(_canonical_state_path(root), payload["decision"])
    _atomic_write(os.path.join(root, "tasks", "route-decision.md"), payload["decision"])
    _atomic_write(os.path.join(root, "tasks", "todo.md"), payload["todo"])
    os.unlink(transaction_path)


def materialize_route(invocation: RouteInvocation) -> RouteDecision:
    _recover_route_state(invocation.root)
    project_path = os.path.join(invocation.root, ".claude", "project.md")
    config, task = _registry_task(invocation.root, invocation.task_ref)
    request = RouteRequest(
        invocation.claim, task, invocation.channel, config, _read_optional(project_path)
    )
    decision = decide_route(request)
    decision["baseline_revision"] = _git_head(invocation.root)
    decision["baseline_worktree"] = _worktree_snapshot(
        invocation.root, decision["baseline_revision"]
    )
    decision["decision_id"] = uuid.uuid4().hex
    decision["task_reference"] = invocation.task_ref
    playbook = _render_playbook(decision)
    todo_path = os.path.join(invocation.root, "tasks", "todo.md")
    todo = _merge_lane(_read_optional(todo_path), decision, playbook)
    _write_route_state(invocation.root, decision, todo)
    return decision


def _inside(path: str, prefix: str) -> bool:
    normalized = prefix.rstrip("/")
    return path == normalized or path.startswith(normalized + "/")


def check_actual_diff(
    decision: RouteDecision, changed_paths: list[str]
) -> dict[str, Any]:
    declared = decision["declared_paths"]
    outside = [
        path
        for path in changed_paths
        if not any(_inside(path, prefix) for prefix in declared)
    ]
    subsystem_roots = {
        "/".join(path.strip("/").split("/")[:2]) for path in changed_paths
    }
    actual_radius = len(subsystem_roots)
    return {
        "overflow": bool(outside) or actual_radius > decision["declared_radius"],
        "actual_radius": actual_radius,
        "changed_paths": sorted(changed_paths),
        "outside_declared_paths": outside,
    }


def _changed_paths_since(root: str, decision: RouteDecision) -> list[str]:
    baseline = decision["baseline_revision"]
    if not baseline:
        raise RouteRefused("route decision has no recorded git baseline")
    before = decision.get("baseline_worktree", {})
    after = _worktree_snapshot(root, baseline)
    return sorted(
        path for path in set(before) | set(after) if before.get(path) != after.get(path)
    )


def _demote(decision: RouteDecision, reason: str, signal: str) -> RouteDecision:
    finalized = dict(decision)
    finalized["lane"] = "gated-at-plan-and-pre-push"
    finalized["autonomy"] = "gated-at-plan-and-pre-push"
    finalized["auto_confirm"] = False
    finalized["downgrades"] = [
        *decision["downgrades"],
        {"reason": reason, "signal": signal},
    ]
    return finalized  # type: ignore[return-value]


def _persist_finalized(
    root: str, decision: RouteDecision, rewrite_lane: bool
) -> RouteDecision:
    todo_path = os.path.join(root, "tasks", "todo.md")
    todo = _read_optional(todo_path)
    if rewrite_lane:
        todo = _merge_lane(todo, decision, _render_playbook(decision))
    _write_route_state(root, decision, todo)
    return decision


def _finalize_route(
    root: str, decision: RouteDecision, changed_paths: list[str]
) -> RouteDecision:
    tripwire = check_actual_diff(decision, changed_paths)
    finalized = dict(decision)
    finalized["runtime_tripwire"] = {
        "status": "failed" if tripwire["overflow"] else "passed",
        **tripwire,
    }
    if tripwire["overflow"]:
        finalized = _demote(
            finalized, "actual diff exceeded the declared scope", "runtime_tripwire"
        )
    return _persist_finalized(root, finalized, tripwire["overflow"])  # type: ignore[arg-type]


def finalize_route(root: str, decision: RouteDecision) -> RouteDecision:
    current = _current_decision(root, decision)
    return _finalize_route(root, current, _changed_paths_since(root, current))


def _current_decision(root: str, supplied: RouteDecision) -> RouteDecision:
    _recover_route_state(root)
    text = _read_optional(_canonical_state_path(root))
    if not text:
        raise RouteRefused(
            "canonical route state is absent; run materialize_route first"
        )
    try:
        payload = json.loads(text.split("```json\n", 1)[1].rsplit("\n```", 1)[0])
    except (IndexError, json.JSONDecodeError) as exc:
        raise RouteRefused("persisted route decision is malformed") from exc
    if (
        supplied.get("decision_id")
        and payload.get("decision_id") != supplied["decision_id"]
    ):
        raise RouteRefused("stale route decision identity")
    return payload  # type: ignore[return-value]


def _review_demotion(
    outcomes: Mapping[str, str],
    unresolved: list[str],
    independent: bool,
    tripwire_passed: bool,
) -> tuple[str, str] | None:
    if not tripwire_passed:
        return (
            "runtime tripwire did not pass before reviewer finalization",
            "runtime-tripwire",
        )
    if any(status != "completed" for status in outcomes.values()):
        return "reviewer did not complete", "reviewer-outcome"
    if unresolved:
        return "review findings remain unresolved", "unresolved-review-findings"
    if not independent:
        return "reviews were not independently dispatched", "review-independence"
    return None


def _validate_review_state(
    decision: RouteDecision,
    review: Mapping[str, Any],
) -> tuple[Mapping[str, str], list[str], bool]:
    outcomes = review.get("outcomes")
    unresolved = review.get("unresolved_findings")
    independent = review.get("independently_dispatched")
    if (
        not isinstance(outcomes, Mapping)
        or not isinstance(unresolved, list)
        or any(not isinstance(item, str) for item in unresolved)
        or type(independent) is not bool
    ):
        raise RouteRefused(
            "review state requires outcomes, unresolved_findings, and independently_dispatched"
        )
    if set(outcomes) != set(decision["reviewers"]):
        raise RouteRefused(
            "reviewer outcomes must name exactly the dispatched reviewers"
        )
    invalid = {
        status
        for status in outcomes.values()
        if status not in ("completed", "hung", "failed")
    }
    if invalid:
        raise RouteRefused(f"invalid reviewer outcome: {', '.join(sorted(invalid))}")
    return outcomes, unresolved, independent


def finalize_reviewers(
    root: str,
    decision: RouteDecision,
    review: Mapping[str, Any],
) -> RouteDecision:
    decision = _current_decision(root, decision)
    outcomes, unresolved, independent = _validate_review_state(decision, review)
    finalized = dict(decision)
    finalized["review_outcomes"] = dict(outcomes)
    finalized["unresolved_review_findings"] = list(unresolved)
    finalized["independently_dispatched_reviews"] = independent
    demotion = _review_demotion(
        outcomes,
        unresolved,
        independent,
        decision["runtime_tripwire"].get("status") == "passed",
    )
    if demotion:
        finalized = _demote(finalized, *demotion)
    return _persist_finalized(root, finalized, demotion is not None)  # type: ignore[arg-type]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        invocation = RouteInvocation(
            payload["claim"], payload["task_ref"], payload["channel"], payload["root"]
        )
        json.dump(materialize_route(invocation), sys.stdout, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except (
        ClaimError,
        RouteRefused,
        ConfigError,
        ProviderError,
        ProviderUnavailable,
        TaskLookupError,
        TaskModelError,
        KeyError,
        TypeError,
        ValueError,
        OSError,
        json.JSONDecodeError,
    ) as exc:
        print(f"route_issue: {exc}", file=sys.stderr)
        return 2


__all__ = [
    "Autonomy",
    "CLAIM_KINDS",
    "ClaimError",
    "Config",
    "RouteDecision",
    "RouteInvocation",
    "RouteRefused",
    "RouteRequest",
    "Task",
    "check_actual_diff",
    "decide_route",
    "finalize_reviewers",
    "finalize_route",
    "load_config",
    "materialize_route",
    "validate_claim",
]


if __name__ == "__main__":
    raise SystemExit(main())
