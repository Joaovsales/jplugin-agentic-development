#!/bin/bash
# grade-code-graph.py: transcript metrics and the frozen six-rule decision.
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
SCRIPTS="$(under_test .agents/skills/eval/scripts)"
GRADER="$SCRIPTS/grade-code-graph.py"
assert_file_exists "$GRADER" "code graph grader exists"
if [ ! -f "$GRADER" ]; then finish; exit $?; fi

"$TEST_PYTHON" - "$GRADER" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

grader = str(Path(sys.argv[1]).resolve())

def transcript(tokens, seconds, graph=True):
    calls = [
        {"type": "tool_use", "id": "g", "name": "Bash", "input": {"command": "timeout 20 graphify query 'billing' --budget 1500" if graph else "echo graphify"}},
        {"type": "tool_use", "id": "s", "name": "mcp__serena__find_symbol" if graph else "Bash", "input": {"command": "echo plain"}},
        {"type": "tool_use", "id": "n", "name": "Grep", "input": {"pattern": "billing"}},
        {"type": "tool_use", "id": "o", "name": "Glob", "input": {"pattern": "*.py"}},
        {"type": "tool_use", "id": "r", "name": "Read", "input": {"file_path": "billing.py"}},
        {"type": "tool_use", "id": "p", "name": "Bash", "input": {"command": "command -v graphify"}},
    ]
    start = {"type": "assistant", "timestamp": "2026-11-15T10:00:00Z", "message": {"id": "m1", "usage": {"input_tokens": tokens, "output_tokens": 0}, "content": calls}}
    # The shared parser deduplicates this repeated turn and ignores API blobs.
    blob = dict(start, type="api-request-blob")
    end = {"type": "system", "timestamp": f"2026-11-15T10:{seconds//60:02}:{seconds%60:02}Z", "subtype": "stop"}
    return [start, copy.deepcopy(start), blob, end]

def make(root, failure=None):
    for arm in ("A", "B", "D"):
        for case, kind in (("invoice-route", "localization"), ("shipment-flow", "localization"), ("config-label", "control")):
            for n in range(1, 4):
                run = root / arm / case / f"run-{n}"
                run.mkdir(parents=True)
                tokens = 800 if arm == "B" else 1000
                seconds, outcome = 100, 1
                graph = arm != "A"
                if failure == 1 and arm == "B" and kind == "localization" and n == 1:
                    outcome = 0
                if failure == 2 and arm == "B" and kind == "localization": tokens = 900
                if failure == 3 and arm == "B" and kind == "control": tokens = 1200
                if failure == 4 and arm == "B": graph = False
                if failure == 5 and arm == "B": seconds = 131
                if failure == 6 and arm == "D" and kind == "localization": tokens = 1200
                rows = transcript(tokens, seconds, graph)
                (run / "transcript.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
                (run / "outcome.json").write_text(json.dumps({"score": outcome}))
                (run / "metadata.json").write_text(json.dumps({"kind": kind, "seed": n, "status": "completed", "cost_usd": 0.5}))

def invoke(root, as_json=True):
    args = [sys.executable, grader, str(root), "--control", "A", "--arm", "B", "--degraded", "D"]
    if as_json: args.append("--json")
    return subprocess.run(args, text=True, capture_output=True)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    good = root / "good"
    make(good)
    result = invoke(good)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["verdict"] == "go", data
    row = next(r for r in data["runs"] if r["arm"] == "B")
    assert (row["graph_calls"], row["lsp_calls"], row["grep_calls"], row["glob_calls"], row["read_calls"]) == (1, 1, 1, 1, 1), row
    assert (row["total_tokens"], row["wall_seconds"]) == (800, 100), row
    plain = next(r for r in data["runs"] if r["arm"] == "A")
    assert plain["graph_calls"] == 0, "echo graphify is not a graph invocation"
    pair = next(r for r in data["paired_means"] if r["arm"] == "B" and r["case"] == "invoice-route")
    assert pair["runs"] == 3 and pair["total_tokens"] == 800 and pair["outcome"] == 1, pair
    assert data["total_spend_usd"] == 13.5, data
    text = invoke(good, False)
    assert "Verdict: go" in text.stdout and "Paired per-case means" in text.stdout, text.stdout
    print("ok: classified tools, deduplicated usage, paired means, spend and passing verdict")
    for failure in range(1, 7):
        path = root / f"rule-{failure}"
        make(path, failure)
        result = invoke(path)
        assert result.returncode == 0, result.stderr
        data = json.loads(result.stdout)
        assert data["verdict"] == "no-go" and data["failed_rules"] == [failure], data
        assert f"rule {failure}" in invoke(path, False).stdout, result.stdout
    print("ok: each of the six rules independently blocks go")
    extra = root / "extra"
    make(extra)
    for arm in ("A", "B", "D"):
        run = extra / arm / "invoice-route" / "run-4"
        run.mkdir()
        (run / "metadata.json").write_text(json.dumps({"kind": "localization", "seed": 4, "status": "errored", "cost_usd": 0.25}))
    data = json.loads(invoke(extra).stdout)
    assert data["verdict"] == "no-go" and not data["complete"], data
    print("ok: a fourth planned sample cannot yield go even when it errored")
    # Delegation counters add to parent usage, rather than replacing it.
    delegated = root / "delegated"
    make(delegated)
    run = delegated / "B" / "invoice-route" / "run-1"
    rows = transcript(800, 100)
    rows[0]["message"]["content"].append({"type": "tool_use", "id": "a", "name": "Agent", "input": {"prompt": "Find billing"}})
    rows.insert(-1, {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "a", "content": "done"}]}, "toolUseResult": {"status": "completed", "totalTokens": 100, "totalToolUseCount": 1}})
    (run / "transcript.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
    data = json.loads(invoke(delegated).stdout)
    row = next(r for r in data["runs"] if r["arm"] == "B" and r["case"] == "invoice-route" and r["run"] == "run-1")
    assert row["total_tokens"] == 900, row
    print("ok: total tokens include parent and delegated work")
    # The accuracy-lift branch of rule 2 uses percentage points, not fractions.
    for arm in ("A", "B"):
        for case in ("invoice-route", "shipment-flow"):
            for n in range(1, 4):
                run = good / arm / case / f"run-{n}"
                (run / "outcome.json").write_text(json.dumps({"score": 0.8 if arm == "A" else 0.9}))
                (run / "transcript.jsonl").write_text("".join(json.dumps(r) + "\n" for r in transcript(1100 if arm == "B" else 1000, 100)))
    assert json.loads(invoke(good).stdout)["verdict"] == "go"
    print("ok: ten-point accuracy lift permits the 1.10 cost bound")
    broken = good / "B" / "invoice-route" / "run-1"
    (broken / "transcript.jsonl").write_text("not JSON\n")
    assert invoke(good).returncode == 2
    print("ok: malformed transcript exits 2")
    # Errored planned runs remain visible, excluded from means and cannot yield go.
    (broken / "metadata.json").write_text(json.dumps({"kind": "localization", "seed": 1, "status": "errored", "cost_usd": 0.25}))
    (broken / "transcript.jsonl").unlink()
    (broken / "outcome.json").unlink()
    data = json.loads(invoke(good).stdout)
    assert data["verdict"] == "no-go" and data["errored_runs"]["B"] == 1 and not data["complete"], data
    print("ok: errored run is counted and prevents incomplete evidence from passing")
PY
rc=$?
assert_eq "0" "$rc" "code graph grader metrics, rule boundaries and invalid evidence"
finish
