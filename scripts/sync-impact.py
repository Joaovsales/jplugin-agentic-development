#!/usr/bin/env python3
"""Preview the downstream impact between two commits in the template repository."""

import argparse
import json
from pathlib import Path
import runpy
import sys


SYNC_SCRIPTS = Path(__file__).resolve().parents[1] / ".agents/skills/sync/scripts"
PROJECT_FILES = {"AGENTS.md", "CLAUDE.md", ".claude/settings.json"}
RETIRE = runpy.run_path(str(SYNC_SCRIPTS / "sync-retire.py"))
MANAGED = runpy.run_path(str(SYNC_SCRIPTS / "sync-managed-block.py"))


def compare(base_ref, target_ref):
    def git(*args):
        return RETIRE["_git"](".", *args)

    base, target = (
        git("rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}").strip()
        for ref in (base_ref, target_ref)
    )
    roots = set()
    blocks = []
    for commit in (base, target):
        doc = RETIRE["read_template_doc"](".", commit, None)
        live, retired = RETIRE["parse_syncable_roots"](doc, commit)
        roots.update(root.rstrip("/") for root in live + retired)
        label = f"{commit}:AGENTS.md"
        blocks.append(MANAGED["extract_source_block"](label, git("show", label)))

    # See both sides of a move across the managed boundary, even on large diffs.
    changed = git("diff", "--name-only", "--no-renames", "-z", base, target, "--")
    impact = {"base": base, "target": target, "project_sync": [], "plugin_only": [], "other": []}
    for path in sorted(filter(None, changed.split("\0"))):
        if path == "AGENTS.md" and blocks[0] == blocks[1]:
            impact["other"].append(path)
        elif path in PROJECT_FILES or any(path == root or path.startswith(root + "/") for root in roots):
            impact["project_sync"].append(path)
        elif path.startswith((".claude-plugin/", "hooks/")):
            impact["plugin_only"].append(path)
        else:
            impact["other"].append(path)
    return impact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", help="last reviewed template commit or tag")
    parser.add_argument("target", help="candidate template commit or tag")
    args = parser.parse_args()
    # The sync helpers own their error types. Keep their diagnostic and an empty
    # report if Git or either snapshot cannot be read.
    try:
        impact = compare(args.base, args.target)
    except (OSError, RETIRE["RetireError"], MANAGED["ManagedBlockError"]) as exc:
        print(f"sync-impact: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(impact, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
