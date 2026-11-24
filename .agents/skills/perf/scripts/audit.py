#!/usr/bin/env python3
"""The /perf audit report: schema, ranking, rendering and filing (specs/perf-audit-and-debug.md).

    audit.py validate <audit.json> [--repo <root>]
    audit.py render   <audit.json> [--repo <root>]
    audit.py file     <audit.json> [--repo <root>] [--apply]

An audit is one `perf-audit/1` JSON file. `validate` refuses anything that is
not evidence: a single-run or hand-typed number, a path without an expected
number, a web path without lab vitals labelled as lab data, a finding below
confidence 75 or without `file:line`. `render` prints the Markdown report with
findings ranked by impact x confidence / effort. `file` runs one
`task-registry upsert` per finding — a dry run unless `--apply`.

Exit 0 on success, 1 when a filing call fails, 2 on a refused audit.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure import Refused, check_summary  # noqa: E402

SCHEMA = "perf-audit/1"
PATH_KINDS = ("startup", "flow", "endpoint", "job", "web")
LAB_METRICS = ("lcp_ms", "inp_ms", "cls")
SCALE = (1, 2, 3)
CONFIDENCES = (75, 100)
REGISTRY = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "task-registry", "scripts", "task-registry.py"
)


# ---------------------------------------------------------------------------- validate

def _require(condition: bool, message: str) -> None:
    if not condition:
        raise Refused(message)


def _number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _check_path(path: dict) -> None:
    pid = path.get("id") or "<no id>"
    _require(bool(path.get("id")) and bool(path.get("name")), f"path {pid}: `id` and `name` are required")
    _require(path.get("kind") in PATH_KINDS, f"path {pid}: kind must be one of {', '.join(PATH_KINDS)}")
    _require(isinstance(path.get("measurement"), dict), f"path {pid}: no measurement")
    check_summary(path["measurement"], f"path {pid}")
    expected = path.get("expected")
    _require(
        isinstance(expected, dict) and _number(expected.get("value")) and expected["value"] > 0,
        f"path {pid}: no expected number — estimate how fast it should be before ranking it",
    )
    _require(bool(expected.get("basis")), f"path {pid}: the expected number needs its one-sentence basis")
    _require(
        expected.get("unit") == path["measurement"]["unit"],
        f"path {pid}: expected unit {expected.get('unit')!r} differs from the measured unit "
        f"{path['measurement']['unit']!r}",
    )
    if path["kind"] == "web":
        lab = path.get("lab")
        _require(isinstance(lab, dict), f"path {pid}: a web path needs a lab block (LCP, INP, CLS)")
        _require(
            lab.get("data") == "lab",
            f"path {pid}: lab block says data={lab.get('data')!r} — a lab trace is lab data, never field data",
        )
        for metric in LAB_METRICS:
            _require(_number(lab.get(metric)), f"path {pid}: lab block lacks {metric}")
        _require(bool(lab.get("backend")), f"path {pid}: lab block must name its backend")


def _check_finding(index: int, finding: dict, path_ids: set, repo) -> None:
    label = f"finding {index + 1} ({finding.get('title') or 'untitled'})"
    _require(bool(finding.get("title")), f"{label}: no title")
    _require(finding.get("path") in path_ids, f"{label}: unknown path {finding.get('path')!r}")
    _require(
        bool(finding.get("file")) and isinstance(finding.get("line"), int) and finding["line"] > 0,
        f"{label}: needs file:line",
    )
    _require(bool(finding.get("fix")), f"{label}: needs a suggested fix")
    _require(bool(finding.get("evidence")), f"{label}: needs its verbatim evidence line")
    for axis in ("impact", "effort"):
        _require(finding.get(axis) in SCALE, f"{label}: {axis} must be 1, 2 or 3")
    _require(
        finding.get("confidence") in CONFIDENCES,
        f"{label}: confidence must be 75 or 100 — a candidate below 75 belongs under `unverified`",
    )
    if repo is not None:
        target = os.path.join(repo, finding["file"])
        try:
            with open(target, "r", encoding="utf-8") as handle:
                lines = handle.read().split("\n")
        except OSError:
            lines = []
        _require(
            finding["line"] <= len(lines),
            f"{label}: {finding['file']}:{finding['line']} does not exist in {repo}",
        )


def validate(audit: dict, repo=None) -> None:
    _require(audit.get("schema") == SCHEMA, f"schema is {audit.get('schema')!r}, expected {SCHEMA!r}")
    for key in ("target", "date", "sha"):
        _require(bool(audit.get(key)), f"`{key}` is required")
    paths = audit.get("paths")
    _require(isinstance(paths, list) and paths, "no critical paths — an audit measures at least one")
    for path in paths:
        _check_path(path)
    ids = [p["id"] for p in paths]
    _require(len(ids) == len(set(ids)), "path ids must be unique")
    for index, finding in enumerate(audit.get("findings") or []):
        _check_finding(index, finding, set(ids), repo)


# ------------------------------------------------------------------------------ rank

def score(finding: dict) -> float:
    return finding["impact"] * finding["confidence"] / 100 / finding["effort"]


def gap(path: dict) -> float:
    return path["measurement"]["median"] / path["expected"]["value"]


def ranked(audit: dict) -> List[dict]:
    by_id = {p["id"]: p for p in audit["paths"]}
    return sorted(
        audit.get("findings") or [],
        key=lambda f: (-score(f), -gap(by_id[f["path"]]), f["file"], f["line"]),
    )


# ---------------------------------------------------------------------------- render

def _qty(value: float, unit: str) -> str:
    return f"{value:g} {unit}"


def render(audit: dict) -> str:
    paths = audit["paths"]
    by_id = {p["id"]: p for p in paths}
    out = [
        f"# Performance audit — {audit['target']}",
        "",
        f"Date {audit['date']} · commit `{audit['sha']}` · inventory: {audit.get('inventory_source') or 'none found'}",
        "",
        "Every number is the median of N runs of the command listed, with its min and spread; "
        "gap is measured median ÷ expected.",
        "",
        "## Critical paths",
        "",
        "| Path | Kind | Runs | Min | Median | Spread | Expected | Gap | Likely source |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for p in paths:
        m, unit = p["measurement"], p["measurement"]["unit"]
        out.append(
            f"| {p['name']} (`{p['id']}`) | {p['kind']} | {m['runs']} | {_qty(m['min'], unit)} | "
            f"{_qty(m['median'], unit)} | {_qty(m['spread'], unit)} | {_qty(p['expected']['value'], unit)} | "
            f"{gap(p):.1f}× | {p.get('source') or '—'} |"
        )
    out += ["", "Commands and estimates:", ""]
    for p in paths:
        out.append(f"- `{p['id']}`: `{p['measurement']['command']}` — expected: {p['expected']['basis']}")
    web = [p for p in paths if p["kind"] == "web"]
    if web:
        out += [
            "", "## Web vitals (lab data)", "",
            "Lab data: synthetic runs on one machine through the named backend — not field data from real users.",
            "", "| Path | LCP | INP | CLS | Long tasks | Bundle | Backend |", "|---|---|---|---|---|---|---|",
        ]
        for p in web:
            lab = p["lab"]
            bundle = f"{lab['bundle_bytes']} B" if lab.get("bundle_bytes") is not None else "—"
            out.append(
                f"| {p['name']} (`{p['id']}`) | {lab['lcp_ms']:g} ms | {lab['inp_ms']:g} ms | {lab['cls']:g} | "
                f"{lab.get('long_tasks', '—')} | {bundle} | {lab['backend']} |"
            )
    out += ["", "## Findings", ""]
    findings = ranked(audit)
    if not findings:
        out.append("Findings: none")
    else:
        out += [
            "Ranked by impact × confidence ÷ effort (impact and effort on 1–3).", "",
            "| Rank | Finding | Location | Path | Measured | Expected | Score | Suggested fix |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for rank, f in enumerate(findings, start=1):
            p = by_id[f["path"]]
            unit = p["measurement"]["unit"]
            out.append(
                f"| {rank} | {f['title']} | `{f['file']}:{f['line']}` | `{f['path']}` | "
                f"{_qty(p['measurement']['median'], unit)} | {_qty(p['expected']['value'], unit)} | "
                f"{score(f):.2f} | {f['fix']} |"
            )
    out += ["", "## Unverified", ""]
    unverified = audit.get("unverified") or []
    out += [f"- `{u.get('file')}:{u.get('line')}` — {u.get('reason')}" for u in unverified] or ["none"]
    out += ["", "## Coverage gaps", ""]
    out += [f"- {g}" for g in audit.get("coverage_gaps") or []] or ["none"]
    return "\n".join(out) + "\n"


# ------------------------------------------------------------------------------ file

def upsert_args(audit: dict, finding: dict) -> List[str]:
    path = {p["id"]: p for p in audit["paths"]}[finding["path"]]
    m, unit, expected = path["measurement"], path["measurement"]["unit"], path["expected"]["value"]
    where = f"{finding['file']}:{finding['line']}"
    severity = "MUST-FIX" if finding["impact"] == 3 else "SHOULD-FIX"
    return [
        "upsert", "--derive-id", "perf", "--source", finding["file"], "--fold-title",
        "--title", finding["title"],
        "--kind", "task", "--label", "performance", "--label", "now" if finding["impact"] == 3 else "next",
        "--summary",
        f"{path['name']}: measured {_qty(m['median'], unit)} median over {m['runs']} runs vs expected "
        f"{_qty(expected, unit)} ({gap(path):.1f}× gap); {finding['pattern']} at {where}",
        "--reproduction", m["command"],
        "--reproduction",
        f"observed: median {_qty(m['median'], unit)} over {m['runs']} runs (min {_qty(m['min'], unit)}, "
        f"spread {_qty(m['spread'], unit)}) / expected: {_qty(expected, unit)}",
        "--proposed-fix", finding["fix"],
        "--criterion", f"`measure.py compare` of `{m['command']}` against this baseline reports `improved`",
        "--criterion", f"the after median moves toward the expected {_qty(expected, unit)}",
        "--evidence",
        f"[{severity} | confidence: {finding['confidence']} | autofix_class: manual | owner: agent] "
        f"{where} — {finding['pattern']}: {finding['title']}",
        "--evidence", f"{finding['evidence']} ({where})",
        "--evidence", f"discovered: perf/audit {audit['date']} @ {audit['sha']}",
    ]


def file_findings(audit: dict, repo: str, apply: bool) -> int:
    findings = ranked(audit)
    if not findings:
        print("audit.py: Findings: none — nothing to file")
        return 0
    for finding in findings:
        argv = [sys.executable, os.path.normpath(REGISTRY)] + upsert_args(audit, finding) + ["--repo", repo]
        if apply:
            argv.append("--apply")
        done = subprocess.run(argv, capture_output=True, text=True)
        sys.stdout.write(done.stdout)
        if done.returncode != 0:
            sys.stderr.write(done.stderr)
            print(f"audit.py: filing {finding['file']}:{finding['line']} failed (exit {done.returncode})", file=sys.stderr)
            return 1
    return 0


# ------------------------------------------------------------------------------ main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="audit.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("cmd", choices=("validate", "render", "file"))
    parser.add_argument("audit")
    parser.add_argument("--repo", help="project root: checks file:line (validate) and is the registry root (file)")
    parser.add_argument("--apply", action="store_true", help="file: perform the writes (default: dry run)")
    args = parser.parse_args(argv)
    try:
        with open(args.audit, "r", encoding="utf-8") as handle:
            audit = json.load(handle)
        validate(audit, args.repo)
    except (OSError, ValueError) as error:
        print(f"audit.py: refused: {args.audit}: {error}", file=sys.stderr)
        return 2
    except Refused as error:
        print(f"audit.py: refused: {error}", file=sys.stderr)
        return 2
    if args.cmd == "render":
        sys.stdout.write(render(audit))
    elif args.cmd == "file":
        return file_findings(audit, args.repo or os.getcwd(), args.apply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
