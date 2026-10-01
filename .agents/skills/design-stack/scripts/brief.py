"""Read and write the project-owned v1 DESIGN.md contract."""

from pathlib import Path
import re


SECTIONS = ("palette", "typography", "layout", "motion", "accessibility",
            "3d intent", "custom brief")
TEMPLATE = Path(__file__).resolve().parent.parent / "templates/DESIGN.md"


def parse_brief(content):
    """Validate a v1 brief while retaining its authored Markdown rules."""
    if not content.startswith("# Project Design\n"):
        raise ValueError("invalid DESIGN.md heading")
    parts = re.split(r"(?m)^## (.+)\n", content)
    fields = dict(re.findall(r"(?m)^(Version|Direction|References): (.*)$", parts[0]))
    if fields.get("Version") != "1" or not fields.get("Direction") or "References" not in fields:
        raise ValueError("unsupported or incomplete DESIGN.md v1 fields")
    headings = [name.lower() for name in parts[1::2]]
    if len(headings) != len(set(headings)):
        raise ValueError("DESIGN.md contains duplicate visual rule sections")
    rules = {name.lower(): body.strip() for name, body in zip(parts[1::2], parts[2::2])}
    if any(not rules.get(name) for name in SECTIONS):
        raise ValueError("DESIGN.md is missing a visual rule section")
    references = fields.get("References", "none")
    return {"version": 1, "direction": fields["Direction"],
            "references": [] if references == "none" else references.split(", "),
            "rules": rules}


def read_brief(path):
    return parse_brief(Path(path).read_text(encoding="utf-8"))


def render_brief(direction, references, rules):
    if any(not isinstance(rules.get(name), str) or not rules[name].strip() for name in SECTIONS):
        raise ValueError("every DESIGN.md visual rule must contain authored text")
    lines = ["# Project Design", "", "Version: 1", f"Direction: {direction}",
             "References: " + (", ".join(references) or "none"), ""]
    for name in SECTIONS:
        lines.extend((f"## {name.title() if name != '3d intent' else '3D Intent'}",
                      rules[name].strip(), ""))
    return "\n".join(lines)


def validated_choice(choice):
    direction = choice.get("direction")
    references = choice.get("references", [])
    if not isinstance(direction, str) or not direction or direction.startswith(("reference:", "impeccable:", "three:")):
        raise ValueError("brief needs one selected visual direction")
    if not isinstance(references, list) or any(not isinstance(ref, str) or not ref.startswith("reference:") for ref in references):
        raise ValueError("brief references must be selected reference IDs")
    return direction, references


def write_brief(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def create_brief(path, choice, rules=None):
    """Create once after owner selection; never overwrite existing UI rules."""
    path = Path(path)
    if path.exists():
        raise ValueError("DESIGN.md already exists; owner refresh is required")
    direction, references = validated_choice(choice)
    defaults = parse_brief(TEMPLATE.read_text(encoding="utf-8"))["rules"]
    if direction != "spatial" and any(not (rules or {}).get(name) for name in SECTIONS[:5]):
        raise ValueError("owner-authored visual rules are required for this direction")
    rules = {**defaults, **(rules or {})}
    if choice.get("custom_brief"):
        rules = {**rules, "custom brief": choice["custom_brief"]}
    content = render_brief(direction, references, rules)
    parse_brief(content)
    write_brief(path, content)
    return path


def refresh_brief(path, choice, rules=None, *, owner_choice=False):
    """Change authored rules only after a new explicit owner choice."""
    if not owner_choice:
        raise ValueError("owner choice is required to refresh DESIGN.md")
    old = read_brief(path)
    direction, references = validated_choice(choice)
    merged = {**old["rules"], **(rules or {})}
    if choice.get("custom_brief"):
        merged["custom brief"] = choice["custom_brief"]
    content = render_brief(direction, references, merged)
    parse_brief(content)
    write_brief(path, content)
    return Path(path)


def onboard_project(project, project_kind, choice=None, rules=None, *, owner_choice=False):
    """Set a new UI default; preserve an existing UI until its owner chooses."""
    if project_kind in ("backend", "cli"):
        return None
    if project_kind not in ("new-ui", "existing-ui"):
        raise ValueError("project kind must be new-ui, existing-ui, backend, or cli")
    project = Path(project)
    path = project / "DESIGN.md"
    if path.exists():
        read_brief(path)
        return path
    existing = project_kind == "existing-ui"
    if existing and not owner_choice:
        raise ValueError("SelectionRequired: existing UI needs an owner choice")
    if existing and any(not (rules or {}).get(name) for name in SECTIONS[:5]):
        raise ValueError("SelectionRequired: preserve existing visual rules in an authored brief")
    return create_brief(path, choice or {"direction": "spatial", "references": []}, rules)
