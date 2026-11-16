"""Send one diff to the local reviewer with the fixed prompt; write the raw reply verbatim.

Usage: run_review.py <diff> <out> [effort]
  effort: the `reasoning_effort` the runbook tested (none | medium); default none.
Sampling is the GGUF's defaults, as in the runbook; only the seed is pinned.
"""
import json, sys, time, urllib.request
from pathlib import Path

ENDPOINT = "http://127.0.0.1:18081/v1/chat/completions"
here = Path(__file__).parent
diff_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
effort = sys.argv[3] if len(sys.argv) > 3 else "none"
body = {
    "messages": [{"role": "user", "content": (here / "prompt.txt").read_text() + diff_path.read_text()}],
    "reasoning_effort": effort, "seed": 42, "max_tokens": 8192,
}
req = urllib.request.Request(ENDPOINT, json.dumps(body).encode(), {"Content-Type": "application/json"})
t0 = time.time()
with urllib.request.urlopen(req, timeout=1500) as r:
    resp = json.load(r)
msg = resp["choices"][0]["message"]
meta = {"diff": diff_path.name, "reasoning_effort": effort, "wall_s": round(time.time() - t0, 1),
        "usage": resp.get("usage"), "timings": resp.get("timings"),
        "finish_reason": resp["choices"][0].get("finish_reason")}
out_path.write_text(
    "=== META ===\n" + json.dumps(meta, indent=1) + "\n"
    + "=== REASONING (verbatim) ===\n" + (msg.get("reasoning_content") or "") + "\n"
    + "=== REPLY (verbatim) ===\n" + (msg.get("content") or "") + "\n")
print(json.dumps({k: meta[k] for k in ("diff", "wall_s", "finish_reason")}), meta["usage"]["completion_tokens"])
