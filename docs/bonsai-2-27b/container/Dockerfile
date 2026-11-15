# Hardened llama-server image on stock upstream llama.cpp (no PrismML fork).
# No model is baked in: the GGUF is bind-mounted read-only at /models at runtime.

# --- fetch: download and verify the pinned upstream release --------------------------------
FROM ubuntu:24.04 AS fetch
ARG LLAMA_BUILD=b12420
ARG LLAMA_SHA256=407f56ebad7238f2d2d8a1895cbfb548204554824cc56a1a6381ff306babca1d
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/llama.tgz \
      "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD}/llama-${LLAMA_BUILD}-bin-ubuntu-cuda-12.8-x64.tar.gz" \
 && echo "${LLAMA_SHA256}  /tmp/llama.tgz" | sha256sum -c - \
 && mkdir /opt/llama \
 && tar -xzf /tmp/llama.tgz -C /opt/llama --strip-components=1 \
      --wildcards '*/llama-server' '*/lib*.so*' '*/LICENSE'

# --- runtime: CUDA 12.8 runtime (cudart + cuBLAS); driver 580 runs CUDA 12 builds ----------
# Ubuntu 24.04 because the release is built with GCC 13 (glibc 2.39).
FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04
COPY --from=fetch /opt/llama /opt/llama
# libgomp1: the release's CPU backends link OpenMP, absent from the CUDA runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 llama \
 && useradd --system --uid 10001 --gid llama --no-create-home --shell /usr/sbin/nologin llama
ENV LD_LIBRARY_PATH=/opt/llama \
    HOME=/tmp \
    LLAMA_CACHE=/tmp/llama-cache \
    LLAMA_ARG_MODEL=/models/Bonsai-27B-Q1_0.gguf
USER 10001:10001
EXPOSE 8080

# /health returns 200 only once the model is loaded. Bash /dev/tcp keeps curl out of the image.
HEALTHCHECK --interval=15s --timeout=5s --start-period=180s --retries=3 \
  CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /health HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && head -1 <&3 | grep -q ' 200 '"]

# Fixed, non-overridable flags (a compose `command:` replaces CMD only):
#   0.0.0.0 inside the container's own network namespace; the host publishes it on 127.0.0.1 only.
#   Full offload with --fit off: refuse to start rather than silently spill layers to the CPU.
#   Attack surface off: no web UI, no /slots, no MCP proxy, no agent tools, no network fetches.
#   Absent on purpose: --rpc, --tools, --mcp-servers-*, --models-dir (router), --media-path,
#   --slot-save-path, --props, --connect.
ENTRYPOINT ["/opt/llama/llama-server", \
  "--host", "0.0.0.0", "--port", "8080", \
  "-ngl", "99", "--fit", "off", "-fa", "on", \
  "--no-webui", "--no-slots", "--no-ui-mcp-proxy", "--no-agent", "--offline"]
CMD ["-c", "32768", "--cache-type-k", "q4_0", "--cache-type-v", "q4_0", "-np", "1", "--jinja"]
