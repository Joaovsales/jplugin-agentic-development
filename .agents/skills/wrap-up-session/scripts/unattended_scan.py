#!/usr/bin/env python3
"""unattended_scan.py — a deterministic scan of what an unattended session did.

An unattended push (a `routine/` branch, or a caller that declares itself
unattended) is reviewed by models, and two model runs over one input can
disagree. This scan cannot: a fixed ruleset of regular expressions, read from
`unattended-scan-rules.json` beside this file, runs over the commands the
session's tool calls named (its transcript) and the lines its push adds (its
diff), both through one normalisation. specs/unattended-scan.md is the contract.

    unattended_scan.py scan [--base REV] [--head REV] [--transcript PATH|auto]...
    unattended_scan.py selftest

Exit 0: no high-severity hit. Exit 1: at least one. Exit 2: the scan could not
run — a rule file that does not load, a rule whose fixture disagrees with its
pattern, a project rule that reuses a built-in id, an unreadable transcript or a
git failure. The pre-push hook blocks on 1 and 2 alike.

A project adds rules in `.agents/unattended-scan-rules.json` (same schema, no
`known_gaps`); it can never redefine or remove a built-in rule. Every rule, the
project's included, proves itself against its `match` and `no_match` fixtures
before anything is scanned, so a rule that silently matches nothing cannot load.

Standard library only, so it runs wherever git and python3 do.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import traceback
from dataclasses import dataclass
from typing import Iterable, Iterator, List, Optional, Sequence, Tuple

BUILTIN_RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "unattended-scan-rules.json")
#: Where the two rule files sit in a repository. Their fixtures are written to
#: match, so they are never text-scanned; editing the built-in file is a path hit.
PROJECT_RULES = ".agents/unattended-scan-rules.json"
RULE_FILE_PATHS = frozenset({PROJECT_RULES, ".agents/skills/wrap-up-session/scripts/unattended-scan-rules.json"})

SEVERITY_TAG = {"high": "MUST-FIX", "medium": "SHOULD-FIX"}
SOURCES = ("transcript", "diff")
RULE_KEYS = frozenset({"id", "severity", "kind", "sources", "pattern", "description", "match", "no_match", "gaps"})
FILE_KEYS = {True: frozenset({"about", "known_gaps", "rules"}), False: frozenset({"about", "rules"})}

#: Transcript objects that are tool calls: Claude Code `tool_use`, Codex
#: `function_call`, `custom_tool_call` and `local_shell_call`.
TOOL_CALL_TYPES = frozenset({"tool_use", "function_call", "custom_tool_call", "local_shell_call"})
CALL_PAYLOAD_KEYS = ("input", "arguments", "action")
#: What a call *did*: the command it ran or the path or URL it touched. Written
#: file content is the diff's job, and tool output is never read.
ACTION_KEYS = ("command", "cmd", "file_path", "path", "url")

ANSI_RE = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[@-Z\\-_])")
LINE_BREAK_RE = re.compile(r"\r\n|\r|\n")
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
EXCERPT_MAX = 160


class ScanError(Exception):
    """The scan could not run; exit 2 with this message."""


@dataclass(frozen=True)
class Rule:
    id: str
    severity: str
    kind: str
    sources: Tuple[str, ...]
    regex: "re.Pattern[str]"
    description: str


@dataclass(frozen=True, order=True)
class Hit:
    location: str
    line: int
    rule_id: str
    severity: str
    description: str
    evidence: str


# ── normalisation ────────────────────────────────────────────────────────────

def logical_lines(physical: Iterable[Tuple[int, str]]) -> List[Tuple[int, str]]:
    """The one normalisation both sources go through.

    ANSI escapes are removed; `\\r\\n`, a lone `\\r` and `\\n` all end a line, so
    text hidden behind a carriage return is scanned on its own; a line ending in
    a backslash or a shell pipe is joined to the next (including blank lines).
    Each logical line keeps the number of the physical line it started on.
    """
    out: List[Tuple[int, str]] = []
    pending: Optional[Tuple[int, str]] = None
    for number, raw in physical:
        for segment in LINE_BREAK_RE.split(ANSI_RE.sub("", raw)):
            start, text = (pending[0], pending[1] + segment) if pending else (number, segment)
            if text.endswith("\\"):
                pending = (start, text[:-1])
                continue
            if text.rstrip().endswith("|") and not text.lstrip().startswith("|"):
                pending = (start, text + " ")
                continue
            pending = None
            out.append((start, text))
    if pending:
        out.append(pending)
    return out


def _matches(rule: Rule, text: str) -> bool:
    if rule.kind == "path":
        return rule.regex.search(text) is not None
    return any(rule.regex.search(line) for _, line in logical_lines([(1, text)]))


# ── rules ────────────────────────────────────────────────────────────────────

def _fail(where: str, why: str) -> ScanError:
    return ScanError(f"{where}: {why}")


def _strings(value: object) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(s, str) and s for s in value)


def _parse_rule(raw: object, where: str) -> Rule:
    if not isinstance(raw, dict) or not isinstance(raw.get("id"), str) or not raw["id"]:
        raise _fail(where, "a rule is not an object with a string id")
    rid = raw["id"]
    unknown = sorted(set(raw) - RULE_KEYS)
    if unknown:
        raise _fail(where, f"rule {rid}: unknown key(s) {', '.join(unknown)}")
    if not isinstance(raw.get("severity"), str) or raw["severity"] not in SEVERITY_TAG:
        raise _fail(where, f"rule {rid}: severity must be high or medium")
    kind = raw.get("kind")
    if kind not in ("text", "path"):
        raise _fail(where, f"rule {rid}: kind must be text or path")
    sources: Tuple[str, ...] = ()
    if kind == "text":
        if not _strings(raw.get("sources")) or not set(raw["sources"]) <= set(SOURCES):
            raise _fail(where, f"rule {rid}: sources must be a non-empty subset of {', '.join(SOURCES)}")
        sources = tuple(s for s in SOURCES if s in raw["sources"])
    for key in ("pattern", "description"):
        if not isinstance(raw.get(key), str) or not raw[key]:
            raise _fail(where, f"rule {rid}: {key} must be a non-empty string")
    try:
        regex = re.compile(raw["pattern"])
    except re.error as exc:
        raise _fail(where, f"rule {rid}: pattern does not compile: {exc}") from None
    rule = Rule(rid, raw["severity"], kind, sources, regex, raw["description"])
    for key, want in (("match", True), ("no_match", False)):
        if not _strings(raw.get(key)):
            raise _fail(where, f"rule {rid}: {key} needs at least one fixture")
        for fixture in raw[key]:
            if _matches(rule, fixture) != want:
                verb = "does not match" if want else "matches"
                raise _fail(where, f"rule {rid}: pattern {verb} its {key} fixture {fixture!r}")
    return rule


def _read_rule_file(path: str, builtin: bool) -> List[Rule]:
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        raise _fail(path, f"cannot load rules: {exc}") from None
    if not isinstance(doc, dict) or not isinstance(doc.get("rules"), list):
        raise _fail(path, "not an object with a rules list")
    unknown = sorted(set(doc) - FILE_KEYS[builtin])
    if unknown:
        raise _fail(path, f"unknown key(s) {', '.join(unknown)} — a project file only adds rules")
    if builtin and not doc["rules"]:
        raise _fail(path, "no rules in the built-in rule set")
    rules = [_parse_rule(raw, path) for raw in doc["rules"]]
    seen = set()
    for rule in rules:
        if rule.id in seen:
            raise _fail(path, f"rule {rule.id} is defined twice")
        seen.add(rule.id)
    return rules


def load_rules() -> List[Rule]:
    """The built-in rules, then the project's: added to, never redefined."""
    rules = _read_rule_file(BUILTIN_RULES, builtin=True)
    if os.path.exists(PROJECT_RULES):
        builtin_ids = {r.id for r in rules}
        for rule in _read_rule_file(PROJECT_RULES, builtin=False):
            if rule.id in builtin_ids:
                raise _fail(PROJECT_RULES, f"rule {rule.id} reuses a built-in id — project rules add, never redefine")
            rules.append(rule)
    return rules


# ── sources ──────────────────────────────────────────────────────────────────

def _git(*args: str) -> str:
    # Bytes, decoded by hand: text mode translates a lone `\r` into a line break,
    # and the normalisation must see it to scan what the carriage return hides.
    proc = subprocess.run(["git", *args], capture_output=True)
    if proc.returncode != 0:
        raise ScanError(f"git {' '.join(args)}: {proc.stderr.decode('utf-8', 'replace').strip() or 'failed'}")
    return proc.stdout.decode("utf-8", "replace")


def _commit(rev: str) -> str:
    if not rev or rev.startswith("-"):
        raise ScanError(f"not a revision: {rev!r}")
    return _git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}").strip()


def default_base(head: str) -> str:
    for name in ("origin/master", "origin/main", "origin/develop"):
        probe = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{name}^{{commit}}"],
                               capture_output=True, text=True)
        if probe.returncode == 0:
            return _git("merge-base", name, head).strip()
    raise ScanError("no origin/master, origin/main or origin/develop: pass --base")


def _unquote(path: str) -> str:
    if path.startswith('"') and path.endswith('"'):
        # git C-quotes a path holding a quote, a backslash or a control byte.
        return path[1:-1].encode("utf-8").decode("unicode_escape").encode("latin-1", "replace").decode("utf-8", "replace")
    return path


def diff_sources(base: str, head: str) -> Tuple[List[str], List[Tuple[str, List[Tuple[int, str]]]]]:
    """The changed paths, and the added lines of each file, in diff order."""
    paths = [p for p in _git("diff", "--no-renames", "--name-only", "-z", base, head).split("\0") if p]
    patch = _git("-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
                 "--no-renames", "--text", "-U0", "--inter-hunk-context=0",
                 "--src-prefix=a/", "--dst-prefix=b/", base, head)
    files: List[Tuple[str, List[Tuple[int, str]]]] = []
    current: Optional[List[Tuple[int, str]]] = None
    number = 0
    remaining = 0
    for line in patch.split("\n"):
        # Inside a zero-context hunk, every '+' is source, even '+++ b/...'.
        if remaining:
            if line.startswith("+"):
                if current is not None:
                    current.append((number, line[1:]))
                number += 1
                remaining -= 1
            continue
        if line.startswith("+++ "):
            target = _unquote(line[4:])
            current = None
            if target.startswith("b/") and target[2:] not in RULE_FILE_PATHS:
                current = []
                files.append((target[2:], current))
        elif line.startswith("@@"):
            found = HUNK_RE.match(line)
            if not found:
                raise ScanError(f"malformed diff hunk: {line}")
            number = int(found.group(1))
            remaining = int(found.group(2)) if found.group(2) is not None else 1
    return paths, files


def _call_strings(payload: object) -> Iterator[str]:
    if isinstance(payload, str):
        try:
            decoded = json.loads(payload)
        except ValueError:
            yield payload
            return
        if not isinstance(decoded, dict):
            yield payload
            return
        payload = decoded
    if isinstance(payload, dict):
        for key in ACTION_KEYS:
            value = payload.get(key)
            if isinstance(value, str):
                yield value
            elif isinstance(value, list) and all(isinstance(v, str) for v in value):
                yield " ".join(value)


def _actions(node: object) -> Iterator[str]:
    if isinstance(node, dict):
        # `type` is any JSON value in a record (a tool's input schema holds objects).
        if isinstance(node.get("type"), str) and node["type"] in TOOL_CALL_TYPES:
            for key in CALL_PAYLOAD_KEYS:
                if key in node:
                    yield from _call_strings(node[key])
                    return
            return
        for value in node.values():
            yield from _actions(value)
    elif isinstance(node, list):
        for value in node:
            yield from _actions(value)


def transcript_lines(path: str) -> List[Tuple[int, str]]:
    """Normalised lines of what a transcript's tool calls did, by record number.

    A JSONL transcript yields its tool calls' commands and paths; a record that
    is not JSON (a truncated last line, while the session is still writing) is
    scanned as raw text, never dropped. Any other file is scanned line by line.
    """
    try:
        with open(path, encoding="utf-8", errors="replace", newline="") as fh:
            records = fh.read().split("\n")
    except OSError as exc:
        raise ScanError(f"transcript {path}: {exc.strerror or exc}") from None
    first = next((r for r in records if r.strip()), "")
    if not (path.endswith(".jsonl") or first.lstrip().startswith("{")):
        return logical_lines(enumerate(records, 1))
    out: List[Tuple[int, str]] = []
    for number, record in enumerate(records, 1):
        if not record.strip():
            continue
        try:
            parsed = json.loads(record)
        except ValueError:
            out.extend(logical_lines([(number, record)]))
            continue
        for action in _actions(parsed):
            out.extend(logical_lines([(number, action)]))
    return out


def resolve_transcripts(values: Sequence[str]) -> List[str]:
    """`auto` is the running Claude Code session and its sub-agents, or nothing."""
    paths: List[str] = []
    for value in values:
        if value != "auto":
            paths.append(value)
            continue
        sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
        if not sid:
            continue
        if not SESSION_ID_RE.match(sid):
            raise ScanError(f"CLAUDE_CODE_SESSION_ID is not a session id: {sid!r}")
        root = glob.escape(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude"))
        paths += sorted(glob.glob(os.path.join(root, "projects", "*", sid + ".jsonl")))
        paths += sorted(glob.glob(os.path.join(root, "projects", "*", sid, "subagents", "*.jsonl")))
    return paths


# ── scan ─────────────────────────────────────────────────────────────────────

def _evidence(text: str) -> str:
    clean = "".join(c if c.isprintable() else "?" for c in text.strip()).replace("`", "'")
    return clean if len(clean) <= EXCERPT_MAX else clean[: EXCERPT_MAX - 1] + "…"


def _text_hits(rules: Sequence[Rule], source: str, location: str, lines: Iterable[Tuple[int, str]]) -> Iterator[Hit]:
    active = [r for r in rules if r.kind == "text" and source in r.sources]
    for number, text in lines:
        for rule in active:
            if rule.regex.search(text):
                yield Hit(location, number, rule.id, rule.severity, rule.description, _evidence(text))


def scan(rules: Sequence[Rule], base: str, head: str, transcripts: Sequence[str]) -> List[Hit]:
    hits: List[Hit] = []
    paths, files = diff_sources(base, head)
    for rule in (r for r in rules if r.kind == "path"):
        hits += [Hit(f"diff:{p}", 0, rule.id, rule.severity, rule.description, _evidence(p))
                 for p in paths if rule.regex.search(p)]
    for path, added in files:
        hits += _text_hits(rules, "diff", f"diff:{path}", logical_lines(added))
    for path in transcripts:
        hits += _text_hits(rules, "transcript", f"transcript:{path}", transcript_lines(path))
    unique = {}
    for hit in sorted(hits):
        unique.setdefault((hit.location, hit.line, hit.rule_id), hit)
    return list(unique.values())


def render(hit: Hit) -> str:
    where = f"{hit.location}:{hit.line}" if hit.line else hit.location
    tag = f"[{SEVERITY_TAG[hit.severity]} | confidence: 75 | autofix_class: manual | owner: human]"
    return f"{tag} {where} — {hit.rule_id}: {hit.description}\n  evidence: `{hit.evidence}`"


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Deterministic scan of an unattended push.")
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("scan", help="scan the diff and the transcripts; exit 1 on a high hit")
    run.add_argument("--base", help="diff base (default: merge base with origin/master|main|develop)")
    run.add_argument("--head", default="HEAD", help="diff head (default: HEAD)")
    run.add_argument("--transcript", action="append", default=[], help="a transcript file, or auto")
    sub.add_parser("selftest", help="load every rule and prove its fixtures")
    args = parser.parse_args(argv)

    rules = load_rules()
    if args.command == "selftest":
        print(f"unattended-scan: {len(rules)} rules proved against their fixtures")
        return 0
    head = _commit(args.head)
    base = _commit(args.base) if args.base else default_base(head)
    transcripts = resolve_transcripts(args.transcript)
    hits = scan(rules, base, head, transcripts)
    for hit in hits:
        print(render(hit))
    high = sum(1 for h in hits if h.severity == "high")
    print(f"unattended-scan: {high} high, {len(hits) - high} medium — diff {base[:7]}..{head[:7]}, "
          f"{len(transcripts)} transcript(s)")
    return 1 if high else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ScanError as error:
        print(f"unattended-scan: error: {error}", file=sys.stderr)
        sys.exit(2)
    except Exception:  # noqa: BLE001 — a crash must not read as exit 1 (a hit) or 0
        traceback.print_exc()
        sys.exit(2)
