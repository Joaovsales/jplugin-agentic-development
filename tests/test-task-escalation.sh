#!/bin/bash
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
CLI="$SCRIPTS/task-registry.py"
PY="$TEST_PYTHON"
TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

P="$(mktemp -d)"; TMP_DIRS+=("$P")
mkdir -p "$P/tasks"
printf '# Tasks\n' > "$P/tasks/todo.md"
PYTHONPATH="$SCRIPTS" "$PY" - "$P" <<'PY'
import sys
from registry.config import Config
from registry.model import Task
from registry.providers.base import WriteGate
from registry.providers.local import LocalMarkdownProvider
root = sys.argv[1]
LocalMarkdownProvider(Config(root=root), WriteGate(apply=True)).create_task(
    Task(id="parent.bug", title="Parent bug", kind="bug", labels=("bug", "in-progress")))
PY

COMMON=(escalate parent.bug --repo "$P" --reason execution-blocked
  --reproduction-state unverified --run-at 2026-09-12T12:34:56-03:00
  --repro-command 'run <fixture>' --observed $'runner stopped\nstatus: done'
  --evidence tasks/routine-runs/source.md)

before="$(find "$P" -type f -exec sha256sum {} + | sort)"
dry="$("$PY" "$CLI" "${COMMON[@]}" 2>&1)"; dry_code=$?
after="$(find "$P" -type f -exec sha256sum {} + | sort)"
assert_eq "0" "$dry_code" "AC10: escalation defaults to a successful no-write preview"
assert_eq "$before" "$after" "AC10: dry-run changes no provider file or run artifact"
assert_contains "$dry" "hold: preview" "AC10: preview names the intended hold stage"

report_refusal="$("$PY" "$CLI" "${COMMON[@]}" --report "$P/report.md" 2>&1)"; report_code=$?
assert_eq "2" "$report_code" "AC10: escalate rejects the shared --report option as usage"
assert_eq "absent" "$([ -e "$P/report.md" ] && echo present || echo absent)" \
  "AC10: rejected --report never reaches the shared output writer"

bad_pair="$("$PY" "$CLI" escalate parent.bug --repo "$P" --reason verification-blocked \
  --reproduction-state unverified --run-at 2026-09-12T12:00:00Z --repro-command x \
  --observed y --evidence z 2>&1)"; bad_pair_code=$?
assert_eq "2" "$bad_pair_code" "AC2: reason/state contradictions are usage errors"
assert_contains "$bad_pair" "verification-blocked" "AC2: validation names the contradictory field"

naive_time="$("$PY" "$CLI" escalate parent.bug --repo "$P" --reason inconclusive \
  --reproduction-state unverified --run-at 2026-09-12T12:00:00 --repro-command x \
  --observed y --evidence z 2>&1)"; naive_code=$?
assert_eq "2" "$naive_code" "AC2: run-at must carry an explicit timezone"
both_evidence="$("$PY" "$CLI" "${COMMON[@]}" --evidence-unavailable missing 2>&1)"; both_code=$?
assert_eq "2" "$both_code" "AC2: evidence reference and unavailable reason are mutually exclusive"
unavailable="$("$PY" "$CLI" escalate parent.bug --repo "$P" --reason inconclusive \
  --reproduction-state not-reproduced --run-at 2026-09-12T12:00:00Z \
  --repro-command x --observed y --evidence-unavailable 'artifact host unavailable' 2>&1)"
assert_eq "0" "$?" "AC2: an explicit evidence-unavailable reason is a valid preview"

BLOCKER="$P/blocker.json"
printf '%s\n' '{"version":1,"source":"tests/runner.sh","title":"Repair runner","summary":"Runner misses fixture","handling":"routine","reproduction":["run tests"],"proposed_fix":["restore fixture"],"criteria":["test reaches assertions"]}' > "$BLOCKER"
applied="$("$PY" "$CLI" "${COMMON[@]}" --blocker-file "$BLOCKER" --apply 2>&1)"; applied_code=$?
assert_eq "1" "$applied_code" "AC9: a fully applied escalation always terminates non-zero"
assert_contains "$applied" "hold: confirmed" "AC5: label readback confirms the hold before blocker filing"
assert_contains "$applied" "blocker: local" "AC6: a valid actionable blocker is filed"
assert_contains "$applied" "comment: delivered" "AC2: the parent notification stage is explicit"
assert_file_contains "$P/tasks/details/parent.bug.md" "needs-investigation" \
  "AC4: parent retains labels and gains the escalation hold"
assert_file_contains "$P/tasks/details/parent.bug.md" '"run_at": "2026-09-12T15:34:56Z"' \
  "AC2: the parent report normalizes the timestamp to UTC seconds"
assert_file_contains "$P/tasks/details/parent.bug.md" '\u003cfixture>' \
  "AC10: untrusted less-than text is escaped inside fenced JSON"
BLOCKER_DETAIL="$(find "$P/tasks/details" -name 'routine-blocker.*.md' | head -1)"
assert_file_contains "$BLOCKER_DETAIL" "source: tests/runner.sh" \
  "AC6: accepted blocker source survives local persistence"
assert_file_contains "$BLOCKER_DETAIL" "1. run tests" \
  "AC10: accepted blocker reproduction survives render/read boundaries"
assert_file_contains "$BLOCKER_DETAIL" "- [ ] test reaches assertions" \
  "AC10: accepted blocker criterion survives render/read boundaries"
assert_file_contains "$BLOCKER_DETAIL" "originating parent: local:parent.bug" \
  "AC7: blocker evidence retains the canonical parent reference"
assert_eq "1" "$(find "$P/tasks/routine-runs" -type f | wc -l)" \
  "AC9: applied escalation retains one exclusive run artifact"
RUN_ARTIFACT="$(find "$P/tasks/routine-runs" -type f | head -1)"
assert_file_contains "$RUN_ARTIFACT" '"blocker_disposition": "local"' \
  "AC7: retained artifact carries the confirmed blocker outcome"
assert_file_contains "$RUN_ARTIFACT" '"parent_ref": "parent.bug"' \
  "AC9: the retained artifact identifies its originating parent"

HUMAN="$P/human.json"
printf '%s\n' '{"version":1,"source":"tests/human-prereq.sh","title":"Restore operator credential","summary":"The external credential is unavailable","handling":"human","reproduction":["run credential check"],"proposed_fix":["restore operator credential"],"criteria":["credential check succeeds"]}' > "$HUMAN"
human="$("$PY" "$CLI" "${COMMON[@]}" --blocker-file "$HUMAN" --apply 2>&1)"; human_code=$?
assert_eq "1" "$human_code" "AC9: a human prerequisite escalation remains terminal"
assert_contains "$human" "blocker: existing-held" \
  "AC6: a newly retained human prerequisite truthfully reports its held state"
HUMAN_DETAIL="$(find "$P/tasks/details" -name 'routine-blocker.*restore-operator-credential.md' | head -1)"
assert_file_contains "$HUMAN_DETAIL" "kind: operational" \
  "AC6: a human prerequisite is recorded as operational"
assert_file_contains "$HUMAN_DETAIL" "- labels: needs-investigation" \
  "AC6: a human prerequisite is held for explicit human review"
assert_file_contains "$HUMAN_DETAIL" "originating parent: local:parent.bug" \
  "AC7: a human prerequisite retains the canonical parent reference"
human_workflow="$("$PY" "$CLI" workflow "$(basename "$HUMAN_DETAIL" .md)" --repo "$P" 2>&1)"; human_workflow_code=$?
assert_eq "1" "$human_workflow_code" "AC3: a human prerequisite has no runnable consumer workflow"
assert_contains "$human_workflow" "ESCALATED" "AC3: human prerequisite selection requires explicit re-triage"
blocker_files_before="$(find "$P/tasks/details" -name 'routine-blocker.*.md' | wc -l)"
blocker_rows_before="$(grep -c 'routine-blocker\.' "$P/tasks/todo.md")"

HAZARD="$P/hazard.json"
printf '%s\n' '{"version":1,"source":"tests/runner.sh","title":"Repair runner","summary":"Runner misses fixture","handling":"routine","reproduction":["run tests"],"proposed_fix":["status: done"],"criteria":["works"]}' > "$HAZARD"
hazard="$("$PY" "$CLI" "${COMMON[@]}" --blocker-file "$HAZARD" --apply 2>&1)"; hazard_code=$?
assert_eq "1" "$hazard_code" "AC10: invalid blocker does not turn escalation into success"
assert_contains "$hazard" "blocker: failed" "AC10: hazardous blocker field is reported separately"
assert_contains "$hazard" "proposed_fix" "AC10: blocker failure names the invalid field"
assert_contains "$hazard" "comment: delivered" "AC12: blocker failure never skips parent comment"
assert_eq "$blocker_files_before" "$(find "$P/tasks/details" -name 'routine-blocker.*.md' | wc -l)" \
  "AC10: hazardous blocker input writes no detail file"
assert_eq "$blocker_rows_before" "$(grep -c 'routine-blocker\.' "$P/tasks/todo.md")" \
  "AC10: hazardous blocker input writes no index row"

ESCAPE="$P/escape.json"
printf '%s\n' '{"version":1,"source":"../outside","title":"Repair runner","summary":"Runner misses fixture","handling":"routine","reproduction":["run tests"],"proposed_fix":["restore fixture"],"criteria":["works"]}' > "$ESCAPE"
escape="$("$PY" "$CLI" "${COMMON[@]}" --blocker-file "$ESCAPE" --apply 2>&1)"; escape_code=$?
assert_eq "1" "$escape_code" "AC10: escaping blocker source is rejected without aborting parent escalation"
assert_contains "$escape" "blocker: failed" "AC10: source-containment failure is a blocker stage result"
assert_contains "$escape" "comment: delivered" "AC12: source-containment failure still reaches parent notification"
assert_eq "$blocker_files_before" "$(find "$P/tasks/details" -name 'routine-blocker.*.md' | wc -l)" \
  "AC10: escaping blocker source writes no detail file"
assert_eq "$blocker_rows_before" "$(grep -c 'routine-blocker\.' "$P/tasks/todo.md")" \
  "AC10: escaping blocker source writes no index row"

outside_runs="$(mktemp -d)"; TMP_DIRS+=("$outside_runs")
rm -rf "$P/tasks/routine-runs"
ln -s "$outside_runs" "$P/tasks/routine-runs"
artifact_failure="$("$PY" "$CLI" "${COMMON[@]}" --apply 2>&1)"; artifact_failure_code=$?
assert_eq "1" "$artifact_failure_code" "AC9: artifact confinement failure remains a terminal result"
assert_contains "$artifact_failure" "hold: confirmed" "AC9: artifact failure retains the completed hold stage"
assert_contains "$artifact_failure" "comment: delivered" "AC9: artifact failure retains the completed comment stage"
assert_contains "$artifact_failure" "artifact: failed" "AC9: artifact confinement failure is reported explicitly"
assert_not_contains "$artifact_failure" "Traceback" "AC9: expected artifact confinement failure has no traceback"

unit="$("$PY" - "$SCRIPTS" <<'PY'
import sys, tempfile, pathlib
sys.path.insert(0, sys.argv[1])
from registry.config import Config
from registry.escalation import EscalationRequest, EscalationError, escalate_task
from registry.model import ExternalRef, Task
from registry.providers.base import ProviderStatus, ProviderError, WriteGate

class Fake:
    name = "github"
    def __init__(self, add_fails=False, comment_fails=False, labels=("bug", "in-progress"),
                 readback_fails=False, terminal_on_readback=False, unavailable=False,
                 require_approval=False):
        self.gate = WriteGate(
            apply=True, require_approval=require_approval, approved=not require_approval
        )
        self.task = Task(id="p.one", title="P", labels=labels, external=ExternalRef("github", "7", "u"))
        self.add_fails, self.comment_fails = add_fails, comment_fails
        self.readback_fails, self.terminal_on_readback = readback_fails, terminal_on_readback
        self.unavailable = unavailable
        self.adds = self.comments = self.reads = 0
        self.bodies = []
    def discover(self): return ProviderStatus(not self.unavailable, "offline" if self.unavailable else "ok")
    def resolve_reference(self, raw): return self.task.external
    def get_task(self, ref):
        self.reads += 1
        if self.readback_fails and self.reads > 1: raise ProviderError("Authorization: Bearer abcdefghijk")
        if self.terminal_on_readback and self.reads > 1: return self.task.with_(status="done")
        return self.task
    def add_labels(self, task, labels):
        self.gate.authorize("add labels", self.name)
        self.adds += 1
        if self.add_fails: raise ProviderError("label delivery failed")
        self.task = self.task.with_(labels=self.task.labels + tuple(labels))
    def comment(self, task, body):
        self.gate.authorize("comment", self.name)
        self.comments += 1
        self.bodies.append(body)
        if self.comment_fails: raise RuntimeError("comment delivery unknown")

def request(parent="7"):
    return EscalationRequest(parent, "inconclusive", "unverified", "2026-09-12T00:00:00Z", "cmd", "obs", ("artifact",), None, None)
def registry(provider):
    root = tempfile.mkdtemp(); pathlib.Path(root, "tasks").mkdir(); pathlib.Path(root, "tasks/todo.md").write_text("# T\n")
    return type("R", (), {"config": Config(root=root, provider="github", repository="o/r"), "provider": provider})()

claim = Fake(add_fails=True)
text, code = escalate_task(registry(claim), request(), True)
print("claim-only:", code, claim.adds, claim.reads, claim.comments, "hold: claim-only" in text)
unconfirmed = Fake(add_fails=True, labels=("bug",))
text, code = escalate_task(registry(unconfirmed), request(), True)
print("unconfirmed:", code, unconfirmed.adds, unconfirmed.reads, unconfirmed.comments,
      "hold: unconfirmed" in text, "blocker: skipped" in text)
readback = Fake(readback_fails=True)
text, code = escalate_task(registry(readback), request(), True)
print("readback-failed:", code, readback.adds, readback.reads, readback.comments,
      "hold: claim-only" in text, "***REDACTED***" in text, "abcdefghijk" not in text)
terminal = Fake(terminal_on_readback=True)
text, code = escalate_task(registry(terminal), request(), True)
print("became-terminal:", code, terminal.adds, terminal.reads, terminal.comments,
      "parent became terminal" in text)
offline = Fake(unavailable=True)
text, code = escalate_task(registry(offline), request(), True)
print("offline:", code, offline.adds, offline.comments, "parent: refused" in text)
denied = Fake(require_approval=True)
denied_registry = registry(denied)
text, code = escalate_task(denied_registry, request(), True)
print("denied:", code, denied.adds, denied.comments, "hold: claim-only" in text,
      "comment: unknown" in text,
      len(list(pathlib.Path(denied_registry.config.root, "tasks/routine-runs").iterdir())))
userinfo = Fake()
userinfo_registry = registry(userinfo)
text, code = escalate_task(
    userinfo_registry, request("https://user:password@github.com/o/r/issues/7"), True
)
artifact = next(pathlib.Path(userinfo_registry.config.root, "tasks/routine-runs").iterdir()).read_text()
persisted = userinfo.bodies[0] + artifact
print("canonical-parent:", code, '"parent_ref": "p.one"' in persisted,
      "password" not in persisted, "user:" not in persisted)
unknown = Fake(comment_fails=True)
text, code = escalate_task(registry(unknown), request(), True)
print("comment-unknown:", code, unknown.adds, unknown.comments, "comment: unknown" in text)
closed = Fake(); closed.task = closed.task.with_(status="done")
text, code = escalate_task(registry(closed), request(), True)
print("closed:", code, closed.adds, closed.comments, "parent: refused" in text)
mismatch = Fake()
text, code = escalate_task(registry(mismatch), request("wanted.id"), True)
print("mismatch:", code, mismatch.adds, mismatch.comments, "does not match" in text)
PY
)"
assert_contains "$unit" "claim-only: 1 1 2 1 True" \
  "AC5: failed label write gets one readback, retains claim fallback, and still comments"
assert_contains "$unit" "unconfirmed: 1 1 2 1 True True" \
  "AC5: failed hold without a prior claim stays unconfirmed and files no blocker"
assert_contains "$unit" "readback-failed: 1 1 2 1 True True True" \
  "AC5/AC10: readback failure uses the prior claim and redacts exception credentials"
assert_contains "$unit" "became-terminal: 1 1 2 1 True" \
  "AC8: a concurrent terminal transition skips blocker creation and still comments once"
assert_contains "$unit" "offline: 1 0 0 True" \
  "AC9: an unavailable authoritative provider refuses before every mutation"
assert_contains "$unit" "denied: 1 0 0 True True 1" \
  "AC9: denied escalation performs no provider mutation and retains honest terminal stages"
assert_contains "$unit" "canonical-parent: 1 True True True" \
  "AC9/AC10: persisted reports use canonical parent identity without URL userinfo"
assert_contains "$unit" "comment-unknown: 1 1 1 True" \
  "AC12: comment exception is unknown after one dispatch and is never retried"
assert_contains "$unit" "closed: 1 0 0 True" \
  "AC8: a closed parent is refused before every remote mutation"
assert_contains "$unit" "mismatch: 1 0 0 True" \
  "AC5: authoritative identity mismatch refuses all escalation writes"

dispositions="$("$PY" - "$SCRIPTS" <<'PY'
import json, pathlib, re, sys, tempfile
sys.path.insert(0, sys.argv[1])
import registry.escalation as escalation
from registry.config import Config
from registry.escalation import BlockerRequest, EscalationRequest
from registry.model import ExternalRef, Task
from registry.providers.base import WriteGate
from registry.redaction import redactor_for
from registry.upsert import UpsertDisposition, UpsertResult

class Fake:
    name = "github"
    def __init__(self, task):
        self.gate = WriteGate(apply=True, require_approval=False)
        self.task, self.comments = task, []
    def add_labels(self, task, labels):
        self.task = task.with_(labels=task.labels + tuple(labels))
    def get_task(self, reference): return self.task
    def comment(self, task, body): self.comments.append(body)

request = EscalationRequest(
    "parent.one", "execution-blocked", "unverified", "2026-09-12T00:00:00Z",
    "run", "blocked", ("artifact",), None, "unused.json",
)
blocker = BlockerRequest(
    "tests/runner.sh", "Repair runner", "Runner unavailable", "routine",
    ("run",), ("repair",), ("runs",),
)
original = escalation.upsert_task_result
for disposition in (
    UpsertDisposition.LOCAL_PENDING, UpsertDisposition.EXISTING_HELD,
    UpsertDisposition.EXISTING_TERMINAL, UpsertDisposition.FAILED,
    UpsertDisposition.UNKNOWN,
):
    root = tempfile.mkdtemp()
    pathlib.Path(root, "tasks").mkdir()
    pathlib.Path(root, "tasks/todo.md").write_text("# Tasks\n", encoding="utf-8")
    config = Config(root=root, provider="github", repository="o/r")
    parent = Task(
        id="parent.one", title="Parent", labels=("bug", "in-progress"),
        external=ExternalRef("github", "7", "https://github.com/o/r/issues/7"),
    )
    provider = Fake(parent)
    registry = type("Registry", (), {"config": config, "provider": provider})()
    filed = Task(
        id="routine-blocker.tests-runner-sh.repair-runner", title="Repair runner",
        external=ExternalRef("local", "routine-blocker.tests-runner-sh.repair-runner", "tasks/details/blocker.md"),
    )
    result = UpsertResult(disposition, task=filed, readback=filed, detail="fixture")
    escalation.upsert_task_result = lambda registry, task, apply, value=result: value
    text, code = escalation._apply_escalation(
        registry, parent, request, blocker, None, redactor_for(config)
    )
    artifact_path = next(pathlib.Path(root, "tasks/routine-runs").iterdir())
    comment_payload = json.loads(re.search(r"```json\n(.*?)\n```", provider.comments[0], re.S).group(1))
    artifact_payload = json.loads(re.search(r"```json\n(.*?)\n```", artifact_path.read_text(), re.S).group(1))
    print(disposition, code, comment_payload["blocker_disposition"],
          artifact_payload["blocker_disposition"], artifact_payload["parent_ref"])
escalation.upsert_task_result = original
PY
)"
for disposition in local-pending existing-held existing-terminal failed unknown; do
  assert_contains "$dispositions" "$disposition 1 $disposition $disposition parent.one" \
    "AC7/AC12: $disposition is preserved in the parent comment and retained artifact"
done

finish
