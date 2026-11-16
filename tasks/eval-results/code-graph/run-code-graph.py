#!/usr/bin/env python3
"""Blinded, sequential Claude Code runner; paid execution requires a committed protocol."""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import threading

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
MODEL = "claude-opus-5-5"
BINARY = "/home/joaosouto/.local/share/claude/versions/2.1.325"
BASE = "c7360e41fc0c466764b0bb4e32df6dd35d279b5b"
GRAPHIFY = "/home/joaosouto/.local/share/pipx/venvs/graphifyy/bin/graphify"
NATIVE_HASH = "0dc4f4a9a165fc60746d7ae8489712e5fc352f1e7ad4eb22e7141bd0812eb0cf"
OPERATIONAL = ["run-code-graph.py", "admission_gateway.py", "sandbox-relay.py"]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def command(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def utc():
    return datetime.now(timezone.utc).isoformat()


def save(path, data):
    temporary = path.with_suffix(path.suffix + ".new")
    with temporary.open("w") as stream:
        stream.write(json.dumps(data, indent=2) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def clean_env(root):
    env = {"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "SHELL": "/bin/bash", "TERM": "dumb",
           "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost"}
    env.update({"HOME": str(root / "home"), "CLAUDE_CONFIG_DIR": str(root / "config"),
                "TMPDIR": str(root / "scratch"), "CLAUDE_CODE_TMPDIR": str(root / "scratch"),
                "XDG_CONFIG_HOME": str(root / "home/.config"), "XDG_DATA_HOME": str(root / "home/.local/share"),
                "XDG_CACHE_HOME": str(root / "home/.cache"), "XDG_STATE_HOME": str(root / "home/.local/state"),
                "PATH": str(root / "tools") + ":/usr/local/bin:/usr/bin:/bin",
                "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096", "CLAUDE_CODE_MAX_RETRIES": "0",
                "DISABLE_COMPACT": "1", "CLAUDE_CODE_DISABLE_FAST_MODE": "1",
                "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1",
                "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
                "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL": "1"})
    return env


def prepare(root, arm, case, source):
    root.mkdir(parents=True, exist_ok=False)
    for directory in ["home/app", "config", "scratch", "tools", "package", "out"]:
        (root / directory).mkdir(parents=True)
    (root / "home/.bashrc").write_text("")
    package = root / "package"
    archive = subprocess.Popen(["git", "archive", source, ".claude-plugin", ".agents", "hooks"], cwd=REPO, stdout=subprocess.PIPE)
    unpack = subprocess.run(["tar", "-x", "-C", str(package)], stdin=archive.stdout, capture_output=True)
    archive.stdout.close()
    if archive.wait() or unpack.returncode:
        raise ValueError("immutable plugin archive failed")
    fixture = load("commerce_fixture", REPO / "evals/code-graph/fixture_gen.py")
    workspace = root / "home/app"
    fixture.generate(case, workspace)
    for name in [".gitignore", ".ignore"]:
        (workspace / name).write_text("graphify-out/\n")
    env = clean_env(root)
    env.update({"CODE_GRAPH_ARM": arm, "CODE_GRAPH_SEED": str(fixture.CASES[case]["seed"]),
                "CODE_GRAPH_REAL_GRAPHIFY": GRAPHIFY, "CODE_GRAPH_STUB_DIR": str(root / "tools")})
    shutil.copyfile(HERE / "sandbox-relay.py", root / "tools/socat")
    (root / "tools/socat").chmod(0o755)
    if arm == "A" and shutil.which("graphify", path=env["PATH"]):
        raise ValueError("control PATH unexpectedly contains graphify")
    if arm != "A":
        (root / "tools/graphify").write_text("#!/bin/sh\nexec " + shlex.quote(GRAPHIFY) + ' "$@"\n')
        (root / "tools/graphify").chmod(0o755)
    git = ["git", "-C", str(workspace), "-c", "core.hooksPath=/dev/null"]
    command(git + ["init", "-q"], env=env)
    command(git + ["add", "."], env=env)
    fixed = {**env, "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z"}
    command(git + ["-c", "user.name=Commerce", "-c", "user.email=commerce@localhost", "commit", "-qm", "Initialize services"], env=fixed)
    if arm != "A":
        command([GRAPHIFY, "update", "."], cwd=workspace, env=env, timeout=120)
    if arm == "D":
        shutil.copyfile(REPO / "evals/code-graph/stubs/graphify", root / "tools/graphify")
        (root / "tools/graphify").chmod(0o755)
        if fixture.CASES[case]["seed"] % 4 == 3:
            (workspace / "graphify-out/graph.json").write_text("{broken\n")
    for key in ["CODE_GRAPH_ARM", "CODE_GRAPH_STUB_DIR", "CODE_GRAPH_REAL_GRAPHIFY"]:
        env.pop(key, None)
    if arm != "D":
        env.pop("CODE_GRAPH_SEED", None)
    denied = [str(REPO), str(Path.home() / ".claude"), str(Path.home() / ".codex"),
              *[str(Path.home() / name) for name in [".ssh", ".aws", ".gnupg", ".kube"]],
              str(root / "config"), str(root / "out"), "/run/secrets", "/run/credentials", "/run/user"]
    host_home = Path.home()
    top = root.relative_to(host_home).parts[0]
    native_denied = denied + ["/tmp", "/var/tmp", "/dev/shm"]
    native_denied += [str(entry) for entry in host_home.iterdir() if entry.name != top]
    native_denied += [str(entry) for entry in (host_home / top).iterdir() if entry != root]
    forbidden = [tool + "(/" + value + suffix + ")" for value in native_denied
                 for suffix in ["", "/**"] for tool in ["Read", "Grep", "Glob", "Edit", "Write"]]
    forbidden += [tool + "(/" + str(value) + "/**)" for value in [package, root / "tools"] for tool in ["Edit", "Write"]]
    settings = {"permissions": {"deny": forbidden},
        "sandbox": {"enabled": True, "failIfUnavailable": True,
        "allowUnsandboxedCommands": False, "autoAllowBashIfSandboxed": False,
        "network": {"allowedDomains": []}, "filesystem": {
            "allowRead": ["/" + str(workspace), "/" + str(package), "/" + str(root / "tools"), "/" + str(root / "scratch"),
                          "/" + str(root / "home/.bashrc"),
                          "/" + str(Path(GRAPHIFY).parent.parent)],
            "denyRead": ["/" + value for value in denied + [str(host_home), "/tmp", "/var/tmp", "/dev/shm"]],
            "allowWrite": ["/" + str(workspace), "/" + str(root / "scratch")],
            "denyWrite": ["//tmp", "//var/tmp", "//dev/shm", "/" + str(package),
                          "/" + str(root / "config"), "/" + str(root / "out")]}}}
    (root / "config/settings.json").write_text(json.dumps(settings))
    return env, fixture.CASES[case]


def native_command(root):
    return [BINARY, "-p", "--output-format", "stream-json", "--verbose", "--max-turns", "30",
            "--max-budget-usd", "4", "--permission-mode", "dontAsk", "--setting-sources", "user",
            "--model", MODEL, "--plugin-dir", str(root / "package"), "--strict-mcp-config",
            "--tools", "Bash,Edit,Write,Read,Grep,Glob,Skill",
            "--mcp-config", '{"mcpServers":{}}', "--allowed-tools", "Bash", "Edit", "Write", "Read", "Grep", "Glob", "Skill",
            "--disallowed-tools", "Agent", "Task", "WebSearch", "WebFetch", "Bash(pip install:*)",
            "Bash(pip3 install:*)", "Bash(pipx install:*)", "Bash(pipx upgrade:*)",
            "Bash(python -m pip install:*)", "Bash(python3 -m pip install:*)"]


def grade(case, root, last_message):
    grades = []
    for path in sorted((REPO / "evals/code-graph" / case / "graders").glob("*.md")):
        head = path.read_text().split("---", 2)[1]
        fields = dict(re.findall(r"^[ \t]*([a-z_]+):[ \t]*(.+)$", head, re.M))
        if fields.get("type") != "regex" or fields.get("match") != "contains":
            raise ValueError("unsupported deterministic grader")
        text = last_message
        if fields.get("source") == "file":
            target = root / "home/app" / fields["path"]
            text = target.read_text() if target.is_file() else ""
        matched = bool(re.search(json.loads(fields["pattern"]), text))
        grades.append({"name": path.stem, "passed": matched, "weight": float(fields.get("weight", 1))})
    score = sum(row["weight"] for row in grades if row["passed"]) / sum(row["weight"] for row in grades)
    return score, grades


def run_slot(root, arm, case, source, oauth, scopes, opener=None, observer=None):
    env, info = prepare(root, arm, case, source)
    gateway_module = load("admission_gateway", HERE / "admission_gateway.py")
    gateway = gateway_module.Gateway(audit=str(root / "out/admission.jsonl"), opener=opener)
    if observer:
        original = gateway_module.admission
        def observe_admission(raw):
            try:
                return original(raw)
            except ValueError as error:
                body = json.loads(raw)
                cache_modes = []
                def collect(value):
                    if isinstance(value, dict):
                        if "cache_control" in value:
                            cache = value["cache_control"]
                            cache_modes.append({"keys": sorted(cache), **{key: cache[key] for key in ["type", "ttl", "scope"] if key in cache}})
                        for child in value.values():
                            collect(child)
                    elif isinstance(value, list):
                        for child in value:
                            collect(child)
                collect(body)
                observer({"reason": str(error), "top_keys": sorted(body),
                          "cache_modes": cache_modes,
                          "message_shapes": [{"keys": sorted(message), "role": message.get("role"),
                              "content_type": type(message.get("content")).__name__,
                              "block_shapes": [{"keys": sorted(block), "type": block.get("type")} for block in message.get("content", []) if isinstance(block, dict)]}
                              for message in body.get("messages", [])],
                          "diagnostics_shape": {key: ({"type": type(value).__name__, "keys": sorted(value)} if isinstance(value, dict)
                              else {"type": type(value).__name__}) for key, value in body.get("diagnostics", {}).items()},
                          "thinking": body.get("thinking"), "output_config": body.get("output_config"),
                          "context_management": body.get("context_management"),
                          "tools": [{"name": x.get("name"), "type": x.get("type"), "keys": sorted(x)} for x in body.get("tools", [])]})
                raise
        gateway_module.admission = observe_admission
        class ObservedHandler(gateway_module.Handler):
            def do_POST(self):
                observer({"beta_names": self.headers.get("anthropic-beta", "").split(",")})
                return super().do_POST()
        gateway.RequestHandlerClass = ObservedHandler
    thread = threading.Thread(target=gateway.serve_forever, daemon=True)
    thread.start()
    read_fd, write_fd = os.pipe()
    os.write(write_fd, oauth.encode() + b"\n")
    os.close(write_fd)
    env.update({"ANTHROPIC_BASE_URL": gateway.url, "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR": str(read_fd),
                "CLAUDE_CODE_OAUTH_SCOPES": " ".join(scopes)})
    prompt = (REPO / "evals/code-graph" / case / "prompt.md").read_text().split("---", 2)[2].strip()
    prompt += "\n\nKeep all work local; do not push or open pull requests."
    prompt += "\nDo not install or upgrade software."
    started = utc()
    try:
        result = subprocess.run(native_command(root), input=prompt, cwd=root / "home/app", env=env,
                                text=True, capture_output=True, timeout=600, pass_fds=(read_fd,))
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
        stdout = stdout.decode() if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode() if isinstance(stderr, bytes) else stderr
    finally:
        os.close(read_fd)
        gateway.shutdown()
        gateway.server_close()
    (root / "out/trace.jsonl").write_text(stdout)
    (root / "out/stderr.log").write_text(stderr)
    records = [json.loads(line) for line in stdout.splitlines() if line.strip().startswith("{")]
    final = next((row for row in reversed(records) if row.get("type") == "result"), {})
    score, graders = grade(case, root, final.get("result", ""))
    gateway_accounted = gateway.budget.spent + sum(gateway.budget.held.values(), Decimal(0))
    nominal = final.get("total_cost_usd")
    known_cost = type(nominal) in {int, float} and math.isfinite(nominal) and nominal >= 0
    cost = nominal if known_cost else float(gateway_accounted)
    accounted = max(gateway_accounted, Decimal(str(cost)))
    billing_breach = known_cost and Decimal(str(cost)) > gateway_accounted
    completed = code == 0 and final.get("subtype") == "success" and known_cost and not billing_breach and not gateway.budget.blocked and not gateway.budget.held
    run = {"score": score, "passed": score == 1, "turns": final.get("num_turns", 0),
           "costUsd": cost, "costSource": "native_cli" if known_cost else "accounted_upper_unknown_nominal",
           "judgeCostUsd": 0, "startedAt": started,
           "durationSeconds": final.get("duration_ms", 0) / 1000, "tracePath": str(root / "out/trace.jsonl"),
           "graders": graders, "status": "completed" if completed else "errored",
           "budgetAccountedUsd": str(accounted),
           "admissionBlocked": gateway.budget.blocked,
           "billingBreach": billing_breach, "gatewayAccountedUsd": str(gateway_accounted),
           "exitCode": code, "finishedAt": utc(), "kind": info["kind"], "seed": info["seed"]}
    aggregate = {"label": "runner-neutral aggregate derived from real CLI output and regex graders",
                 "cases": [{"name": case, "arms": {"with": [run]}}]}
    save(root / "out/aggregate.json", aggregate)
    return run


def protocol_commit(manifest):
    protocol = HERE / "protocol.md"
    content = protocol.read_bytes()
    if hashlib.sha256(content).hexdigest() != manifest["protocol_sha256"]:
        raise ValueError("registered protocol hash mismatch")
    relative = str(protocol.relative_to(REPO))
    commit = command(["git", "log", "-1", "--format=%H", "--", relative], cwd=REPO)
    if not commit:
        raise ValueError("protocol is not committed")
    saved = subprocess.run(["git", "show", commit + ":" + relative], cwd=REPO, capture_output=True, check=True).stdout
    if saved != content:
        raise ValueError("protocol is not committed")
    return commit


def slots():
    fixture = load("commerce_fixture", REPO / "evals/code-graph/fixture_gen.py")
    return [{"id": f"{arm}/{case}/{number}", "arm": arm, "case": case, "repetition": number,
             "seed": info["seed"], "kind": info["kind"]}
            for arm in ["A", "B", "D"] for case, info in fixture.CASES.items() for number in [1, 2, 3]]


def validate_manifest(manifest):
    if manifest.get("model") != MODEL or manifest.get("N") != 3 or manifest.get("slots") != slots():
        raise ValueError("manifest model, N, cases, seeds or slots changed")
    sources = manifest.get("sources", {})
    if set(sources) != {"A", "B", "D"} or sources["A"] != BASE or sources["B"] != sources["D"]:
        raise ValueError("unexpected arm source selection")
    for source in sources.values():
        if not re.fullmatch(r"[0-9a-f]{40}", source):
            raise ValueError("source must be an immutable commit ID")
        command(["git", "cat-file", "-e", source + "^{commit}"], cwd=REPO)
    if manifest.get("fixture_source") != BASE or manifest.get("native_sha256") != NATIVE_HASH:
        raise ValueError("fixture or native version pin changed")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", manifest.get("results_directory", "")):
        raise ValueError("results directory must be a local date")
    if manifest.get("operational_sha256") != {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest() for name in OPERATIONAL}:
        raise ValueError("operational source changed since registration")
    command(["git", "diff", "--exit-code", BASE, "--", "evals/code-graph"], cwd=REPO)
    if hashlib.sha256(Path(BINARY).read_bytes()).hexdigest() != NATIVE_HASH:
        raise ValueError("native binary changed since admission review")
    if command([GRAPHIFY, "--version"], timeout=5).split()[-1:] != ["0.9.109"]:
        raise ValueError("graph runtime pin mismatch")


def reserve_attempt(path, state, attempt):
    if state.get("pending"):
        raise ValueError("unresolved paid reservation; reconcile its audit before resuming")
    if Decimal(state["accounted_usd"]) + 4 > 320:
        raise ValueError("next run's $4 reservation exceeds total ceiling")
    state["pending"] = {**attempt, "reserved_usd": "4", "reserved_at": utc()}
    save(path, state)


def record_ledger(state, event, stage):
    path = REPO / "tasks/code-graph-run.md"
    text = re.sub(r"^State: .*$", "State: " + stage, path.read_text(), count=1, flags=re.M)
    text = re.sub(r"\nHALTED-NEEDS-USER\s*$", "\n", text)
    total = sum((Decimal(str(row["costUsd"])) for row in state["attempts"]), Decimal(0))
    text = re.sub(r"^- Cumulative evaluation spend: .*$", f"- Cumulative evaluation spend: ${total}", text, count=1, flags=re.M)
    protocol = event.get("protocol_commit", state["attempts"][-1]["protocol_commit"] if state["attempts"] else "pending")
    summary = f"- Paid runs: {len(state['attempts'])} charged attempts; pending reservation: ${4 if state.get('pending') else 0}; protocol commit: {protocol}"
    text = re.sub(r"^- Paid runs: .*$", summary, text, count=1, flags=re.M)
    text += "\n- Run receipt: " + json.dumps(event) + "\n"
    path.write_text(text)


def select_run(run, slot, results):
    selected = results / slot["arm"] / slot["case"] / ("run-" + str(slot["repetition"]))
    metadata = {"kind": run["kind"], "seed": run["seed"], "status": run["status"],
                "cost_usd": run["costUsd"], "cost_source": run["costSource"], "attempt_id": run["attempt_id"]}
    if selected.exists():
        if json.loads((selected / "metadata.json").read_text()) != metadata:
            raise ValueError("selected artifact collision; refusing overwrite")
        return
    root = Path(run["artifact_root"])
    staging = Path(tempfile.mkdtemp(prefix="arranged-", dir=root.parent))
    command(["python3", str(REPO / ".agents/skills/eval/scripts/arrange-plugin-eval-results.py"),
             str(root), str(root / "out/aggregate.json"), "--arm", slot["arm"], "--out", str(staging)])
    selected.parent.mkdir(parents=True, exist_ok=True)
    pending = Path(tempfile.mkdtemp(prefix=".slot-", dir=selected.parent)) / "run"
    shutil.copytree(staging / slot["arm"] / slot["case"] / "run-1", pending)
    save(pending / "metadata.json", metadata)
    pending.rename(selected)


def execute(manifest_path):
    manifest = json.loads(manifest_path.read_text())
    validate_manifest(manifest)
    commit = protocol_commit(manifest)
    state_path = HERE / "execution-state.json"
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    state = json.loads(state_path.read_text()) if state_path.exists() else {"attempts": [], "selected": {}, "accounted_usd": "0", "pending": None, "manifest_sha256": manifest_hash}
    if state.get("manifest_sha256") != manifest_hash:
        raise ValueError("manifest changed after execution began")
    if any(attempt["protocol_commit"] != commit for attempt in state["attempts"]):
        raise ValueError("registered protocol commit changed")
    if state.get("pending"):
        raise ValueError("unresolved paid reservation; inspect execution-state.json before resuming")
    if state.get("halt_reason"):
        raise ValueError(state["halt_reason"])
    results = HERE / manifest["results_directory"]
    for arm in ["A", "B", "D"]:
        while True:
            generation = state.setdefault("arm_generations", {}).get(arm, 0)
            arm_slots = [slot for slot in manifest["slots"] if slot["arm"] == arm]
            for slot in arm_slots:
                if slot["id"] in state["selected"]:
                    continue
                known = [row for row in state["attempts"] if row["id"] == slot["id"] and row["generation"] == generation]
                while not known or known[-1]["status"] == "errored" and len(known) < 2:
                    validate_manifest(manifest)
                    if protocol_commit(manifest) != commit:
                        raise ValueError("registered protocol commit changed")
                    root = Path(tempfile.mkdtemp(prefix="hr-", dir=Path.home())) / "round"
                    attempt = {**slot, "generation": generation, "attempt": len(known) + 1,
                               "attempt_id": f"{slot['id']}/{generation}/{len(known) + 1}",
                               "protocol_commit": commit, "source_sha": manifest["sources"][arm], "artifact_root": str(root)}
                    reserve_attempt(state_path, state, attempt)
                    record_ledger(state, state["pending"], "SMOKE" if not state["attempts"] else "RUNNING")
                    credentials = json.loads((Path.home() / ".claude/.credentials.json").read_text())["claudeAiOauth"]
                    run = {**run_slot(root, arm, slot["case"], attempt["source_sha"], credentials["accessToken"], credentials["scopes"]), **attempt}
                    raw_accounted = Decimal(run["budgetAccountedUsd"])
                    if run["costSource"] == "native_cli" and Decimal(str(run["costUsd"])) > raw_accounted:
                        run["billingBreach"] = True
                    run["budgetAccountedUsd"] = str(max(raw_accounted, Decimal(str(run["costUsd"]))))
                    save(root / "out/run-receipt.json", run)
                    state["attempts"].append(run)
                    state["accounted_usd"] = str(Decimal(state["accounted_usd"]) + Decimal(run["budgetAccountedUsd"]))
                    state["pending"] = None
                    if run["admissionBlocked"] or run.get("billingBreach") or Decimal(str(run["costUsd"])) > 4:
                        state["halt_reason"] = "admission assumptions failed; review the retained audit before resuming"
                    save(state_path, state)
                    record_ledger(state, run, "RUNNING")
                    known.append(run)
                    print(f"{run['attempt_id']} {run['status']} accounted=${state['accounted_usd']}", flush=True)
                    if state.get("halt_reason"):
                        raise ValueError(state["halt_reason"])
                run = known[-1]
                select_run(run, slot, results)
                state["selected"][slot["id"]] = run
                save(state_path, state)
                if slot["id"] == "A/invoice-rounding/1" and generation == 0:
                    projected = Decimal(state["accounted_usd"]) + Decimal(run["budgetAccountedUsd"]) * (90 - len(state["selected"]))
                    if projected > 320:
                        raise ValueError("smoke projection exceeds the $320 program ceiling")
            errors = sum(state["selected"][slot["id"]]["status"] == "errored" for slot in arm_slots)
            if errors <= 3:
                break
            if generation >= 1:
                raise ValueError("arm still exceeds 10% errors after its permitted rerun")
            archived = results / "attempts" / f"arm-{arm}-generation-{generation}"
            archived.parent.mkdir(parents=True, exist_ok=True)
            if archived.exists():
                raise ValueError("arm archive already exists; reconcile before retry")
            (results / arm).rename(archived)
            state["selected"] = {key: value for key, value in state["selected"].items() if not key.startswith(arm + "/")}
            state["arm_generations"][arm] = generation + 1
            save(state_path, state)
    record_ledger(state, {"selected_runs": len(state["selected"]), "accounted_usd": state["accounted_usd"]}, "GRADING")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=HERE / "run-manifest.json")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    if not args.execute:
        treatment = command(["git", "rev-parse", "HEAD"], cwd=REPO)
        save(args.manifest, {"model": MODEL, "N": 3, "protocol_sha256": None,
             "native_sha256": NATIVE_HASH, "fixture_source": BASE,
             "operational_sha256": {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest() for name in OPERATIONAL},
             "sources": {"A": BASE, "B": treatment, "D": treatment},
             "results_directory": "2026-11-16", "slots": slots()})
        print("Manifest prepared; paid execution remains disabled until protocol registration.")
        return
    with (HERE / "runner.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        execute(args.manifest)


if __name__ == "__main__":
    main()
