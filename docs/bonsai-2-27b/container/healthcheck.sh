#!/bin/bash
# HEALTHCHECK plus watchdog. Docker's restart policy acts on container exit, never on
# `unhealthy`, so a wedged llama-server would stay up and keep being called. This check
# SIGKILLs llama-server after WATCHDOG_FAILURES consecutive failed probes; tini (PID 1) then
# exits and `restart: unless-stopped` brings the container back.
#
# The watchdog arms only after the first healthy probe, so a slow model load (503) is never
# killed. A server that never becomes healthy is left to Docker's `unhealthy` status: a load
# that fails exits on its own (full offload with --fit off fails fast).
set -u
readonly SERVER=/opt/llama/llama-server
readonly STATE=/tmp/llama-health
readonly PROBE_TIMEOUT=4          # seconds; must stay under the HEALTHCHECK --timeout (5s)
readonly WATCHDOG_FAILURES=3

if [[ ${1:-} == --probe ]]; then
  exec 3<>/dev/tcp/127.0.0.1/8080 \
    && printf 'GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3 \
    && IFS= read -r line <&3 \
    && [[ $line == *' 200 '* ]]
  exit
fi

mkdir -p "$STATE"
if timeout "$PROBE_TIMEOUT" "$0" --probe; then
  : > "$STATE/armed"
  echo 0 > "$STATE/failures"
  exit 0
fi

[[ -e $STATE/armed ]] || exit 1
failures=$(( $(cat "$STATE/failures" 2>/dev/null || echo 0) + 1 ))
echo "$failures" > "$STATE/failures"
(( failures >= WATCHDOG_FAILURES )) || exit 1

echo "watchdog: ${failures} consecutive failed probes, killing llama-server" >&2
for proc in /proc/[0-9]*; do
  [[ $(readlink "$proc/exe" 2>/dev/null) == "$SERVER" ]] && kill -KILL "${proc#/proc/}"
done
rm -rf "$STATE"
exit 1
