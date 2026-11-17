#!/usr/bin/env python3
"""Unpaid native-runner routing proof in a namespace with only loopback."""
import argparse
from collections import Counter
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import tempfile
import threading
import urllib.request

MODEL = "claude-opus-5-5"


def child(root, plugin, binary, transport_only, relay_source, oauth, direct):
    root = Path(root)
    records = []
    admission_observations = []
    arranged_proof = {}
    private = root / "private.txt"
    private.write_text("synthetic private sentinel\n")
    prefix = "/" + secrets.token_urlsafe(24)

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            return

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                request = json.loads(body)
            except ValueError:
                request = {}
            records.append({"path": self.path, "model": request.get("model"),
                            "max_tokens": request.get("max_tokens"),
                            "header_names": sorted(self.headers.keys()),
                            "authorization_present": bool(self.headers.get("Authorization")),
                            "authorization_scheme": self.headers.get("Authorization", "").split(" ", 1)[0],
                            "visible_native_eval_paths": sorted(set(re.findall(r"/[^\s<>\"`']*claude-eval[^\s<>\"`']*",
                                json.dumps({"system": request.get("system"), "messages": request.get("messages")})))),
                            "top_level_keys": sorted(request), "body_bytes": len(body),
                            "tools": [{"name": tool.get("name"), "type": tool.get("type", "custom")}
                                      for tool in request.get("tools", [])],
                            "metadata_keys": sorted(request.get("metadata", {})),
                            "thinking_keys": sorted(request.get("thinking", {})),
                            "thinking_type": request.get("thinking", {}).get("type"),
                            "thinking_display": request.get("thinking", {}).get("display"),
                            "output_config": request.get("output_config", {}),
                            "context_management": request.get("context_management", {}),
                            "anthropic_beta": self.headers.get("anthropic-beta", ""),
                            "content_types": dict(Counter(block.get("type", "unknown") for message in request.get("messages", [])
                                                   for block in message.get("content", []) if isinstance(block, dict))),
                            "system_types": dict(Counter(block.get("type", "unknown") for block in request.get("system", [])
                                                  if isinstance(block, dict))),
                            "shell_marker_seen": any(block.get("type") == "tool_result" and not block.get("is_error", False)
                                and "harbor relay ready" in json.dumps(block.get("content", ""))
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict)),
                            "graphify_version_seen": any(block.get("type") == "tool_result"
                                and "0.9.109" in json.dumps(block.get("content", ""))
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict)),
                            "credential_hidden_seen": any(block.get("type") == "tool_result" and not block.get("is_error", False)
                                and "credential-hidden" in json.dumps(block.get("content", ""))
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict)),
                            "graph_query_seen": any(block.get("type") == "tool_result" and not block.get("is_error", False)
                                and "graph-query-ready" in json.dumps(block.get("content", ""))
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict)),
                            "bash_privacy_seen": any(block.get("type") == "tool_result" and not block.get("is_error", False)
                                and "privacy-hidden" in json.dumps(block.get("content", ""))
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict)),
                            "privacy_denials": [{"id": block.get("tool_use_id"), "is_error": block.get("is_error", False),
                                "denied_or_empty": bool(block.get("is_error", False)) or any(text in json.dumps(block.get("content", "")).lower()
                                    for text in ["no matches found", "no files found"]),
                                "private_sentinel_seen": not block.get("is_error", False) and "synthetic private sentinel" in json.dumps(block.get("content", ""))}
                                for message in request.get("messages", []) if message.get("role") == "user"
                                for block in message.get("content", []) if isinstance(block, dict) and block.get("type") == "tool_result"
                                and block.get("tool_use_id", "").startswith("toolu_private_")],
                            "request_sha256": hashlib.sha256(body).hexdigest()})
            if self.path.split("?", 1)[0] != prefix + "/v1/messages":
                self.send_error(404, "offline routing probe")
                return
            message = {"id": "msg_offline_probe", "type": "message", "role": "assistant",
                       "model": MODEL, "content": [], "stop_reason": None,
                       "stop_sequence": None, "usage": {"input_tokens": 1,
                       "output_tokens": 0, "cache_creation_input_tokens": 0,
                       "cache_read_input_tokens": 0}}
            events = [
                ("message_start", {"message": message}),
                ("content_block_start", {"index": 0, "content_block": {"type": "text", "text": ""}}),
                ("content_block_delta", {"index": 0, "delta": {"type": "text_delta", "text": "route probe completed"}}),
                ("content_block_stop", {"index": 0}),
                ("message_delta", {"delta": {"stop_reason": "end_turn", "stop_sequence": None}, "usage": {"output_tokens": 4}}),
                ("message_stop", {}),
            ]
            step = sum(record["model"] == MODEL for record in records)
            if not transport_only and step == 1:
                shell = "printf 'harbor relay ready\\n' && timeout 5 /home/joaosouto/.local/share/pipx/venvs/graphifyy/bin/graphify --version"
                if direct:
                    shell += " && timeout 20 graphify query settle_amount --budget 1500 >/dev/null && printf graph-query-ready"
                    shell += " && if [ -r " + shlex.quote(str(private)) + " ] || [ -r /tmp/harbor-workflow/evals/code-graph/fixture_gen.py ]; then printf privacy-visible; else printf privacy-hidden; fi"
                shell += " && if [ -z \"${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}\" ]; then printf credential-hidden; else printf credential-exposed; fi"
                events[1] = ("content_block_start", {"index": 0, "content_block":
                    {"type": "tool_use", "id": "toolu_offline_bash", "name": "Bash", "input": {}}})
                events[2] = ("content_block_delta", {"index": 0, "delta": {"type": "input_json_delta",
                    "partial_json": json.dumps({"command": shell})}})
                events[4][1]["delta"]["stop_reason"] = "tool_use"
            elif direct and step in {2, 3, 4, 5, 6, 7, 8, 9, 10, 11}:
                choices = {2: ("Grep", {"pattern": "settle_amount", "path": "billing", "output_mode": "content"}),
                           3: ("Read", {"file_path": str(root / "round/home/app/billing/amounts.py"), "offset": 130, "limit": 12}),
                           4: ("Read", {"file_path": str(private)}),
                           5: ("Grep", {"pattern": "synthetic private sentinel", "path": str(private), "output_mode": "content"}),
                           6: ("Glob", {"pattern": str(private)}),
                           7: ("Read", {"file_path": "/tmp/harbor-workflow/evals/code-graph/fixture_gen.py"}),
                           8: ("Grep", {"pattern": "CASES", "path": "/tmp/harbor-workflow/evals/code-graph/fixture_gen.py", "output_mode": "content"}),
                           9: ("Glob", {"pattern": "/tmp/harbor-workflow/evals/code-graph/fixture_gen.py"}),
                           10: ("Write", {"file_path": str(root / "round/package/protected.txt"), "content": "offline write probe"}),
                           11: ("Edit", {"file_path": str(private), "old_string": "synthetic private sentinel", "new_string": "tampered"})}
                name, arguments = choices[step]
                events[1] = ("content_block_start", {"index": 0, "content_block":
                    {"type": "tool_use", "id": ("toolu_private_" if step >= 4 else "toolu_offline_") + str(step), "name": name, "input": {}}})
                events[2] = ("content_block_delta", {"index": 0, "delta": {"type": "input_json_delta", "partial_json": json.dumps(arguments)}})
                events[4][1]["delta"]["stop_reason"] = "tool_use"
            elif direct:
                events[2][1]["delta"]["text"] = "billing/amounts.py settle_amount"
            data = "".join("event: " + kind + "\ndata: " + json.dumps({"type": kind, **value}) + "\n\n"
                           for kind, value in events).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    home = root / "host-home"
    config = home / ".claude"
    config.mkdir(parents=True)
    (root / "temporary").mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ANTHROPIC_", "CLAUDE_", "_CLAUDE_", "AWS_", "GOOGLE_", "OPENAI_", "EVAL_"))}
    env.update({"HOME": str(home), "CLAUDE_CONFIG_DIR": str(config),
                "TMPDIR": str(root / "temporary"), "CODE_GRAPH_ARM": "A",
                "ANTHROPIC_API_KEY": "offline-route-probe-fake-key",
                "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{server.server_port}{prefix}",
                "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096", "CLAUDE_CODE_MAX_RETRIES": "0",
                "DISABLE_COMPACT": "1", "CLAUDE_CODE_DISABLE_FAST_MODE": "1",
                "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1"})
    if oauth:
        del env["ANTHROPIC_API_KEY"]
        env.update({"CLAUDE_CODE_OAUTH_TOKEN": "sk-ant-oat01-offline-route-probe-not-real",
                    "CLAUDE_CODE_OAUTH_SCOPES": "user:inference user:profile",
                    "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL": "1"})
    if relay_source:
        tools = root / "tools"
        tools.mkdir()
        shutil.copyfile(relay_source, tools / "socat")
        (tools / "socat").chmod(0o755)
        env["PATH"] = str(tools) + os.pathsep + env["PATH"]
    granted = ["Edit", "Write"] if transport_only else ["Bash", "Edit", "Write"]
    command = [binary, "plugin", "eval", plugin, "--eval-dir", "evals/code-graph",
               "--case", "invoice-rounding", "--runs", "1", "--concurrency", "1",
               "--ablation", "none", "--scaffold", "--keep-temp",
               "--allow-tools", *granted, "--disallow-tools",
               "Agent", "Task", "WebSearch", "WebFetch", "--model", MODEL,
               "--max-cost-usd", "4", "--trust-plugin", "--no-publish",
               "--output-dir", str(root / "output"), "--json", str(root / "aggregate.json")]
    timeout = False
    try:
        if direct:
            import importlib.util
            source = Path(__file__).with_name("run-code-graph.py")
            spec = importlib.util.spec_from_file_location("commerce_runner", source)
            runner = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(runner)
            def opener(request):
                url = f"http://127.0.0.1:{server.server_port}{prefix}/v1/messages?beta=true"
                local = urllib.request.Request(url, data=request.data, headers=dict(request.header_items()))
                return urllib.request.urlopen(local, timeout=30)
            source_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source.parents[3], text=True).strip()
            run = runner.run_slot(root / "round", "B", "invoice-rounding", source_sha,
                                  "sk-ant-oat01-offline-route-probe-not-real", ["user:inference", "user:profile"],
                                  opener=opener, observer=admission_observations.append)
            stdout = (root / "round/out/trace.jsonl").read_bytes()
            stderr = (root / "round/out/stderr.log").read_bytes()
            exit_code = run["exitCode"]
            command = runner.native_command(root / "round")
            if run["status"] == "completed":
                arranger = source.parents[3] / ".agents/skills/eval/scripts/arrange-plugin-eval-results.py"
                arranged = subprocess.run(["/usr/bin/python3", str(arranger), str(root / "round"),
                    str(root / "round/out/aggregate.json"), "--arm", "B", "--out", str(root / "arranged")], capture_output=True, text=True)
                selected = root / "arranged/B/invoice-rounding/run-1"
                arranged_proof = {"exit_code": arranged.returncode, "stderr": arranged.stderr[-500:],
                    "transcript_present": (selected / "transcript.jsonl").is_file(),
                    "outcome": json.loads((selected / "outcome.json").read_text()) if (selected / "outcome.json").exists() else None}
        else:
            run = subprocess.run(command, cwd=root, env=env, capture_output=True, timeout=100)
            exit_code, stdout, stderr = run.returncode, run.stdout, run.stderr
    except subprocess.TimeoutExpired as exc:
        timeout = True
        exit_code, stdout, stderr = None, exc.stdout or b"", exc.stderr or b""
    finally:
        server.shutdown()
        server.server_close()
    (root / "stdout.log").write_bytes(stdout)
    (root / "stderr.log").write_bytes(stderr)
    receipt = {"label": "unpaid mock transport probe; excluded from planned runs",
               "interfaces": socket.if_nameindex(), "external_network": "unshared namespace; loopback only",
               "fake_credentials_only": True, "upstream_connections": 0,
               "auth_mode": "fake OAuth bearer" if oauth else "fake API key",
               "synthetic_usage_only": True, "paid_cost_usd": 0,
               "requested_model": MODEL, "requests": records, "native_exit_code": exit_code,
               "admission_observations": admission_observations,
               "unchanged_arranger_proof": arranged_proof,
               "runner": "direct CLI fallback" if direct else "native plugin eval",
               "timeout": timeout, "artifact_root": str(root),
               "command": command, "shell_granted": not transport_only,
               "task_local_relay": bool(relay_source),
               "shell_execution_proven": any(record["shell_marker_seen"] for record in records),
               "graphify_version_proven": any(record["graphify_version_seen"] for record in records),
               "credential_hidden_proven": any(record["credential_hidden_seen"] for record in records),
               "graph_query_proven": any(record["graph_query_seen"] for record in records),
               "bash_privacy_proven": any(record["bash_privacy_seen"] for record in records),
               "socat_available": shutil.which("socat") is not None, "output_tokens_cap": 4096,
               "routing_proven": any(record["model"] == MODEL and record["path"].split("?", 1)[0] == prefix + "/v1/messages"
                                     for record in records)}
    if direct and records:
        privacy = records[-1]["privacy_denials"]
        receipt["native_privacy_proven"] = len(privacy) == 8 and all(row["denied_or_empty"] and not row["private_sentinel_seen"] for row in privacy)
        receipt["neutral_startup_paths_proven"] = not records[0]["visible_native_eval_paths"]
        receipt["private_marker_unchanged"] = private.read_text() == "synthetic private sentinel\n"
        receipt["package_write_blocked"] = not (root / "round/package/protected.txt").exists()
    (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))
    success = receipt["routing_proven"] and (transport_only or receipt["shell_execution_proven"])
    if direct:
        success = success and receipt.get("native_privacy_proven") and receipt.get("neutral_startup_paths_proven") and arranged_proof.get("exit_code") == 0
    return 0 if success else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin", default="/tmp/harbor-workflow")
    parser.add_argument("--binary", default="/home/joaosouto/.local/share/claude/versions/2.1.325")
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--inside", type=Path)
    parser.add_argument("--transport-only", action="store_true")
    parser.add_argument("--relay", type=Path)
    parser.add_argument("--root-parent", type=Path)
    parser.add_argument("--root-prefix", default="harbor-route-")
    parser.add_argument("--oauth", action="store_true")
    parser.add_argument("--direct", action="store_true")
    args = parser.parse_args()
    if args.inside:
        return child(args.inside, args.plugin, args.binary, args.transport_only, args.relay, args.oauth, args.direct)
    root = Path(tempfile.mkdtemp(prefix=args.root_prefix, dir=args.root_parent))
    inner = ["bwrap", "--unshare-user", "--uid", str(os.getuid()), "--gid", str(os.getgid()),
             "--ro-bind", "/", "/", "--bind", str(root), str(root), "--dev", "/dev", "--proc", "/proc",
             "/usr/bin/python3", str(Path(__file__).resolve()), "--inside", str(root),
             "--plugin", args.plugin, "--binary", args.binary]
    setup = ("import fcntl,os,socket,struct,sys; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); "
             "fcntl.ioctl(s,0x8914,struct.pack('16sH14s',b'lo',0x49,b'')); s.close(); "
             "os.execvp(sys.argv[1],sys.argv[1:])")
    command = ["bwrap", "--unshare-user", "--unshare-net", "--uid", "0", "--gid", "0",
               "--cap-add", "CAP_NET_ADMIN", "--cap-add", "CAP_SETFCAP", "--ro-bind", "/", "/", "--bind", str(root), str(root),
               "--dev", "/dev", "--proc", "/proc", "/usr/bin/python3", "-c", setup, *inner]
    if args.transport_only:
        command.append("--transport-only")
    if args.relay:
        command.extend(["--relay", str(args.relay.resolve())])
    if args.oauth:
        command.append("--oauth")
    if args.direct:
        command.append("--direct")
    result = subprocess.run(command, capture_output=True, text=True, timeout=230 if args.direct else 115)
    receipt_path = root / "receipt.json"
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text())
    else:
        receipt = {"routing_proven": False, "namespace_exit_code": result.returncode,
                   "namespace_error": result.stderr[-2000:], "artifact_root": str(root)}
    if args.receipt:
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
