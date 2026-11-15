# Bonsai 2 on an RTX 3050 6GB Laptop — stock llama.cpp runbook and measured results

Measured 2026-11-15 on this machine. Every number in the *Measured* tables comes from a run
recorded under [`results/`](results/). Vendor figures appear only where labelled **vendor**.

## Verdict

| Question | Answer |
| --- | --- |
| Does Bonsai 2 27B `Q2_0` run on **stock** upstream llama.cpp (no PrismML fork)? | **Yes.** b12420 loads it, applies the Hadamard metadata (`loaded 402 Hadamard-folded weight(s)`), and greedy output is coherent. |
| Does it fit in VRAM at `-ngl 99`? | **No.** `cudaMalloc failed: out of memory` allocating 6921 MiB. At most 36 of 65 layers fit, and the rest decode on the CPU. |
| Was the 8–12 tok/s projection met for the 27B? | **No.** Measured generation is **~5 tok/s** (tg128 5.03 at best; 5.19 tok/s on the server at 32K). |
| Does any Bonsai option reach ≥ 10 tok/s here? | **Yes, but only models that fit entirely in VRAM:** Bonsai 27B v1 `Q1_0` at **20.3 tok/s** and Bonsai 2 9B `Q2_0` at **43.9 tok/s**. |
| Hardened container (native Docker, loopback only) | **Built and verified.** 27B v1 `Q1_0` generates at 20.1–20.3 tok/s in the container against 20.0 bare metal. See [Container](#container-hardened-llama-server-on-the-native-docker-engine). |
| Tool calling (5-prompt round-trip harness) | All three models emitted correct tool calls on 5/5 prompts in every run. The end-to-end scores and their caveats are in [Tool calling](#tool-calling-5-prompt-round-trip-harness). |

**Recommendation.** Don't use Bonsai 2 **27B** as the local tier on this GPU: partial offload holds
it at ~5 tok/s. Bonsai 27B v1 `Q1_0` (20 tok/s) and Bonsai 2 9B `Q2_0` (43 tok/s) are fast enough
and passed this small tool-call probe, but five prompts is a smoke test, not a capability
measurement. See [Limitations](#limitations).

## Environment

| Item | Value |
| --- | --- |
| GPU | NVIDIA GeForce RTX 3050 6GB Laptop GPU (sm_86), driver 580.178.04. llama.cpp reports 5804 MiB device memory. About 718 MiB was held by the Orca IDE node service throughout every run. |
| CPU / RAM | Intel Core 7 240H (10C/16T), 31 GiB. llama-bench used 6 threads (default). |
| llama.cpp | Upstream **ggml-org/llama.cpp release `b12420`**, `llama-cli --version` → `1.0.0-dev (build 12420, commit a68799c60)`, prebuilt `ubuntu-cuda-12.8-x64` (no local build; local nvcc 12.0 unused) |
| Release archives (sha256) | `llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz` `407f56eb…babca1d`; `cudart-llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz` `310a05b8…77f0f7b` |
| Install location | `~/opt/llama-b12420/llama-b12420/` (outside the repo and outside `~/venv`) |

### Model files (all verified: local sha256 == Hugging Face LFS oid)

| Model | Repo / file | Bytes | sha256 |
| --- | --- | ---: | --- |
| Bonsai 2 27B (target) | `prism-ml/Ternary-Bonsai-2-27B-gguf` / `Ternary-Bonsai-2-27B-Q2_0.gguf` | 7,626,008,928 | `4f99aed01b8a877e153f9aa6569a4440fe17c59701cc0953e36d7f460549e70e` |
| Bonsai 2 9B | `prism-ml/Ternary-Bonsai-2-9B-gguf` / `Ternary-Bonsai-2-9B-Q2_0.gguf` | 2,556,640,128 | `1f884aa56aacd2bbbb2e4b7abaead2b1102b74a9c75a23fc33dab916813a384d` |
| Bonsai 27B v1 | `prism-ml/Bonsai-27B-gguf` / `Bonsai-27B-Q1_0.gguf` | 3,803,452,480 | `17ef842e47450caeb8eaa3ebfbbab5d2f2278b62b79be107985fb69a2f819aa0` |

The fork-only packings `PQ2_0` and `PTQ1_0` were not downloaded, and the PrismML fork was not
cloned.

## Commands

```bash
# 1. Runtime: upstream release, CUDA 12.8 build plus its bundled cudart/cuBLAS
mkdir -p ~/opt/llama-b12420 && cd ~/opt/llama-b12420
gh release download b12420 -R ggml-org/llama.cpp \
  -p 'llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz' \
  -p 'cudart-llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz'
tar xzf llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz
tar xzf cudart-llama-b12420-bin-ubuntu-cuda-12.8-x64.tar.gz
cp --update=none cudart-llama-b12420-bin-ubuntu-cuda-12.8-x64/* llama-b12420/
export LD_LIBRARY_PATH=~/opt/llama-b12420/llama-b12420 BIN=~/opt/llama-b12420/llama-b12420
$BIN/llama-cli --version          # must report build >= 11556

# 2. Model
mkdir -p ~/models/bonsai2-27b && cd ~/models/bonsai2-27b
curl -L -o Ternary-Bonsai-2-27B-Q2_0.gguf \
  https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main/Ternary-Bonsai-2-27B-Q2_0.gguf
sha256sum Ternary-Bonsai-2-27B-Q2_0.gguf   # 4f99aed0…49e70e
M=~/models/bonsai2-27b/Ternary-Bonsai-2-27B-Q2_0.gguf

# 3. Load + greedy sanity check (no -ngl: let --fit pick the split; -lv 4 prints the load log)
$BIN/llama-completion -m $M -fa on -c 2048 -n 60 --temp 0 -no-cnv -lv 4 \
  -p "The capital of France is Paris. The capital of Japan is"

# 4. Bench: full offload first, then lower -ngl one value per run (an OOM aborts a multi-value run)
$BIN/llama-bench -m $M -p 512 -n 128 -ngl 99 -fa 1 -r 3
for ngl in 26 28 30 32 34 36; do $BIN/llama-bench -m $M -p 512 -n 128 -fa 1 -r 3 -ngl $ngl -o jsonl; done

# 5+6. Server (127.0.0.1 only, 32K ctx, q4_0 KV) + 400-token generation + tool-call harness.
#      The script starts llama-server, measures, runs the harness and stops the server on exit.
docs/bonsai-2-27b/serve_and_probe.sh <model.gguf> <out-dir> <ngl> none medium
#   which runs:
#   llama-server -m <model> --host 127.0.0.1 --port 18080 -c 32768 -ngl <ngl> -fa on \
#     --cache-type-k q4_0 --cache-type-v q4_0 -np 1 --jinja
```

[`serve_and_probe.sh`](serve_and_probe.sh) checks that the server listens on loopback only
(`results/*/listen.txt`: `127.0.0.1:18080`). The tool-call harness is
[`toolcall_harness.py`](toolcall_harness.py). It uses only the standard library and refuses any
non-loopback base URL.

## Measured: Bonsai 2 27B `Q2_0` (the target)

**Load on stock llama.cpp.** The file loads with no fork. It is a `qwen35` architecture with 64
blocks, and its tensors are 402 × `q2_0`, 96 × `bf16` and 353 × `f32`. The load log reports
`load_tensors_hadamard: loaded 402 Hadamard-folded weight(s)`. Greedy continuation of "The capital
of Japan is" → "Tokyo. The capital of Germany is Berlin. …", which is coherent.

**`-ngl 99`** fails with `cudaMalloc failed: out of memory` while allocating 6921.11 MiB on device
0 ([`results/bench-ngl99-oom.log`](results/bench-ngl99-oom.log)).

**Partial offload** (`llama-bench -p 512 -n 128 -fa 1 -r 3`, mean ± sd):

| `-ngl` | pp512 t/s | tg128 t/s |
| ---: | ---: | ---: |
| 26 | 189.59 ± 9.09 | 1.95 ± 0.19 |
| 28 | 211.93 ± 2.51 | 4.40 ± 0.57 |
| 30 | 244.67 ± 0.91 | 4.84 ± 0.23 |
| 32 | 247.32 ± 0.87 | 4.96 ± 0.13 |
| 34 | 244.39 ± 9.00 | 5.01 ± 0.15 |
| 36 | 251.35 ± 1.86 | **5.03 ± 0.28** |

`-ngl 37` and above were not tried after the coordinator's pivot. Generation is flat at about
5 tok/s from 30 layers up, so the CPU-resident share bounds decode, not the exact split. With
`--fit` at a 2048 context, the stock fit picked 29/65 layers: CUDA0 model buffer 3219.82 MiB, CPU
model buffer 4042.31 MiB, CUDA0 compute buffer 525 MiB.

**Server at 32K, q4_0 KV, `-ngl 30`.** The 400-token generation ran at **5.19 tok/s**. Prompt
processing on the 28-token prompt ran at 6.67 t/s. Whole-GPU memory in use was 4129 MiB, Orca
included ([`results/run-27b-v2/`](results/run-27b-v2/)).

## Measured: models that fit entirely in VRAM (`-ngl 99`)

| Model | Layers on GPU | CUDA0 model buf | Host model buf | pp512 t/s | tg128 t/s | Peak whole-GPU MiB (bench) | Server 32K q4_0: gen t/s (400 tok) | Server whole-GPU MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Bonsai 2 9B `Q2_0` | 33/33 | 2154.86 MiB | 272.81 MiB | 973.22 ± 7.64 | **43.95 ± 0.06** | 2949 | **42.94** | 2915 |
| Bonsai 27B v1 `Q1_0` | 65/65 | 3446.27 MiB | 170.51 MiB | 336.17 ± 0.77 | **20.32 ± 0.05** | 4305 | **20.01** (re-run: 19.90) | 4577 |

All repeating layers and the output head run on the GPU. The small host model buffer
(`CPU_Mapped`) is the token-embedding table, which stock llama.cpp keeps on the host. It is a row
lookup and not part of decode compute, so "nothing on the host" holds for the transformer layers
but not literally for every byte. The whole-GPU figures include about 718 MiB held by Orca. Both
models gave coherent greedy output. The 9B log also shows `loaded 202 Hadamard-folded weight(s)`.

## Tool calling: 5-prompt round-trip harness

Each prompt is a full round trip: an OpenAI-style `tools` request to llama-server → the model's
`tool_calls` → a canned tool result → the final answer. **Pass** requires both correct calls (names
plus arguments) and a final answer containing the tool-returned values. Reasoning is not echoed
back into later turns, per KNOWN_ISSUES. The prompts:

1. **single**: weather in Lisbon.
2. **select**: convert 250 USD→EUR, with three tools offered.
3. **parallel**: Paris and Tokyo, two calls.
4. **typed-args**: `create_event` with a date, an integer duration and an array of attendees. The answer must quote the returned `evt_7731`.
5. **chained**: `search_files` → `get_file_info` on the returned path.

| Model | Effort | 1 | 2 | 3 | 4 | 5 | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 27B v1 `Q1_0`, first run, harness v0 | none | PASS | PASS | PASS | FAIL¹ | FAIL² | 3/5 |
| 27B v1 `Q1_0` | none | PASS | PASS | PASS | PASS | PASS | 5/5 |
| 27B v1 `Q1_0` | medium | PASS | PASS | PASS | PASS³ | PASS | 5/5 |
| 9B v2 `Q2_0` | none | PASS | PASS | PASS | FAIL¹ | PASS | 4/5 |
| 9B v2 `Q2_0` | medium | PASS | PASS | PASS | PASS | PASS | 5/5 |
| **27B v2 `Q2_0`** (`-ngl 30`) | none | PASS | PASS | PASS | PASS | PASS | 5/5 |

1. The tool call was exactly correct, but the final answer did not quote the event id `evt_7731`.
   This is a strict answer check, kept as designed.
2. **Harness bug, fixed after this run.** The model answered `48,213 bytes` and the check expected
   `48213`. The harness now strips digit-group separators before matching, and every other row
   uses the fixed harness. The tool calls in this run were correct.
3. **Defect the harness does not penalise:** the model called `create_event` **twice** with
   identical arguments. With a real side-effecting tool, that books the meeting twice.

Every tool call across all runs was well-formed JSON with the right tool and arguments. No run
showed the malformed-call or `// // //` looping that KNOWN_ISSUES describes. Per-prompt calls,
answers, token counts and timings are in `results/run-*/toolcall-*.json`.

**Vendor figure, not measured here:** the model card reports BFCL v3 74.92 for Bonsai 2 27B against
76.74 for FP16. This harness is not BFCL and its results are not comparable to that score.

## Container: hardened llama-server on the native Docker engine

The service for the local tier. It runs on the **native** Docker engine (context `default`,
`unix:///var/run/docker.sock`), not the Docker Desktop VM, which is capped at 7.9 GB. GPU access
goes through nvidia-container-toolkit.

- [`container/Dockerfile`](container/Dockerfile) is a multi-stage build:
  - The fetch stage downloads the upstream `b12420` CUDA 12.8 release and **verifies its sha256**
    (`407f56eb…babca1d`).
  - The runtime stage is `nvidia/cuda:12.8.1-runtime-ubuntu24.04` plus `libgomp1`. The release
    links OpenMP and is built with GCC 13, which needs glibc 2.39.
  - **No model is baked in.**
- [`container/compose.yaml`](container/compose.yaml) is the hardened service definition.

**Why hardening is mandatory.** llama.cpp's HTTP API is unauthenticated by default, and the PrismML
documentation says its server `apiKey` is not checked. Published advisories include a Critical
unauthenticated RCE in the RPC backend and heap overflows in GGUF parsing. A malformed or hostile
GGUF is therefore a code-execution vector, and the container is the blast-radius boundary.

```bash
export DOCKER_CONTEXT=default
# Default model: Bonsai 27B v1 Q1_0 (best quality that fits entirely in VRAM, ~20 tok/s)
docker compose -f docs/bonsai-2-27b/container/compose.yaml up -d --build
# Fast alternative: Bonsai 2 9B Q2_0 (~43 tok/s)
BONSAI_MODEL_DIR=~/models/bonsai2-9b BONSAI_MODEL_FILE=Ternary-Bonsai-2-9B-Q2_0.gguf \
  docker compose -f docs/bonsai-2-27b/container/compose.yaml up -d
curl -s http://127.0.0.1:18080/health          # {"status":"ok"} once the model is loaded
docker compose -f docs/bonsai-2-27b/container/compose.yaml down
```

| Control | How it is applied | Verified in-container ([`results/container/verify.txt`](results/container/verify.txt)) |
| --- | --- | --- |
| Drop all capabilities | `cap_drop: [ALL]` | `CapInh/Prm/Eff/Bnd/Amb` all `0000000000000000` for PID 1 |
| No privilege escalation | `security_opt: no-new-privileges:true` | `NoNewPrivs: 1` |
| Non-root | `USER 10001:10001` in the image, `user:` in compose | `uid=10001(llama) gid=10001(llama)` |
| Read-only rootfs | `read_only: true`, plus `tmpfs /tmp` (64 MiB, `noexec,nosuid,nodev`) | `touch /x` and `touch /opt/llama/x` → `Read-only file system`; `/tmp` writable |
| Model read-only | bind mount with `read_only: true` | `/models ext4 ro`; `touch /models/x` → `Read-only file system` |
| Process cap | `pids_limit: 256` | `PidsLimit=256` |
| Memory cap | `mem_limit: 8g`, `memswap_limit: 8g` (no swap), and `--cache-ram 4096` in ENTRYPOINT | `Memory=8589934592 MemorySwap=8589934592`. The KV cache for the full 32K is allocated on the GPU at start, so a filled context does not grow host memory. The prompt cache is the one host-side growth path: its default of 8192 MiB equals the limit, hence the 4096 bound. |
| Loopback only | `ports: "127.0.0.1:18080:8080"` | host listener `127.0.0.1:18080` only; `/health` → 200 on loopback; refused (curl rc=7) on both host IPv4s, all four host IPv6s and every docker bridge gateway |
| Full offload or fail | `-ngl 99 --fit off` in ENTRYPOINT | GPU memory 4577 MiB in use, the same as the bare-metal full-offload server |
| Surface off | ENTRYPOINT `--no-webui --no-slots --no-ui-mcp-proxy --no-agent --offline`. `--rpc`, `--tools` (incl. `exec_shell_command`), `--mcp-servers-*`, `--models-dir` (router child-spawning), `--media-path`, `--slot-save-path`, `--props`, `--metrics` and `--connect` are never passed. | `/slots` 501, `/metrics` 501, `POST /props` 501, `/` (web UI) 404 |
| Service | `HEALTHCHECK` on `/health` (bash `/dev/tcp`, no curl in the image) and `restart: unless-stopped` | `healthy` about 9 s after start, and again about 9 s after `docker restart` |

The hardening flags are in the image ENTRYPOINT, so a compose `command:` override can replace only
the tunables (context, KV type, slots) and cannot *remove* a hardening flag. It can still **add**
flags such as `--tools` or `--rpc`, and so can `LLAMA_ARG_*` environment variables. The compose
file is therefore part of the trust boundary: review any change to its `command:` or
`environment:` as a security change. `GET /props` still answers 200 because it is read-only server
info.

**What the healthcheck proves.** `/health` returns 200 once the model is loaded: the process is up
and the weights are on the GPU. It does not prove that a generation succeeds. A generation probe
would compete with real requests for the single slot (`-np 1`) and time out behind long
completions, so a client should send a 1-token smoke request before relying on the service. The
Docker engine's `restart:` policy acts on **exit**, not on `unhealthy`. A wedged server that never
exits stays up and is reported `unhealthy`, but is not restarted.

The container's bridge address (`172.23.0.2:8080` on this run) is reachable **from this host**, as
any docker bridge is. It is not routed off the host, and the published port is loopback-only.

**Measured in the container** (default model 27B v1 `Q1_0`, 32K, q4_0 KV): three 400-token runs at
**20.28 / 20.11 / 20.12 tok/s**, against 20.01 and 19.90 bare metal. That is within ±2%, which this
laptop's run-to-run noise covers, so the container costs nothing measurable. Tool-call harness at
effort `none`: **4/5**. Every call was correct. Case 4 failed only the answer check: the model did
not quote `evt_7731`, the same pattern seen bare metal
([`results/container/`](results/container/)).

## Limitations

- **N=1 per prompt, five prompts.** Sampling uses the GGUF's defaults (not greedy), and case 4
  flipped between runs on the same model. A pass rate on five easy prompts can't show the
  agentic regressions reviewers report. Those show up in long multi-turn loops, many tools and
  ambiguous schemas, none of which this harness covers.
- **Effort levels.** `xhigh`, the model's default reasoning effort, was not tested, and the 27B v2
  was tested only at `none` because it runs at 5 tok/s. `none` and `medium` both keep reasoning
  short, so long-reasoning failure modes (empty or cut-off answers) were not exercised.
- **One harness change after seeing results.** The digit-separator normalisation is disclosed
  above, and the raw pre-fix run is kept in `results/run-27b-v1-raw/`. No other criterion changed.
- **Context.** The server allocated 32K with q4_0 KV, but every measurement used short prompts.
  Generation speed and quality with a filled 32K context were **not** measured. The
  `--cache-type-k/v q4_0` quality impact was not measured either.
- **Shared GPU and laptop thermals.** About 718 MiB of VRAM was held by Orca during all runs. The
  `-ngl 26` tg128 (1.95) is anomalously low against `-ngl 28` (4.40) and was not re-run to
  explain it. Treat single-digit-percent differences as noise.
- **Different models, not one model at different sizes.** The 9B and the 27B v1 are separate models
  with their own quality, and their benchmark standing was not measured here. 27B v1 `Q1_0` is the
  previous generation, not Bonsai 2.
- **No fork comparison.** By owner decision, `PQ2_0` and `PTQ1_0` on the PrismML fork were not
  measured. The vendor reports `PTQ1_0` at 5.95 GB, which is still larger than this GPU's free
  VRAM.
- No long-lived service was left running. Each bare-metal server ran only inside
  `serve_and_probe.sh` and was killed on exit, and the container was brought down
  (`compose down`) after verification.
- **Adoption gate not run.** Issue #407 gates adoption on `/eval` mode B, which shows no
  regression or else adoption is rejected. That eval was **not** run, because it dispatches
  sub-agents and this work was done by a dispatched worker that cannot. The container is built and
  verified, but adoption remains gated on that eval.
- The container's API has no authentication. Loopback publishing is the access control, so any
  local process or user on this host can call it.
