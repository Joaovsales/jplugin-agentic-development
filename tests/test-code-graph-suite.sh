#!/bin/bash
# The navigation suite's cases, blinded fixtures and degraded CLI are reproducible.
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
SUITE="$(under_test evals)"/code-graph
assert_file_exists "$SUITE/fixture_gen.py" "code graph fixture generator exists"
assert_file_exists "$SUITE/stubs/graphify" "degraded graphify stub exists"
if [ ! -f "$SUITE/fixture_gen.py" ] || [ ! -f "$SUITE/stubs/graphify" ]; then finish; exit $?; fi

"$TEST_PYTHON" - "$SUITE" <<'PY'
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

suite = Path(sys.argv[1])
# Expected locations and seeds belong to the contract, outside the generated workspace.
expected_cases = {
    "invoice-rounding": ("localization", 101, "billing/amounts.py", "settle_amount"),
    "dispatch-callers": ("localization", 102, "gateway/queue.py", "enqueue_dispatch"),
    "currency-shape": ("localization", 103, "catalog/mapper.ts", "mapPrice"),
    "credit-flow": ("localization", 104, "ledger/bridge.py", "encode_credit"),
    "terms-failure": ("localization", 105, "billing/policy.py", "resolve_terms"),
    "status-rename": ("localization", 106, "notify/queue.py", "publish_alert"),
    "refund-balance": ("localization", 107, "orders/receipt.py", "apply_refund"),
    "readme-copy": ("control", 108, "README.md", ""),
    "profile-port": ("control", 109, "config/runtime.yaml", ""),
    "receipt-module": ("control", 110, "reporting/receipt.py", "format_receipt"),
}
directories = {path.parent.name: path.parent for path in suite.glob("*/case.yaml")}
assert set(directories) == set(expected_cases), sorted(directories)
cases = {}
for name, directory in directories.items():
    metadata = (directory / "case.yaml").read_text()
    declared_name = re.search(r"(?m)^name:\s*(.+)$", metadata).group(1).strip().strip("\"'")
    assert declared_name == name, (name, declared_name)
    tags = re.search(r"(?m)^tags:.*(?:\n[ \t]+.*)*", metadata).group(0)
    kinds = re.findall(r"\b(localization|control)\b", tags)
    kind, seed, target_file, target_symbol = expected_cases[name]
    assert kinds == [kind], (name, kinds)
    cases[name] = {"kind": kind, "seed": seed, "target_file": target_file,
                   "target_symbol": target_symbol, "scaffold": name == "receipt-module"}
assert sum(c["kind"] == "localization" for c in cases.values()) >= 7
assert sum(c["kind"] == "control" for c in cases.values()) >= 3
assert {c["seed"] % 4 for c in cases.values()} == {0, 1, 2, 3}
blocked = re.compile(r"(?<![A-Za-z0-9_])(eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena)(?![A-Za-z0-9_])", re.I)

def tree(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}

with tempfile.TemporaryDirectory() as scratch:
    root = Path(scratch)
    for name, case in cases.items():
        directory = directories[name]
        for relative in ("case.yaml", "prompt.md", "fixture.sh", "graders/outcome.md"):
            assert (directory / relative).is_file(), (name, relative)
        assert not blocked.search(name), name
        prompt = (directory / "prompt.md").read_text()
        assert not blocked.search(prompt), name
        assert "type: regex" in (directory / "graders/outcome.md").read_text(), name
        a, b = root / name / "a", root / name / "b"
        for out in (a, b):
            subprocess.run([sys.executable, str(suite / "fixture_gen.py"), name, "--out", str(out), "--arm", "A"], check=True)
        files = list(p for p in a.rglob("*") if p.is_file())
        assert len(files) >= 150, (name, len(files))
        assert sum(len(p.read_text().splitlines()) for p in files) >= 20000, name
        assert any(p.suffix == ".py" for p in files) and any(p.suffix == ".ts" for p in files), name
        assert tree(a) == tree(b), name
        for path in files:
            assert not blocked.search(str(path.relative_to(a))), (name, path)
            assert not blocked.search(path.read_text()), (name, path)
            if path.suffix == ".py":
                ast.parse(path.read_text(), filename=str(path))
        assert (a / case["target_file"]).is_file() or case.get("scaffold"), name
        if case["kind"] == "localization":
            source = (a / case["target_file"]).read_text()
            assert case["target_symbol"] in source, name
            if case["target_file"].endswith(".py"):
                function = next(n for n in ast.parse(source).body
                                if isinstance(n, ast.FunctionDef) and n.name == case["target_symbol"])
                namespace = {}
                exec(compile(ast.Module(body=[function], type_ignores=[]), name, "exec"), namespace)
                function = namespace[case["target_symbol"]]
                if name == "invoice-rounding":
                    assert function(2, 1099) == 2197
                elif name == "credit-flow":
                    assert function(1215)["minor"] == 12
                elif name == "terms-failure":
                    assert function("basic") is None
                elif name == "refund-balance":
                    assert function(1200, 300) == 1500
                elif name == "dispatch-callers":
                    namespace["dispatch_parcel"] = lambda parcel, region: (parcel, region)
                    try:
                        function("parcel", "local")
                    except TypeError:
                        pass
                    else:
                        raise AssertionError("remaining caller already supplies region")
                elif name == "status-rename":
                    namespace["pack_status"] = lambda status: {"state": status}
                    try:
                        function("ready")
                    except NameError:
                        pass
                    else:
                        raise AssertionError("old helper name is no longer present")
        pattern_text = (directory / "graders/outcome.md").read_text().split("pattern: ", 1)[1].splitlines()[0]
        pattern = json.loads(pattern_text)
        answer = case["target_file"] + " " + case.get("target_symbol", "")
        assert re.search(pattern, answer), (name, pattern)
        assert not re.search(pattern, "The issue is in an unrelated module."), name
    print("ok: case shape, minimum counts, fixture sizes, Python/TypeScript and byte determinism")
    print("ok: generated paths/content and organic prompts stay blinded; deterministic graders identify targets")

    for seed in range(4):
        work = root / f"fault-{seed}"
        work.mkdir()
        env = dict(os.environ, CODE_GRAPH_SEED=str(seed))
        for repeat in range(2):
            try:
                result = subprocess.run([sys.executable, str(suite / "stubs/graphify"), "query", "billing"],
                                        cwd=work, env=env, capture_output=True, text=True, timeout=0.3)
            except subprocess.TimeoutExpired:
                assert seed == 1, seed
            else:
                assert seed != 1, seed
                if seed == 0:
                    assert result.returncode == 1, result
                elif seed == 2:
                    assert result.returncode == 0 and not result.stdout, result
                else:
                    assert result.returncode == 0, result
                    try:
                        json.loads((work / "graphify-out/graph.json").read_text())
                    except ValueError:
                        pass
                    else:
                        raise AssertionError("corrupt mode wrote valid JSON")
    print("ok: all four degraded modes repeat deterministically from seed")
assert (suite / "rubric.md").is_file()
assert "Paid smoke: deferred" in (suite / "README.md").read_text()
assert "Arm C:" in (suite / "README.md").read_text()
PY
rc=$?
assert_eq 0 "$rc" "code graph suite inputs, outcome graders and degraded paths"
finish
