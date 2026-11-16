# Native Bash cwd tracker — unpaid reproduction

Root cause: Claude Code 2.1.325 generates a sandbox with `denyWrite: //tmp`
while its default eval run home and temporary directory also sit beneath `/tmp`.
Bash runs the requested command, then its mandatory `pwd -P > cwd-*` tracker
fails on the read-only mount. This is an infrastructure error, not model output.

## Prelude and evidence

1. Generated temporary-directory deny rule: retained configuration and tool
   error agree; a controlled layout change removes the failure (evidence 1).
2. Outer test namespace mount: unchanged `ro-bind /` plus writable run-root bind
   in failing and passing probes. Successful artifact writes and the passing
   Bash command disconfirm the outer mount as the primary cause (evidence 1).
3. Ownership: both probes execute under UID/GID 1000 with a freshly owned run
   directory. The failure explicitly says read-only filesystem; moving the
   directory without changing identity fixes it (evidence 1).

Picked #1 after the controlled comparison. No sandbox restriction was removed.

## Supported layout

Use a short neutral run root outside `/tmp`, `/var/tmp` and `/dev/shm`:

```bash
python3 tasks/eval-results/code-graph/transport-probe.py \
  --relay tasks/eval-results/code-graph/sandbox-relay.py \
  --root-parent /home/joaosouto --root-prefix hr- \
  --receipt tasks/eval-results/code-graph/transport-probe-receipt.json
```

The operational layout is `HOME=<root>/host-home`,
`TMPDIR=<root>/temporary`, and a task-local `tools/socat` relay on PATH.
Native eval creates the candidate's sanitized home/config below that root.
A longer first layout failed Unix bridge initialization; the short layout
avoids the socket-path constraint and passes the controlled probe.

## Verification

- Network namespace contained loopback only; only a fake credential was used.
- Bash returned `is_error: false`, with `harbor relay ready` and
  `graphify 0.9.109` in the actual tool result.
- Sandbox remained enabled, required, and unsandboxed execution forbidden.
- Native exit 1 is the expected regex outcome for the deliberately unrelated
  mock answer; it is not a Bash failure or an experiment verdict.
- Request shape, sandbox flags, paths and tool result are retained in
  `transport-probe-receipt.json`; full raw probe artifacts remain at the
  absolute `artifact_root` it names. No paid call or package install occurred.
- Probe source compiles with `python3 -m py_compile`.

## Not finished

OAuth bearer transport through the local base URL is not verified by this
fake-API-key probe. Production admission, protocol registration and all paid
runs remain owned by the orchestrator.
