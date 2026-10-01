"""Validate and resolve semantic agent routes without reading installed config."""

from __future__ import annotations

from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:
    raise SystemExit("agent-policy: Python 3.11 or newer is required") from exc


DEFAULT_POLICY = Path(__file__).resolve().parents[2] / "config/agent-policy.toml"
TIERS = {"Scout", "Builder", "Reviewer", "Planner", "Ceiling"}
PERMISSIONS = {"read-only", "mcp-read", "workspace-write"}
WORKFLOW_ROLES = {
    "backend-developer", "code-debugger", "code-reviewer", "context-document-optimizer",
    "critic", "frontend-design-validator", "frontend-developer", "planner",
    "security-reviewer", "software-design-expert-review", "explorer", "scout",
}


class PolicyError(ValueError):
    """A policy or requested route cannot be resolved safely."""


def _named_entries(entries: object, kind: str) -> dict[str, dict]:
    if not isinstance(entries, list):
        raise PolicyError(f"{kind} must be a list")
    named: dict[str, dict] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            raise PolicyError(f"{kind} entry needs a name")
        name = entry["name"]
        if not name or name in named:
            raise PolicyError(f"duplicate or empty {kind} name: {name!r}")
        named[name] = entry
    return named


def _validate_mapped_tier(name: str, config: dict, models: dict) -> None:
    model, effort = config.get("model"), config.get("effort")
    if not isinstance(model, str) or not isinstance(models.get(model), dict):
        raise PolicyError(f"unsupported model {model!r} for tier {name}")
    supported = models[model].get("efforts")
    if not isinstance(supported, list):
        raise PolicyError(f"model {model}: efforts must be a list")
    if effort not in supported:
        raise PolicyError(f"unsupported effort {effort!r} for tier {name} model {model!r}")
    if type(models[model].get("rank")) is not int:
        raise PolicyError(f"missing model rank: {model}")


def _validate_tiers(policy: dict) -> None:
    tiers = policy.get("tiers")
    providers = policy.get("providers")
    if not isinstance(providers, dict) or not isinstance(providers.get("codex"), dict):
        raise PolicyError("providers.codex must be a table")
    models = providers["codex"].get("models")
    if not isinstance(tiers, dict) or not isinstance(models, dict):
        raise PolicyError("tiers and providers.codex.models must be tables")
    for name, config in tiers.items():
        if name not in TIERS or not isinstance(config, dict):
            raise PolicyError(f"unknown tier: {name}")
        if name == "Ceiling":
            if config != {"inherit_model": True}:
                raise PolicyError("Ceiling must inherit its model without a fixed mapping")
            continue
        _validate_mapped_tier(name, config, models)


def _validate_role(name: str, route: dict, policy: dict) -> None:
    if route.get("tier") not in policy["tiers"]:
        raise PolicyError(f"role {name}: unknown tier {route.get('tier')!r}")
    if route.get("permission") not in PERMISSIONS:
        raise PolicyError(f"role {name}: unsupported permission {route.get('permission')!r}")
    if route.get("floor") and route["tier"] != "Ceiling":
        raise PolicyError(f"role {name}: floor requires Ceiling tier")
    if route.get("floor") and route["floor"] not in set(policy["tiers"]) - {"Ceiling"}:
        raise PolicyError(f"role {name}: unknown floor {route['floor']!r}")


def _validate_escalation(name: str, lane: dict, policy: dict) -> None:
    threshold, target = lane.get("escalate_at_or_below"), lane.get("escalate_to")
    if not (threshold or target):
        return
    if lane.get("tier") != "Ceiling" or threshold not in policy["tiers"] or target not in policy["tiers"]:
        raise PolicyError(f"lane {name}: invalid escalation tiers")
    if "Ceiling" in {threshold, target}:
        raise PolicyError(f"lane {name}: escalation tiers must be mapped")
    models = policy["providers"]["codex"]["models"]
    lower = policy["tiers"][threshold]["model"]
    higher = policy["tiers"][target]["model"]
    if models[higher]["rank"] <= models[lower]["rank"]:
        raise PolicyError(f"lane {name}: escalation must raise model rank")


def _validate_lane(name: str, lane: dict, roles: dict, policy: dict) -> None:
    if lane.get("role") not in roles:
        raise PolicyError(f"lane {name}: unknown role {lane.get('role')!r}")
    if lane.get("tier", roles[lane["role"]]["tier"]) not in policy["tiers"]:
        raise PolicyError(f"lane {name}: unknown tier")
    if "floor" in lane:
        if lane["floor"] not in set(policy["tiers"]) - {"Ceiling"}:
            raise PolicyError(f"lane {name}: unknown floor {lane['floor']!r}")
        if lane.get("tier") != "Ceiling":
            raise PolicyError(f"lane {name}: floor requires Ceiling tier")
    _validate_escalation(name, lane, policy)


def _validate_routes(policy: dict) -> None:
    roles = _named_entries(policy.get("roles"), "role")
    lanes = _named_entries(policy.get("lanes"), "lane")
    missing = WORKFLOW_ROLES - roles.keys()
    if missing:
        raise PolicyError(f"missing workflow roles: {', '.join(sorted(missing))}")
    for name, route in roles.items():
        _validate_role(name, route, policy)
    for name, lane in lanes.items():
        _validate_lane(name, lane, roles, policy)


def _validate_limits(policy: dict) -> None:
    limits = policy.get("limits")
    codex = limits.get("codex") if isinstance(limits, dict) else None
    cap = codex.get("max_children") if isinstance(codex, dict) else None
    if type(cap) is not int or cap <= 0:
        raise PolicyError("limits.codex.max_children must be a positive integer")


def load_policy(path: Path = DEFAULT_POLICY) -> dict:
    """Read one policy, refusing unknown schema and duplicate route declarations."""
    try:
        with Path(path).open("rb") as stream:
            policy = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise PolicyError(f"cannot read policy {path}: {exc}") from exc
    if policy.get("schema_version") != 1:
        raise PolicyError(f"unsupported schema version: {policy.get('schema_version')!r}")
    _validate_tiers(policy)
    _validate_limits(policy)
    _validate_routes(policy)
    return policy


def _effective_model(policy: dict, tier: str, floor: str | None, parent_model: str | None) -> tuple:
    if tier != "Ceiling":
        mapped = policy["tiers"][tier]
        return mapped["model"], mapped["effort"], False, f"{tier} uses its Codex mapping"
    models = policy["providers"]["codex"]["models"]
    if parent_model not in models:
        return None, None, True, "parent model unknown; inheritance and floor unresolved"
    if not floor:
        return parent_model, None, True, "Ceiling inherits the parent model and effort"
    floor_model = policy["tiers"][floor]["model"]
    parent_rank = models.get(parent_model, {}).get("rank", 0)
    if parent_rank >= models[floor_model]["rank"]:
        return parent_model, None, True, f"parent meets {floor} floor"
    mapped = policy["tiers"][floor]
    return mapped["model"], mapped["effort"], False, f"{floor} floor escalates parent"


def _lane_escalation(policy: dict, lane: dict, parent_model: str | None) -> tuple | None:
    threshold = lane.get("escalate_at_or_below")
    if not threshold:
        return None
    models = policy["providers"]["codex"]["models"]
    if parent_model not in models:
        return None
    parent_rank = models.get(parent_model, {}).get("rank", 0)
    threshold_model = policy["tiers"][threshold]["model"]
    if parent_rank > models[threshold_model]["rank"]:
        return None
    target = lane["escalate_to"]
    mapped = policy["tiers"][target]
    return mapped["model"], mapped["effort"], False, f"{target} escalation above {threshold} parent"


def _select_route(policy: dict, lane: str | None, role: str | None) -> tuple[str, dict, dict]:
    roles = {entry["name"]: entry for entry in policy["roles"]}
    lanes = {entry["name"]: entry for entry in policy["lanes"]}
    if lane and lane not in lanes:
        raise PolicyError(f"unknown lane: {lane}")
    if not lane and not role:
        raise PolicyError("specify a role or lane")
    if lane:
        selected = lanes[lane]["role"]
        if role and role != selected:
            raise PolicyError(f"lane {lane} selects role {selected}, not {role}")
        role = selected
    if role not in roles:
        raise PolicyError(f"unknown role: {role}")
    return role, roles[role], lanes.get(lane, {})


def resolve(policy: dict, harness: str = "codex", lane: str | None = None,
            role: str | None = None, parent_model: str | None = None) -> dict:
    """Resolve a named role or lane into its semantic and provider route."""
    if harness != "codex":
        raise PolicyError(f"unsupported harness: {harness}")
    role, route, selected = _select_route(policy, lane, role)
    tier = selected.get("tier", route["tier"])
    floor = selected.get("floor", route.get("floor"))
    model, effort, inherited, decision = _effective_model(policy, tier, floor, parent_model)
    escalation = _lane_escalation(policy, selected, parent_model)
    if escalation is not None:
        model, effort, inherited, decision = escalation
    trace = [f"harness codex", f"lane {lane} selects {role}" if lane else f"role {role}",
             f"tier {tier}" + (f" with {floor} floor" if floor else ""), decision]
    return {"harness": harness, "lane": lane, "role": role, "tier": tier,
            "floor": floor, "model": model, "effort": effort,
            "inherit_model": inherited, "inherit_effort": inherited,
            "unresolved": model is None,
            "permission": route["permission"], "limits": policy["limits"][harness],
            "trace": trace}


def _spawn_choice(policy: dict, required: str | None, spawn_model: str) -> None:
    models = policy["providers"]["codex"]["models"]
    if spawn_model not in models:
        raise PolicyError(f"unsupported spawn model: {spawn_model}")
    if required and models[spawn_model]["rank"] < models[required]["rank"]:
        raise PolicyError(f"spawn model {spawn_model} does not meet required {required}")


def _ceiling_precedence(policy: dict, route: dict, context: dict) -> dict:
    required = route["model"] if not route["inherit_model"] else None
    spawn_model = context["spawn_model"]
    if spawn_model:
        _spawn_choice(policy, required, spawn_model)
        model, effort, source = spawn_model, route["effort"] if required else None, "explicit_spawn"
    else:
        if context["default_model"]:
            raise PolicyError("agents.default_subagent_model would cap Ceiling inheritance")
        if context["default_effort"]:
            raise PolicyError("agents.default_subagent_reasoning_effort would cap Ceiling inheritance")
        parent_model = context["parent_model"]
        model = parent_model if parent_model in policy["providers"]["codex"]["models"] else None
        effort = None
        source = "parent" if model else "unknown_parent"
    route.update(model=model, effort=effort, source=source,
                 required_model=required, requires_spawn_override=bool(required and not spawn_model),
                 unresolved=model is None)
    return route


def effective_route(policy: dict, role: str, parent_model: str | None = None,
                    lane: str | None = None, default_subagent_model: str | None = None,
                    spawn_model: str | None = None,
                    default_subagent_effort: str | None = None) -> dict:
    """Apply Codex's agent-file, spawn, default, parent model precedence."""
    route = resolve(policy, role=role, lane=lane, parent_model=parent_model)
    base_tier = next(item["tier"] for item in policy["roles"] if item["name"] == role)
    route["profile"] = lane if lane and route["tier"] == "Ceiling" and base_tier != "Ceiling" else role
    if route["tier"] != "Ceiling":
        route.update(source="agent_file", required_model=None, requires_spawn_override=False)
    else:
        context = {"parent_model": parent_model, "spawn_model": spawn_model,
                   "default_model": default_subagent_model, "default_effort": default_subagent_effort}
        route = _ceiling_precedence(policy, route, context)
    route["trace"].append(f"Codex precedence selected {route['source']}")
    return route
