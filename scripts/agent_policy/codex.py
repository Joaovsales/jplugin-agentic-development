"""Deterministic native Codex agent-file rendering from the canonical policy."""

import json

from .policy import resolve


EXTRA_AGENTS = {
    "explorer": ("Read-only code reconnaissance", "Inspect code and report cited findings. Do not modify files."),
    "scout": ("MCP-capable source investigator", "Investigate the assigned source with available tools. Do not modify files."),
}


def render_agent(policy: dict, name: str, description: str,
                 instructions: str, marker: str, lane: str | None = None) -> str:
    """Render one route; Ceiling omits both model fields for inheritance."""
    route = resolve(policy, lane=lane) if lane else resolve(policy, role=name)
    fields = {"name": name, "description": description,
              "developer_instructions": instructions}
    if route["tier"] != "Ceiling":
        fields["model"] = route["model"]
        fields["model_reasoning_effort"] = route["effort"]
    if route["permission"] != "mcp-read":
        fields["sandbox_mode"] = route["permission"]
    return marker + "\n" + "".join(
        f"{key} = {json.dumps(value, ensure_ascii=False)}\n" for key, value in fields.items()
    )
