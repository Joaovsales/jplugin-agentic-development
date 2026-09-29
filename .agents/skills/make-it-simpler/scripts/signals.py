#!/usr/bin/env python3
"""signals.py — rank simplification candidates for /make-it-simpler.

    signals.py rank [--path <p>]... [--limit N]

Prints {"head": <short sha>, "candidates": [...]} sorted by score desc, then
key asc. Deterministic, read-only and offline: the only subprocesses are
`git ls-files` and `git rev-parse`. The seven signals, the weight W and the
exclusions are defined in references/lens.md. Paths are root-relative wherever
it is run from; a tracked file that cannot be read (deleted, not yet staged) is
skipped.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import PurePosixPath

W = 5
EXCLUDED_PREFIXES = ("tests/fixtures/",)
ALWAYS_LOADED = ("AGENTS.md", "CLAUDE.md", ".agents/hooks/session-start.sh")
LINE_BUDGETS = {"SKILL.md": 150, "AGENTS.md": 200}
CODE_BUDGET = 500
DUPLICATE_MIN_CHARS = 60
NEEDLE_MIN_CHARS = 20

CITE = re.compile(r"`([^`\n]+\.md|/[a-z0-9-]+)` § \*([^*]+?)\*")
HEADING = re.compile(r"^#{2,3} (.+?)\s*$|^\*\*([^*\n]+?)\.?\*\*", re.M)
SCRIPT_REF = re.compile(r"`([^`\s]+\.(?:py|sh))`")
FLAG = re.compile(r"(?<![\w-])--[a-z][a-z0-9-]+")
NEEDLE = re.compile(r'"([^"$\\\n]{%d,})"' % NEEDLE_MIN_CHARS)
ENFORCING = re.compile(r"\b(must|never|always)\b", re.I)
LIST_MARK = re.compile(r"^(?:[-*>]|\d+\.)\s+")


def git(*args):
    done = subprocess.run(["git", *args], capture_output=True, text=True,
                          encoding="utf-8", check=False)
    if done.returncode != 0:
        print(f"signals: git {args[0]} failed: {done.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return done.stdout


def tracked_texts():
    texts = {}
    for path in sorted(git("ls-files", "-z").split("\0")):
        if not path or path.startswith(EXCLUDED_PREFIXES):
            continue
        try:
            raw = open(path, "rb").read()
        except OSError:
            continue
        if b"\0" not in raw:
            texts[path] = raw.decode("utf-8", errors="replace")
    return texts


def resolve(ref, citing, texts):
    """The tracked path `ref` names, from the root or the citing file's dir."""
    if ref.startswith("/"):
        ref = f".agents/skills/{ref[1:]}/SKILL.md"
    for candidate in (ref, str(PurePosixPath(citing).parent / ref)):
        if candidate in texts:
            return candidate
    return None


def unfenced_lines(text):
    fenced = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif not fenced:
            yield number, line


def markdown(texts):
    return [p for p in texts if p.endswith(".md")]


def detect_duplicate_rule(texts):
    seen = {}
    for path in markdown(texts):
        digest = hashlib.sha256(texts[path].encode("utf-8")).hexdigest()
        for number, line in unfenced_lines(texts[path]):
            rule = LIST_MARK.sub("", line.strip())
            if len(rule) >= DUPLICATE_MIN_CHARS and not rule.startswith(("#", "|")):
                seen.setdefault(rule, {}).setdefault(digest, (path, number))
    for homes in seen.values():
        if len(homes) > 1:
            path, number = min(homes.values())
            yield path, number, len(homes) - 1


def detect_citation_drift(texts):
    for path in markdown(texts):
        for match in CITE.finditer(texts[path]):
            target = resolve(match[1], path, texts)
            if target is None:
                continue  # an unresolved path or a retired skill: /tidy owns it
            wanted = " ".join(match[2].split())
            found = {" ".join((m[1] or m[2]).split()) for m in HEADING.finditer(texts[target])}
            if wanted not in found:
                yield path, texts[path].count("\n", 0, match.start()) + 1, 1


def detect_over_budget(texts):
    for path, text in texts.items():
        budget = LINE_BUDGETS.get(PurePosixPath(path).name)
        count = len(text.splitlines())
        if budget and count > budget:
            yield path, budget + 1, count - budget


def detect_doc_script_contradiction(texts):
    for path in markdown(texts):
        for number, line in unfenced_lines(texts[path]):
            scripts = [s for s in (resolve(r, path, texts) for r in SCRIPT_REF.findall(line)) if s]
            flags = FLAG.findall(line)
            if scripts and any(all(f not in texts[s] for s in scripts) for f in flags):
                yield path, number, 1


def test_needles(texts):
    needles = set()
    for path, text in texts.items():
        if path.startswith("tests/") and path.endswith(".sh"):
            needles.update(NEEDLE.findall(text))
    return sorted(needles)


def detect_enforced_prose(texts):
    needles = test_needles(texts)
    for path in markdown(texts):
        for number, line in unfenced_lines(texts[path]):
            if ENFORCING.search(line) and any(n in line for n in needles):
                yield path, number, 1


def detect_orphan(texts):
    for path in texts:
        pure = PurePosixPath(path)
        if pure.parent.name != "references" or pure.suffix != ".md":
            continue
        if not any(pure.name in t for p, t in texts.items() if p != path):
            yield path, 1, len(texts[path].splitlines())


def detect_code_red_flag(texts):
    for path, text in texts.items():
        count = len(text.splitlines())
        if path.endswith((".py", ".sh")) and count > CODE_BUDGET:
            yield path, CODE_BUDGET + 1, count - CODE_BUDGET


#: The seven signals, in lens.md's order: the one place a signal is named.
DETECTORS = {
    "duplicate-rule": detect_duplicate_rule,
    "citation-drift": detect_citation_drift,
    "over-budget": detect_over_budget,
    "doc-script-contradiction": detect_doc_script_contradiction,
    "enforced-prose": detect_enforced_prose,
    "orphan-or-overlap": detect_orphan,
    "code-red-flag": detect_code_red_flag,
}
SIGNALS = tuple(DETECTORS)


def hits(texts):
    """One (signal, path) → [first line, summed lines_saved]."""
    grouped = {}
    for signal, detector in DETECTORS.items():
        for path, line, saved in detector(texts):
            entry = grouped.setdefault((signal, path), [line, 0])
            entry[0] = min(entry[0], line)
            entry[1] += saved
    return grouped


def always_loaded(path, line, text):
    if path in ALWAYS_LOADED:
        return True
    if PurePosixPath(path).name != "SKILL.md" or not text.startswith("---"):
        return False
    lines = text.splitlines()
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), 0)
    return line <= end + 1


def score(lines_saved, callers, loaded):
    return lines_saved * max(callers, 1) * (W if loaded else 1)


def candidate(key, first, texts):
    (signal, path), (line, saved) = key, first
    callers = sum(1 for p, t in texts.items() if p != path and path in t)
    loaded = always_loaded(path, line, texts[path])
    return {"signal": signal, "path": path, "line": line,
            "evidence": texts[path].splitlines()[line - 1], "lines_saved": saved,
            "callers": callers, "always_loaded": loaded,
            "score": score(saved, callers, loaded), "key": f"{signal} in {path}"}


def under(path, prefixes):
    return not prefixes or any(path == p or path.startswith(p.rstrip("/") + "/") for p in prefixes)


def rank(prefixes, limit):
    os.chdir(git("rev-parse", "--show-toplevel").strip())
    texts = tracked_texts()
    for prefix in prefixes:
        if not any(under(p, [prefix]) for p in texts):
            print(f"signals: --path {prefix} matches no tracked file", file=sys.stderr)
            return 2
    cands = [candidate(key, first, texts) for key, first in hits(texts).items() if under(key[1], prefixes)]
    cands.sort(key=lambda c: (-c["score"], c["key"]))
    head = git("rev-parse", "--short", "HEAD").strip()
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps({"head": head, "candidates": cands[:limit]}, indent=2, ensure_ascii=False))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="signals.py")
    sub = parser.add_subparsers(dest="command", required=True)
    rank_parser = sub.add_parser("rank")
    rank_parser.add_argument("--path", action="append", default=[])
    rank_parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args(argv)
    return rank(args.path, args.limit)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
