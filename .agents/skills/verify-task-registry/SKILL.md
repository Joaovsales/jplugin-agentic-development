---
name: verify-task-registry
description: Verify this repository's task-registry CLI through isolated local task creation, reading, and routine selection with retained PTY evidence.
disable-model-invocation: false
harness: universal
---

# /verify-task-registry — Task registry verification

## Surface and capability ceiling

Primary surface: the real Python task-registry CLI shipped in this repository.
Driver: Bash plus util-linux `script`, one isolated PTY per CLI invocation.
Proof: command arguments, merged stdout/stderr, exit status, and persisted task
content reopened through a second CLI invocation. No build server, port, login,
or seed service is needed; Python 3.8+ and util-linux `script -e` are required.

Secondary surfaces: GitHub issues, installer commands, and agent-invoked workflows.
This local-provider recipe cannot prove GitHub authorization/concurrency, skill
triggering, a complete routine ending in a PR, or installation. Report criteria
requiring those surfaces as BLOCKED until separately driven with their required
context. There is no browser surface; VISUAL criteria are BLOCKED with this driver.
Unit tests and mocked trackers are supplemental evidence, never substitutes.

Read [the feature index](features/README.md) before choosing a recipe.

## Launch and ownership

Run the following in one Bash session from the repository root. This creates only
an owned scratch repository and a separate, durable evidence directory. No helper
files are shipped: these commands and the feature recipes are the complete interface.
Do not run this skill in a downstream repository missing the task-registry CLI.

```bash
set -euo pipefail
VERIFY_SOURCE=$(pwd -P)
VERIFY_CLI="$VERIFY_SOURCE/.agents/skills/task-registry/scripts/task-registry.py"
test -f "$VERIFY_CLI"
command -v python3
script --version
mkdir -p "$VERIFY_SOURCE/tasks/verification"
VERIFY_EVIDENCE=$(mktemp -d "$VERIFY_SOURCE/tasks/verification/task-registry.XXXXXX")
VERIFY_RUNTIME=$(mktemp -d /tmp/verify-task-registry.XXXXXX)
VERIFY_REPO="$VERIFY_RUNTIME/project"
cleanup() {
  rm -rf -- "$VERIFY_RUNTIME"
  test ! -e "$VERIFY_RUNTIME"
  printf 'owned runtime removed: %s\n' "$VERIFY_RUNTIME" > "$VERIFY_EVIDENCE/cleanup.txt"
}
trap cleanup EXIT
mkdir -p "$VERIFY_REPO/docs"
printf 'Task tracking instructions: docs/task-tracking.md\n' > "$VERIFY_REPO/AGENTS.md"
printf '%s\n' '```ini' '[tracker]' 'provider = local' '```' > "$VERIFY_REPO/docs/task-tracking.md"
{
  git -C "$VERIFY_SOURCE" rev-parse HEAD
  git -C "$VERIFY_SOURCE" status --short
  sha256sum "$VERIFY_CLI"
  printf 'source=%s\nrepo=%s\nauth=none; provider=local; port=none\n' "$VERIFY_SOURCE" "$VERIFY_REPO"
} > "$VERIFY_EVIDENCE/identity.txt"
drive() {
  local proof=$1 command_text result
  shift
  printf -v command_text '%q ' python3 "$VERIFY_CLI" "$@" --repo "$VERIFY_REPO" --provider local
  printf '%s\n' "$command_text" > "$VERIFY_EVIDENCE/$proof.command.txt"
  if SHELL=/bin/bash script -q -e -c "$command_text" "$VERIFY_EVIDENCE/$proof.pty.txt" </dev/null; then
    result=0
  else
    result=$?
  fi
  printf '%s\n' "$result" > "$VERIFY_EVIDENCE/$proof.exit.txt"
  return "$result"
}
```

Each drive owns only its foreground process and PTY; it exits before the next
command starts. There are no background processes, profiles, or ports to reclaim.
On interruption, let the foreground command terminate before removing its owned
scratch directory. Never kill by process name. Concurrent runs get distinct paths.

## Doctor

```bash
drive doctor doctor
rg 'provider: +local' "$VERIFY_EVIDENCE/doctor.pty.txt"
rg 'reachable: +yes' "$VERIFY_EVIDENCE/doctor.pty.txt"
rg -F 'configuration:  docs/task-tracking.md' "$VERIFY_EVIDENCE/doctor.pty.txt"
rg -F 'local Markdown store at tasks/details/' "$VERIFY_EVIDENCE/doctor.pty.txt"
```

Require exit 0 and all four checks. Together with identity.txt and the recorded
`--repo` / `--provider` arguments, this identifies the source revision, data root,
configuration, and auth context. CLI readiness is successful Doctor completion.
A mismatch is BLOCKED; do not drive a different or shared repository to get a pass.

## Drive and preserve evidence

Execute [record and update](features/record-task.md) for the minimum walkthrough;
then use [read detail](features/read-task.md) and
[routine selection](features/routines.md) as the criteria require. Each feature
lists entry points separately; record unrun entry points as NOT RUN.

PTY logs combine stdout/stderr; the companion exit file is authoritative. Capture
both the action and the read-back; a successful write message alone is insufficient.
Do not seed task records through internal Python imports or edit stored metadata.
The configuration above is setup; all task state is created through the public CLI.

## Cleanup and surviving-artifact check

After the selected feature finishes, run:

```bash
cleanup
trap - EXIT
test -s "$VERIFY_EVIDENCE/doctor.pty.txt"
test -s "$VERIFY_EVIDENCE/create.pty.txt"
test -s "$VERIFY_EVIDENCE/reopen.pty.txt"
test -s "$VERIFY_EVIDENCE/cleanup.txt"
printf 'PASS: evidence survived cleanup\n' > "$VERIFY_EVIDENCE/survival.txt"
printf 'Evidence: %s\n' "$VERIFY_EVIDENCE"
```

On failure the EXIT trap still removes owned runtime state and retains evidence;
record FAIL or BLOCKED, the failing command, and its exit status. Never label a
failed cleanup or missing artifact as PASS. For a read-only recipe, first run the
minimum walkthrough to seed its task and supply these named baseline artifacts.

Append the command sequence, feature IDs and entry points, Doctor outcome,
read-back observations, cleanup outcome, and surviving evidence paths to
`tasks/e2e-log.md`. Only mark an entry point PASS when its own proof was checked.

## Integration

Consumed by `/verify --scope e2e`. After user-facing changes run
`/maintain-verification-skill --scope changed`; for a full source-and-live audit
run `/maintain-verification-skill`. This skill does not commit or push its evidence.
