#!/usr/bin/env python3
"""Non-pessimization candidates for /perf and /quality-gate (specs/perf-audit-and-debug.md).

Lists the wasted work a machine can spot, each at its exact `file:line`, for a
reviewer to confirm by reading the code:

* `n-plus-one`       — a query or remote call inside a loop: one round trip per item.
* `sequential-await` — an `await` inside a loop: each item waits for the last.
* `await-waterfall`  — consecutive awaits that do not use each other's results.

    scan.py [--format json|findings] <path ...>

Python is parsed with `ast`; JavaScript and TypeScript are scanned with strings
and comments masked and brackets matched. A candidate is a pattern match, so
`findings` prints it at confidence 50 — the reviewer reads it to raise it.
Exit 0 when the scan ran, 2 on a missing path.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from typing import Iterable, List, Optional, Set, Tuple

PY_SUFFIXES = (".py",)
JS_SUFFIXES = (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs")
SKIP_DIRS = {"node_modules", ".git", "dist", "build", ".venv", "venv", "__pycache__"}

WHY = {
    "n-plus-one": "a query or remote call inside a loop makes one round trip per item; batch it, join, or prefetch",
    "sequential-await": "an await inside a loop waits for each item in turn; start them together (gather / Promise.all) or batch",
    "await-waterfall": "consecutive awaits that do not use each other's results run one after another; run them concurrently",
}
FAILURE = {
    "n-plus-one": "with N items the path makes N + 1 round trips, so its time grows with the data instead of staying near one query",
    "sequential-await": "with N items the path waits N times the slowest call instead of about once",
    "await-waterfall": "the path takes the sum of the calls' latencies instead of the longest one",
}

# Python: method names that issue a query, and receivers whose get/post are remote.
PY_DB_METHODS = {
    "execute", "executemany", "query", "fetch", "fetchrow", "fetchval", "fetchone",
    "fetchall", "find_one", "filter_by", "scalar", "scalars", "aggregate", "raw",
}
PY_HTTP_RECEIVERS = {"requests", "httpx", "session", "client", "http"}
PY_HTTP_METHODS = {"get", "post", "put", "patch", "delete", "request"}
PY_ORM_METHODS = {"get", "filter", "exclude", "all", "first", "count"}
PY_BARE_CALLS = {"urlopen", "fetch"}

JS_QUERY_RE = re.compile(
    r"(?:\b(?:fetch|axios)\s*\(|\baxios\.(?:get|post|put|patch|delete|request)\s*\("
    r"|\.(?:query|execute|findOne|findUnique|findFirst|findMany|findById|findAll|aggregate|raw)\s*\()"
)
JS_LOOP_RE = re.compile(r"\b(?:for|while)\s*(?:await\s*)?\(")
JS_DO_RE = re.compile(r"\bdo\s*\{")
JS_CALLBACK_RE = re.compile(r"\.(?:forEach|map|flatMap|filter|reduce|some|every|find)\s*\(")
JS_AWAIT_RE = re.compile(r"\bawait\b")
JS_FOR_AWAIT_RE = re.compile(r"\bfor\s*$")
JS_AWAIT_STMT_RE = re.compile(r"^(\s*)(?:(?:const|let|var)\s+(.+?)\s*=\s*)?await\b(.*)$")
JS_IDENT_RE = re.compile(r"[A-Za-z_$][\w$]*")

Candidate = Tuple[str, int, str]


# --------------------------------------------------------------------------- python

def _dotted_tail(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id.lower()
    if isinstance(node, ast.Attribute):
        return node.attr.lower()
    if isinstance(node, ast.Call):
        return _dotted_tail(node.func)
    return ""


def _is_query_call(node: ast.Call) -> bool:
    func = node.func
    if isinstance(func, ast.Name):
        return func.id in PY_BARE_CALLS
    if not isinstance(func, ast.Attribute):
        return False
    receiver = _dotted_tail(func.value)
    if func.attr in PY_DB_METHODS:
        return True
    if func.attr in PY_HTTP_METHODS and receiver in PY_HTTP_RECEIVERS:
        return True
    return func.attr in PY_ORM_METHODS and receiver == "objects"


class _LoopVisitor(ast.NodeVisitor):
    """Calls and awaits that run once per iteration; nested functions reset the depth."""

    def __init__(self) -> None:
        self.depth = 0
        self.found: List[Tuple[int, str]] = []

    def _function(self, node) -> None:
        saved, self.depth = self.depth, 0
        self.generic_visit(node)
        self.depth = saved

    visit_FunctionDef = visit_AsyncFunctionDef = visit_Lambda = _function

    def _loop(self, node) -> None:
        self.visit(node.iter if hasattr(node, "iter") else node.test)
        self.depth += 1
        for stmt in node.body:
            self.visit(stmt)
        self.depth -= 1
        for stmt in node.orelse:
            self.visit(stmt)

    visit_For = visit_AsyncFor = visit_While = _loop

    def _comprehension(self, node) -> None:
        self.visit(node.generators[0].iter)
        self.depth += 1
        for index, generator in enumerate(node.generators):
            if index:
                self.visit(generator.iter)
            for condition in generator.ifs:
                self.visit(condition)
        for part in ("elt", "key", "value"):
            if hasattr(node, part):
                self.visit(getattr(node, part))
        self.depth -= 1

    visit_ListComp = visit_SetComp = visit_GeneratorExp = visit_DictComp = _comprehension

    def visit_Call(self, node: ast.Call) -> None:
        if self.depth and _is_query_call(node):
            self.found.append((node.lineno, "n-plus-one"))
        self.generic_visit(node)

    def visit_Await(self, node: ast.Await) -> None:
        if self.depth:
            self.found.append((node.lineno, "sequential-await"))
        self.generic_visit(node)


def _await_statement(stmt: ast.stmt) -> Optional[Tuple[ast.Await, Set[str]]]:
    """An `x = await f()` or `await f()` statement: the await and the names it binds."""
    value = getattr(stmt, "value", None)
    if not isinstance(value, ast.Await) or not isinstance(stmt, (ast.Assign, ast.AnnAssign, ast.Expr)):
        return None
    targets = stmt.targets if isinstance(stmt, ast.Assign) else [getattr(stmt, "target", None)]
    bound = {n.id for t in targets if t is not None for n in ast.walk(t) if isinstance(n, ast.Name)}
    return value, bound


def _python_waterfalls(tree: ast.AST) -> Iterable[Tuple[int, str]]:
    for node in ast.walk(tree):
        for field in ("body", "orelse", "finalbody"):
            block = getattr(node, field, None)
            if isinstance(block, list):
                yield from _waterfalls_in(block)


def _waterfalls_in(block: List[ast.stmt]) -> Iterable[Tuple[int, str]]:
    run: List[ast.stmt] = []
    bound: Set[str] = set()
    for stmt in block + [None]:
        found = _await_statement(stmt) if stmt is not None else None
        if found is not None:
            used = {n.id for n in ast.walk(found[0].value) if isinstance(n, ast.Name)}
            if run and not (used & bound):
                run.append(stmt)
                bound |= found[1]
                continue
        if len(run) >= 2:
            yield run[0].lineno, "await-waterfall"
        run, bound = ([stmt], set(found[1])) if found is not None else ([], set())


def scan_python(text: str) -> List[Tuple[int, str]]:
    tree = ast.parse(text)
    visitor = _LoopVisitor()
    visitor.visit(tree)
    return visitor.found + list(_python_waterfalls(tree))


# ----------------------------------------------------------------------- javascript

def _mask(text: str) -> str:
    """Strings, template literals and comments blanked to spaces; quotes and newlines kept."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i) or text.startswith("/*", i):
            close = "\n" if text[i + 1] == "/" else "*/"
            end = text.find(close, i + 2)
            end = n if end < 0 else end + (0 if close == "\n" else 2)
            start = i
        elif text[i] in "'\"`":
            quote, end = text[i], i + 1
            while end < n and text[end] != quote:
                end += 2 if text[end] == "\\" else 1
            start, end = i + 1, min(end, n)
        else:
            i += 1
            continue
        for k in range(start, end):
            if out[k] != "\n":
                out[k] = " "
        i = end + 1
    return "".join(out)


def _match(masked: str, start: int, open_ch: str, close_ch: str) -> int:
    depth = 0
    for k in range(start, len(masked)):
        if masked[k] == open_ch:
            depth += 1
        elif masked[k] == close_ch:
            depth -= 1
            if depth == 0:
                return k
    return len(masked)


def _js_regions(masked: str) -> Tuple[List[Tuple[int, int]], List[Tuple[int, int]]]:
    """(sequential loop bodies, callback spans) as character ranges."""
    sequential, callbacks = [], []
    for m in JS_LOOP_RE.finditer(masked):
        header_end = _match(masked, m.end() - 1, "(", ")")
        rest = header_end + 1
        while rest < len(masked) and masked[rest] in " \t\r\n":
            rest += 1
        if rest < len(masked) and masked[rest] == "{":
            sequential.append((rest, _match(masked, rest, "{", "}")))
        else:
            end = masked.find(";", rest)
            sequential.append((rest, len(masked) if end < 0 else end))
    for m in JS_DO_RE.finditer(masked):
        brace = m.end() - 1
        sequential.append((brace, _match(masked, brace, "{", "}")))
    for m in JS_CALLBACK_RE.finditer(masked):
        paren = m.end() - 1
        callbacks.append((paren, _match(masked, paren, "(", ")")))
    return sequential, callbacks


def _inside(offset: int, regions: List[Tuple[int, int]]) -> bool:
    return any(a <= offset <= b for a, b in regions)


def scan_javascript(text: str) -> List[Tuple[int, str]]:
    masked = _mask(text)
    sequential, callbacks = _js_regions(masked)
    line_of = lambda offset: masked.count("\n", 0, offset) + 1  # noqa: E731
    found = []
    for m in JS_QUERY_RE.finditer(masked):
        if _inside(m.start(), sequential + callbacks):
            found.append((line_of(m.start()), "n-plus-one"))
    for m in JS_AWAIT_RE.finditer(masked):
        if JS_FOR_AWAIT_RE.search(masked[max(0, m.start() - 12):m.start()]):
            continue
        if _inside(m.start(), sequential) and not _in_callback_within_loop(m.start(), sequential, callbacks):
            found.append((line_of(m.start()), "sequential-await"))
    found.extend(_js_waterfalls(masked.split("\n")))
    return found


def _in_callback_within_loop(offset, sequential, callbacks) -> bool:
    """An await in a callback nested inside the loop body belongs to the callback."""
    loops = [(a, b) for a, b in sequential if a <= offset <= b]
    inner_loop_start = max(a for a, _ in loops)
    return any(a <= offset <= b and a > inner_loop_start for a, b in callbacks)


def _js_waterfalls(lines: List[str]) -> Iterable[Tuple[int, str]]:
    run_start, indent, bound = None, None, set()
    length = 0
    for number, line in enumerate(lines + [""], start=1):
        m = JS_AWAIT_STMT_RE.match(line)
        if m and run_start is not None and m.group(1) == indent:
            used = set(JS_IDENT_RE.findall(m.group(3)))
            if not (used & bound):
                length += 1
                bound |= set(JS_IDENT_RE.findall(m.group(2) or ""))
                continue
        if length >= 2:
            yield run_start, "await-waterfall"
        if m:
            run_start, indent, length = number, m.group(1), 1
            bound = set(JS_IDENT_RE.findall(m.group(2) or ""))
        else:
            run_start, indent, length, bound = None, None, 0, set()


# ---------------------------------------------------------------------------- driver

def _files(paths: List[str]) -> Iterable[str]:
    for path in paths:
        if os.path.isfile(path):
            yield path
            continue
        for root, dirs, names in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(names):
                yield os.path.join(root, name)


def scan(paths: List[str]) -> dict:
    seen: Set[Candidate] = set()
    candidates, skipped = [], []
    for path in _files(paths):
        if not path.endswith(PY_SUFFIXES + JS_SUFFIXES):
            continue
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read()
            hits = scan_python(text) if path.endswith(PY_SUFFIXES) else scan_javascript(text)
        except (SyntaxError, UnicodeDecodeError, OSError) as error:
            skipped.append({"file": path, "reason": f"{type(error).__name__}: {error}"})
            continue
        lines = text.split("\n")
        for line, pattern in hits:
            key = (path, line, pattern)
            if key in seen:
                continue
            seen.add(key)
            candidates.append({
                "file": path, "line": line, "pattern": pattern,
                "evidence": lines[line - 1].strip(), "why": WHY[pattern],
            })
    candidates.sort(key=lambda c: (c["file"], c["line"], c["pattern"]))
    return {"candidates": candidates, "skipped": skipped}


def findings(result: dict) -> str:
    out = []
    for c in result["candidates"]:
        out.append(
            f"[SHOULD-FIX | confidence: 50 | autofix_class: manual | owner: agent] "
            f"{c['file']}:{c['line']} — {c['pattern']}: {c['why']}\n"
            f"  evidence: `{c['evidence']}` ({c['file']}:{c['line']})\n"
            f"  failure: {FAILURE[c['pattern']]}"
        )
    for s in result["skipped"]:
        out.append(f"skipped: {s['file']} — {s['reason']}")
    return "\n".join(out)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="scan.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--format", choices=("json", "findings"), default="json")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)
    missing = [p for p in args.paths if not os.path.exists(p)]
    if missing:
        print(f"scan.py: refused: no such path: {', '.join(missing)}", file=sys.stderr)
        return 2
    result = scan(args.paths)
    print(findings(result) if args.format == "findings" else json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
