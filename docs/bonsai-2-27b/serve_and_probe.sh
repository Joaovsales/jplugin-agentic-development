#!/usr/bin/env bash
# Start llama-server on 127.0.0.1 (32K ctx, q4_0 KV), measure a 400-token generation,
# run the 5-prompt tool-call harness, then stop the server. Never leaves a service running.
# Usage: serve_and_probe.sh <model.gguf> <out-dir> [ngl] [effort...]
set -euo pipefail
MODEL=$1; OUT=$2; NGL=${3:-99}; shift 3 || true
EFFORTS=("${@:-none}")
BIN=${LLAMA_BIN:-$HOME/opt/llama-b12420/llama-b12420}
PORT=${PORT:-18080}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
export LD_LIBRARY_PATH=$BIN

"$BIN/llama-server" -m "$MODEL" --host 127.0.0.1 --port "$PORT" \
  -c 32768 -ngl "$NGL" -fa on --cache-type-k q4_0 --cache-type-v q4_0 \
  -np 1 --jinja > "$OUT/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; wait $SRV 2>/dev/null || true' EXIT

for _ in $(seq 1 180); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "server died"; tail -20 "$OUT/server.log"; exit 1; }
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || { echo "server not healthy"; exit 1; }
ss -ltnp 2>/dev/null | grep ":$PORT " | tee "$OUT/listen.txt"
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | tee "$OUT/vram.txt"

# Raw 400-token generation (ignore_eos guarantees length); server-side timings are the measurement.
curl -s "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' -d '{
  "prompt": "Write a detailed technical essay about how CPU caches work, covering cache lines, associativity, write policies, coherence protocols and prefetching.\n\n",
  "n_predict": 400, "ignore_eos": true, "temperature": 0.7, "cache_prompt": false}' > "$OUT/gen400.json"
python3 -I -c 'import json,sys; t=json.load(open(sys.argv[1]))["timings"]; print("gen400: predicted_n=%d predicted_per_second=%.2f prompt_n=%d prompt_per_second=%.2f" % (t["predicted_n"], t["predicted_per_second"], t["prompt_n"], t["prompt_per_second"]))' "$OUT/gen400.json" | tee "$OUT/gen400.txt"

for eff in "${EFFORTS[@]}"; do
  python3 -I "$HERE/toolcall_harness.py" --base "http://127.0.0.1:$PORT" --effort "$eff" \
    --max-tokens "${MAX_TOKENS:-8192}" --out "$OUT/toolcall-$eff.json" | tee "$OUT/toolcall-$eff.txt"
done
