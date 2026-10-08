#!/usr/bin/env python3
"""Install a verified, user-scoped release of the shared design sources."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from catalog import build_catalog, select_direction, source_paths
from brief import SECTIONS, create_brief, read_brief, refresh_brief


SOURCES = {
    "taste": "https://github.com/Leonxlnx/taste-skill.git",
    "impeccable": "https://github.com/pbakaus/impeccable.git",
    "references": "https://github.com/VoltAgent/awesome-design-md.git",
    "three": "https://github.com/img2threejs/img2threejs.git",
}
HOME = Path(os.environ.get("DESIGN_STACK_HOME", Path.home() / ".local/share/jplugin/design-stack"))


def run(*command, cwd=None, env=None):
    timeout = float(os.environ.get("DESIGN_STACK_TIMEOUT", "90"))
    # Windows CreateProcess ignores PATHEXT, so a bare `npx` never finds npx.cmd.
    executable = shutil.which(command[0]) or command[0]
    return subprocess.run((executable, *command[1:]), check=True, capture_output=True, text=True,
                          timeout=timeout, cwd=cwd, env=env).stdout.strip()


def current_manifest():
    path = HOME / "manifest.json"
    if not path.exists():
        return None
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") not in (0, 1):
        raise ValueError("unsupported design-stack manifest version")
    release = manifest.get("current", "")
    if not isinstance(release, str) or len(release) != 64 or any(c not in "0123456789abcdef" for c in release):
        raise ValueError("invalid current release pointer")
    location = HOME / "releases" / release
    if Path(manifest.get("catalog_path", "")).resolve() != (location / "sources").resolve():
        raise ValueError("catalog path leaves the verified release")
    validate(location)
    build_catalog(location, manifest["sources"])
    if len(installed_entrypoints(location)) < 2:
        raise ValueError("installed design commands are missing")
    for name in SOURCES:
        revision = run("git", "-C", str(location / "sources" / name), "rev-parse", "HEAD")
        if manifest.get("sources", {}).get(name) != revision:
            raise ValueError(f"{name} revision differs from manifest")
    return manifest


def validate(release):
    source_paths(release)


def stage_release(stage):
    revisions = {}
    for name, url in SOURCES.items():
        url = os.environ.get(f"DESIGN_STACK_{name.upper()}_URL", url)
        path = stage / "sources" / name
        run("git", "clone", "--quiet", "--", url, str(path))
        revisions[name] = run("git", "-C", str(path), "rev-parse", "HEAD")
    return revisions


def installed_entrypoints(stage):
    paths = set()
    for home in (stage, stage / "user"):
        for root in (".agent", ".agents", ".claude"):
            base = home / root
            if base.exists():
                paths.update(p for p in base.rglob("SKILL.md") if p.is_file())
                paths.update(p for p in base.rglob("commands/*.md") if p.is_file())
    return paths


def install_skills(stage):
    """Run upstream CLIs with all home and project writes confined to staging."""
    user_home = stage / "user"
    user_home.mkdir()
    env = os.environ.copy()
    env.update(HOME=str(user_home), XDG_DATA_HOME=str(user_home / ".local/share"),
               XDG_CONFIG_HOME=str(user_home / ".config"),
               npm_config_cache=str(stage / "npm-cache"))
    npx = os.environ.get("DESIGN_STACK_NPX", "npx")
    run(npx, "--yes", "skills", "add", str(stage / "sources/taste"), "--yes",
        cwd=stage, env=env)
    taste_entries = installed_entrypoints(stage)
    if not taste_entries:
        raise ValueError("Taste installer produced no staged skill")
    run(npx, "--yes", "--package", str(stage / "sources/impeccable"),
        "impeccable", "install", cwd=stage, env=env)
    if not installed_entrypoints(stage) - taste_entries:
        raise ValueError("Impeccable installer produced no staged command or skill")


def release_id(revisions):
    encoded = json.dumps(revisions, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def promote(stage, revisions):
    identifier = release_id(revisions)
    release = HOME / "releases" / identifier
    if not release.exists():
        stage.rename(release)
    manifest = {
        "schema_version": 1,
        "sources": revisions,
        "catalog_path": str(release / "sources"),
        "current": identifier,
    }
    temporary = HOME / "manifest.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    temporary.replace(HOME / "manifest.json")
    return manifest


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "update", "status", "catalog", "select",
                                           "brief", "read-brief", "refresh"))
    parser.add_argument("--json", action="store_true", help="print catalog entries as JSON")
    parser.add_argument("--direction", help="one catalog direction or archetype ID")
    parser.add_argument("--reference", action="append", default=[], help="reference ID; repeatable")
    parser.add_argument("--custom-brief", default="", help="owner-authored brief text")
    parser.add_argument("--use-case", default="", help="target use case for a fit warning")
    parser.add_argument("--override-fit", action="store_true", help="accept a fit warning")
    parser.add_argument("--project", help="UI project directory containing DESIGN.md")
    parser.add_argument("--rule", action="append", default=[], help="visual rule as section=text")
    parser.add_argument("--owner-choice", action="store_true", help="confirm explicit owner selection")
    return parser.parse_args()


def selected_rules(raw_rules):
    rules = {}
    for rule in raw_rules:
        name, separator, value = rule.partition("=")
        if not separator or name not in SECTIONS or name in rules:
            raise ValueError("--rule needs a unique known section=text")
        rules[name] = value
    return rules


def selected_command(args, entries):
    if not args.direction:
        raise ValueError("--direction is required for selection")
    choice = select_direction(entries, args.direction, args.reference,
                              args.custom_brief, args.use_case, args.override_fit)
    if args.action == "select":
        print(json.dumps(choice, indent=2))
        return
    if not args.project or not args.owner_choice:
        raise ValueError("--project and explicit --owner-choice are required")
    rules = selected_rules(args.rule)
    path = Path(args.project) / "DESIGN.md"
    if args.action == "brief":
        create_brief(path, choice, rules or None)
    else:
        refresh_brief(path, choice, rules, owner_choice=True)
    print(path)


def catalog_command(args, previous):
    if not previous:
        raise ValueError("run design-stack setup before UI work")
    release = HOME / "releases" / previous["current"]
    entries = build_catalog(release, previous["sources"])
    if args.action != "catalog":
        selected_command(args, entries)
    elif args.json:
        print(json.dumps(entries, indent=2))
    else:
        for item in entries:
            print(f"{item['kind']:10} {item['id']:45} {item['title']}")


def install_command(previous):
    HOME.mkdir(parents=True, exist_ok=True)
    (HOME / "releases").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="staging-", dir=HOME) as folder:
        stage = Path(folder)
        revisions = stage_release(stage)
        if previous and previous["sources"] == revisions:
            print(f"Ready {previous['current']} (unchanged)")
            return
        install_skills(stage)
        validate(stage)
        build_catalog(stage, revisions)
        result = promote(stage, revisions)
    print(f"Ready {result['current']}")


def error_outcome(action, previous, error):
    if action == "update" and previous:
        return "UpdateRejected"
    if action in ("select", "brief", "refresh") and previous and isinstance(error, ValueError):
        return "SelectionRejected"
    return "SetupRequired"


def main():
    args = parse_args()
    previous = None
    try:
        if args.action == "read-brief":
            if not args.project:
                raise ValueError("--project is required")
            print(json.dumps(read_brief(Path(args.project) / "DESIGN.md"), indent=2))
        else:
            previous = current_manifest()
            if args.action in ("catalog", "select", "brief", "refresh"):
                catalog_command(args, previous)
            elif args.action == "status" or (args.action == "setup" and previous):
                if not previous:
                    raise ValueError("run design-stack setup before UI work")
                print(f"Ready {previous['current']} (offline)")
            else:
                install_command(previous)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        outcome = error_outcome(args.action, previous, error)
        print(f"{outcome}: {str(error).removeprefix(f'{outcome}: ')}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
