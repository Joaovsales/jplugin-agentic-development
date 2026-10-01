"""Discover design choices from one verified shared release."""

import json
from pathlib import Path
import re


HEADING = re.compile(r"^(#{2,6})\s+(.+)$")
NUMBERED = re.compile(r"^\d+\.\s+\*\*(.+?)\*\*(?::|\s|$)")
WORD = re.compile(r"[a-z0-9]+")
FIT_STOPWORDS = {"a", "and", "for", "of", "the", "to", "with", "style", "visual",
                 "design", "interface", "interfaces", "ui", "product", "products"}


def slug(value):
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    if not result:
        raise ValueError("catalog entry has no stable name")
    return result


def safe_file(path, release):
    if not path.is_file() or not path.resolve().is_relative_to(release.resolve()):
        raise ValueError(f"catalog path is missing or leaves the verified release: {path}")
    return path


def frontmatter(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    fields = {}
    if lines and lines[0] == "---":
        for line in lines[1:]:
            if line == "---":
                break
            key, separator, value = line.partition(":")
            if separator and key in ("name", "description"):
                fields[key] = value.strip()
    return fields, lines


def entry(identifier, kind, title, revision, fit, path=None):
    result = {"id": identifier, "kind": kind, "title": title,
              "source_revision": revision, "fit": fit}
    if path is not None:
        result["path"] = str(path)
    return result


def archetypes(lines, skill_name, revision, path):
    found = []
    section_depth = None
    for line in lines:
        heading = HEADING.match(line)
        if heading:
            depth, title = len(heading[1]), heading[2].strip()
            if "archetype" in title.lower():
                section_depth = depth
            elif section_depth is not None and depth > section_depth:
                name = re.sub(r"^\d+(?:\.\d+)*\s+", "", title)
                found.append(entry(f"taste:{skill_name}:{slug(name)}", "archetype",
                                   name, revision, title, path))
            else:
                section_depth = None
            continue
        item = NUMBERED.match(line) if section_depth is not None else None
        if item:
            name = item[1].rstrip(":")
            found.append(entry(f"taste:{skill_name}:{slug(name)}", "archetype",
                               name, revision, line.strip(), path))
    return found


def build_catalog(release, revisions):
    """Return every option available in a staged or current local release."""
    release = Path(release)
    sources = release / "sources"
    entries = [entry("spatial", "direction", "Spatial", "builtin:v1", "Spatial UI"),
               entry("custom", "direction", "Custom", "builtin:v1", "Owner-authored visual rules")]
    taste = sorted((sources / "taste/skills").glob("*/SKILL.md"))
    references = sorted((sources / "references/design-md").glob("*/DESIGN.md"))
    if not taste or not references:
        raise ValueError("catalog needs Taste styles and design references")
    for path in taste:
        safe_file(path, release)
        fields, lines = frontmatter(path)
        name = path.parent.name
        entries.append(entry(f"taste:{name}", "direction", fields.get("name", name),
                             revisions["taste"], fields.get("description", ""), path))
        entries.extend(archetypes(lines, name, revisions["taste"], path))
    for path in references:
        safe_file(path, release)
        name = path.parent.name
        entries.append(entry(f"reference:{name}", "reference", name,
                             revisions["references"], "Design reference", path))
    metadata = release / ".agents/skills/impeccable/scripts/command-metadata.json"
    if not metadata.exists():
        metadata = sources / "impeccable/.agent/skills/impeccable/scripts/command-metadata.json"
    if metadata.exists():
        safe_file(metadata, release)
        commands = json.loads(metadata.read_text(encoding="utf-8"))
        if not isinstance(commands, dict):
            raise ValueError("Impeccable command metadata is invalid")
        for name, details in sorted(commands.items()):
            if not isinstance(details, dict) or not isinstance(details.get("description"), str):
                raise ValueError(f"invalid Impeccable command: {name}")
            entries.append(entry(f"impeccable:{slug(name)}", "tool", name,
                                 revisions["impeccable"], details["description"], metadata))
    else:
        source_skill = sources / "impeccable/.agent/skills/impeccable"
        safe_file(source_skill / "SKILL.md", release)
        references_dir = release / ".agents/skills/impeccable/reference"
        if not references_dir.is_dir():
            references_dir = source_skill / "reference"
        command_files = sorted(references_dir.glob("*.md"))
        for path in command_files:
            safe_file(path, release)
            entries.append(entry(f"impeccable:{slug(path.stem)}", "tool", path.stem,
                                 revisions["impeccable"], "Impeccable command reference", path))
        if not command_files:
            entries.append(entry("impeccable:impeccable", "tool", "Impeccable",
                                 revisions["impeccable"], "UI design commands",
                                 source_skill / "SKILL.md"))
    path = safe_file(sources / "three/SKILL.md", release)
    entries.append(entry("three:img2threejs", "tool", "img2threejs",
                         revisions["three"], "Opt-in image-to-3D pipeline", path))
    identifiers = [item["id"] for item in entries]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("catalog contains duplicate IDs")
    return entries


def select_direction(entries, direction, references, custom_brief="", use_case="",
                     override_fit=False):
    """Validate an owner's one-direction selection without changing project files."""
    by_id = {item["id"]: item for item in entries}
    chosen = by_id.get(direction)
    if not chosen or chosen["kind"] not in ("direction", "archetype"):
        raise ValueError(f"SelectionRejected: invalid primary direction: {direction}")
    if len(references) != len(set(references)) or any(
            by_id.get(ref, {}).get("kind") != "reference" for ref in references):
        raise ValueError("SelectionRejected: references must be unique catalog references")
    fit = set(WORD.findall(chosen["fit"].lower())) - FIT_STOPWORDS
    use = set(WORD.findall(use_case.lower())) - FIT_STOPWORDS
    warning = bool(use and fit and not use.intersection(fit) and direction != "custom")
    if warning and not override_fit:
        raise ValueError(f"Fit warning: {direction} describes {chosen['fit']}; owner may override")
    return {"direction": direction, "references": references,
            "custom_brief": custom_brief, "fit_warning": warning}
