"""Read-only inspection of visible Codex configuration and agent routes."""

from __future__ import annotations

import tomllib
import re
from dataclasses import dataclass
from pathlib import Path

from .policy import resolve

MANAGED = "# jplugin-agentic-development:managed"


@dataclass(frozen=True)
class Context:
    codex_home: Path
    project_dir: Path
    trust: str = "unknown"
    profile: str | None = None
    parent_model: str | None = None
    cli_model: str | None = None
    cli_max_threads: int | None = None
    cli_default_subagent_model: str | None = None
    cli_known: bool = False
    cloud_known: bool = False
    session_known: bool = False


def _read_toml(path: Path) -> tuple[dict | None, str | None]:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        return None, "non-regular file"
    if not path.exists():
        return None, None
    try:
        value = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        return None, str(exc)
    return value, None


def _project_roots(project_dir: Path) -> list[Path]:
    current = project_dir.resolve()
    return [current, *current.parents]


def _cli_config(context: Context) -> dict:
    cli = {"agents": {}}
    if context.cli_model is not None:
        cli["model"] = context.cli_model
    if context.cli_max_threads is not None:
        cli["agents"]["max_concurrent_threads_per_session"] = context.cli_max_threads
    if context.cli_default_subagent_model is not None:
        cli["agents"]["default_subagent_model"] = context.cli_default_subagent_model
    return cli


def _project_layers(context: Context, layers: list, findings: list, unknown: list) -> None:
    project_files = [root / ".codex/config.toml" for root in _project_roots(context.project_dir)]
    if context.trust == "trusted":
        for path in project_files:
            value, error = _read_toml(path)
            if error:
                findings.append(f"invalid project config {path}: {error}")
            elif value is not None:
                layers.append((f"project:{path}", value))
    elif context.trust == "unknown":
        project_agents = [root / ".codex/agents" for root in _project_roots(context.project_dir)]
        if any(path.exists() for path in project_files) or any(
            any(directory.glob("*.toml")) for directory in project_agents
        ):
            unknown.append("project_trust")


def _profile_layer(context: Context, layers: list, findings: list) -> None:
    if not context.profile:
        return
    if not re.fullmatch(r"[A-Za-z0-9_-]+", context.profile):
        findings.append(f"invalid selected profile name {context.profile!r}")
        return
    profile_path = context.codex_home / f"{context.profile}.config.toml"
    selected, error = _read_toml(profile_path)
    if error:
        findings.append(f"invalid selected profile {profile_path}: {error}")
    elif selected is not None:
        layers.append((f"profile:{context.profile}", selected))
    else:
        findings.append(f"selected profile {context.profile} is unavailable")


def _visible_layers(context: Context) -> tuple[list[tuple[str, dict]], list[str], list[str]]:
    findings = []
    unknown = [name for name, known in (("cli", context.cli_known), ("cloud", context.cloud_known),
                                          ("session", context.session_known)) if not known]
    layers = [("cli", _cli_config(context))]
    _project_layers(context, layers, findings, unknown)
    user_path = context.codex_home / "config.toml"
    user, error = _read_toml(user_path)
    if error:
        findings.append(f"invalid user config {user_path}: {error}")
    user = user or {}
    _profile_layer(context, layers, findings)
    layers.append((f"user:{user_path}", user))
    return layers, findings, unknown


def _winner(layers: list[tuple[str, dict]], key: str) -> tuple[object | None, str | None]:
    for source, layer in layers:
        value = layer.get(key)
        if value is not None:
            return value, source
    return None, None


def _agent_winner(layers: list[tuple[str, dict]], key: str) -> tuple[object | None, str | None]:
    for source, layer in layers:
        agents = layer.get("agents", {})
        if isinstance(agents, dict):
            value = agents.get(key)
            if value is not None:
                return value, source
    return None, None


def _cap(layers: list[tuple[str, dict]], policy: dict) -> dict:
    for source, layer in layers:
        agents = layer.get("agents", {})
        if not isinstance(agents, dict):
            continue
        for key in ("max_concurrent_threads_per_session", "max_threads"):
            if key in agents:
                value = agents[key]
                status = "unsupported" if type(value) is not int or value <= 0 else (
                    "excess" if value > policy["limits"]["codex"]["max_children"] else "match")
                return {"value": value, "status": status, "source": source, "key": key}
    return {"value": None, "status": "missing", "source": None, "key": None}


def _agent_path(context: Context, name: str) -> tuple[Path, str]:
    if context.trust == "trusted":
        for root in _project_roots(context.project_dir):
            path = root / ".codex/agents" / f"{name}.toml"
            if path.exists() or path.is_symlink():
                return path, "project"
    return context.codex_home / "agents" / f"{name}.toml", "user"


def _agent_state(path: Path, route: dict, layer: str) -> tuple[dict | None, str]:
    installed, error = _read_toml(path)
    if error:
        return None, "InvalidInstalled"
    if installed is None:
        return None, "Missing"
    if layer == "project":
        return installed, "ProjectShadow"
    text = path.read_text(encoding="utf-8")
    if not text.startswith(MANAGED + "\n"):
        return installed, "PersonalConflict"
    expected = (route["model"], route["effort"]) if route["tier"] != "Ceiling" else (None, None)
    actual = (installed.get("model"), installed.get("model_reasoning_effort"))
    sandbox = None if route["permission"] == "mcp-read" else route["permission"]
    matches = (actual == expected and installed.get("sandbox_mode") == sandbox
               and installed.get("name") == path.stem)
    return installed, "Match" if matches else "ManagedDrift"


def _observed_model(installed: dict | None, route: dict, path: Path,
                    effective: dict) -> tuple[object | None, str]:
    pinned = installed.get("model") if isinstance(installed, dict) else None
    if pinned is not None:
        return pinned, f"agent_file:{path}"
    if not installed:
        return None, "missing_agent"
    if route["tier"] == "Ceiling" and effective["default_model"] is not None:
        return effective["default_model"], f"agents.default_subagent_model:{effective['default_source']}"
    model = effective["parent_model"] if route["tier"] == "Ceiling" else route["model"]
    return model, f"parent:{effective['parent_source']}" if model else "unknown_parent"


def _observed_effort(installed: dict | None, path: Path, effective: dict) -> tuple[object | None, str]:
    pinned = installed.get("model_reasoning_effort") if installed else None
    if pinned is not None:
        return pinned, f"agent_file:{path}"
    if installed and effective["default_effort"] is not None:
        return effective["default_effort"], f"agents.default_subagent_reasoning_effort:{effective['effort_source']}"
    return None, "parent_or_unknown"


def _role_report(policy: dict, context: Context, name: str, lane: bool, effective: dict) -> dict:
    parent = effective["parent_model"]
    route = resolve(policy, lane=name, parent_model=parent) if lane else (
        resolve(policy, role=name, parent_model=parent))
    path, layer = _agent_path(context, name)
    installed, state = _agent_state(path, route, layer)
    model, source = _observed_model(installed, route, path, effective)
    effort, effort_source = _observed_effort(installed, path, effective)
    requires_spawn_override = bool(installed and installed.get("model") is None and
                                   route["tier"] == "Ceiling" and not route["inherit_model"])
    models = policy["providers"]["codex"]["models"]
    scout = policy["tiers"]["Scout"]["model"]
    expensive = bool(source.startswith("parent:") and installed and
                     model in models and models[model]["rank"] > models[scout]["rank"])
    return {"file": str(path), "file_layer": layer, "file_status": state,
            "model": model, "model_source": source, "effort": effort,
            "effort_source": effort_source,
            "tier": route["tier"], "inherited_expensive": expensive,
            "requires_spawn_override": requires_spawn_override}


def _role_names(policy: dict) -> list[str]:
    names = sorted({role["name"] for role in policy["roles"]} |
                   {lane["name"] for lane in policy["lanes"] if lane.get("tier") == "Ceiling" and
                    next(role["tier"] for role in policy["roles"] if role["name"] == lane["role"]) != "Ceiling"})
    return names


def _append_role_findings(roles: dict, findings: list) -> None:
    for name, route in roles.items():
        if route["file_status"] != "Match":
            findings.append(f"{name}: {route['file_status']} at {route['file']}")
        elif route["inherited_expensive"]:
            findings.append(f"{name}: inherits expensive parent model {route['model']}")
        if route["requires_spawn_override"]:
            findings.append(f"{name}: policy floor requires a spawn override; no effective spawn was supplied")


def _child_defaults(layers: list, findings: list) -> tuple:
    default, default_source = _agent_winner(layers, "default_subagent_model")
    effort, effort_source = _agent_winner(layers, "default_subagent_reasoning_effort")
    if default is not None:
        findings.append(f"agents.default_subagent_model at {default_source} caps Ceiling inheritance")
    if effort is not None:
        findings.append(f"agents.default_subagent_reasoning_effort at {effort_source} caps Ceiling inheritance")
    return default, default_source, effort, effort_source


def _parent_context(context: Context, config_model: object, model_source: str | None,
                    unknown: list) -> tuple[str | None, str | None]:
    if context.parent_model is not None:
        return context.parent_model, "explicit_argument"
    if unknown or not isinstance(config_model, str):
        return None, model_source
    return config_model, model_source


def inspect(policy: dict, context: Context) -> dict:
    """Report visible winners; unavailable higher layers prevent a healthy verdict."""
    layers, findings, unknown = _visible_layers(context)
    config_model, model_source = _winner(layers, "model")
    cap = _cap(layers, policy)
    if cap["status"] != "match":
        findings.append(f"child cap {cap['status']} at {cap['source'] or 'unknown layer'}")
    default, default_source, default_effort, effort_source = _child_defaults(layers, findings)
    lane_names = {lane["name"] for lane in policy["lanes"]}
    parent, parent_source = _parent_context(context, config_model, model_source, unknown)
    effective = {"parent_model": parent, "parent_source": parent_source,
                 "default_model": default, "default_source": default_source,
                 "default_effort": default_effort, "effort_source": effort_source}
    roles = {name: _role_report(policy, context, name, name in lane_names, effective)
             for name in _role_names(policy)}
    _append_role_findings(roles, findings)
    status = "UnknownLayer" if unknown else ("Issue" if findings else "Match")
    return {"status": status, "unknown_layers": unknown, "model": config_model,
            "model_source": model_source, "cap": cap, "roles": roles, "findings": findings,
            "config_layers": [source for source, _ in layers]}
