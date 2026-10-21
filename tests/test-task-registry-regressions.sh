#!/bin/bash
# tests/test-task-registry-regressions.sh — contract tests for the provider-agnostic task registry:
# regressions of the model, index, configuration and local provider.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-regressions.sh runs only the cases whose name matches.
. "$(dirname "$0")/lib.sh"

py_module .agents/skills/task-registry/scripts
SCRIPTS="${PYTHONPATH%%:*}"   # py_module puts the declared directory first
CLI="$SCRIPTS/task-registry.py"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh

# A project directory with the layout every scenario expects; registry_repo
# is the same inside a git repository, for scenarios that resolve their
# repository from `origin`.
registry_project() {
  local d
  d="$(fixture_dir)"
  mkdir -p "$d/tasks" "$d/specs" "$d/docs"
  printf '%s' "$d"
}
registry_repo() {
  local d
  d="$(fixture_repo)"
  mkdir -p "$d/tasks" "$d/specs" "$d/docs"
  printf '%s' "$d"
}

# Run the CLI the way a skill does.
reg() { "$PY" "$CLI" "$@"; }

# --- shared fixture content --------------------------------------------------
# The seed lives under tests/fixtures/task-registry/; these helpers only place it.

write_index() {
  fixture_copy task-registry/todo.md "$1/tasks/todo.md"
}

# The gh mock first on PATH, with the shared labels and issues. The issue list
# also returns pull requests, marked by a `pull_request` key -- #45 is one,
# carrying a managed block so that a provider that fails to drop it would
# surface a fourth task.
install_gh_mock() {
  local d="$1"
  mkdir -p "$d/bin" "$d/ghdata"
  fixture_copy task-registry/gh "$d/bin/gh"
  chmod +x "$d/bin/gh"
  fixture_copy task-registry/labels.json "$d/ghdata/labels.json"
  fixture_copy task-registry/issues.json "$d/ghdata/issues.json"
  fixture_copy task-registry/issue-42.json "$d/ghdata/issue-42.json"
  fixture_copy task-registry/next-number "$d/ghdata/next-number"
}

# =============================================================================
# 12. Regressions — one block per defect found in review
#
# Each assertion here failed before its fix. They are grouped by the layer the
# defect lived in rather than by the review that found it, so the next reader
# finds them next to the code they constrain.
# =============================================================================

# --- model: an unbalanced marker must not eat the body ------------------------
if begin_case "12. Regressions — model: an unbalanced marker must not eat the body"; then
model_reg="$("$PY" - <<'EOF'
from registry.model import Task, upsert_metadata_block, safe_task

task = Task(id="a.b", title="A task")
stray = (
    "Intro paragraph.\n\n"
    "Someone quoted the format: <!-- task-registry:begin -->\n\n"
    "A paragraph a human wrote that must survive.\n\n"
    "<!-- task-registry:begin -->\ntask-id: stale.id\n<!-- task-registry:end -->\n"
)
out = upsert_metadata_block(stray, task)
print("stray-kept=" + str("A paragraph a human wrote that must survive." in out))
print("stray-intro-kept=" + str("Intro paragraph." in out))
print("stray-real-block-replaced=" + str("task-id: a.b" in out and "stale.id" not in out))

# The well-formed case still replaces in place, exactly once.
good = "Body.\n\n<!-- task-registry:begin -->\ntask-id: old\n<!-- task-registry:end -->\n\nTail.\n"
replaced = upsert_metadata_block(good, task)
print("replaced-count=" + str(replaced.count("<!-- task-registry:begin -->")))
print("tail-kept=" + str("Tail." in replaced))
print("old-id-gone=" + str("task-id: old" not in replaced))

# A foreign vocabulary value is defaulted and reported, never raised.
built, notes = safe_task("issue #7", id="x.y", title="T", kind="chore", status="triage")
print("safe-kind=" + built.kind)
print("safe-status=" + built.status)
print("safe-notes=" + str(len(notes)))
print("safe-note-names-source=" + str(all("issue #7" in note for note in notes)))
EOF
)"
assert_contains "$model_reg" "stray-kept=True" \
  "Model: a stray begin marker never deletes the prose after it"
assert_contains "$model_reg" "stray-intro-kept=True" \
  "Model: a stray begin marker never deletes the prose before it"
assert_contains "$model_reg" "stray-real-block-replaced=True" \
  "Model: the real block is still the one rewritten when a stray marker precedes it"
assert_contains "$model_reg" "replaced-count=1" \
  "Model: a well-formed block is still replaced in place, not duplicated"
assert_contains "$model_reg" "tail-kept=True" "Model: text after the block survives replacement"
assert_contains "$model_reg" "old-id-gone=True" "Model: the superseded identity is removed"
assert_contains "$model_reg" "safe-kind=task" "Model: an unknown kind reads as the default"
assert_contains "$model_reg" "safe-status=open" "Model: an unknown status reads as the default"
assert_contains "$model_reg" "safe-notes=2" "Model: each defaulted field is reported, not swallowed"
assert_contains "$model_reg" "safe-note-names-source=True" \
  "Model: the report names the record the bad value came from"
fi
end_case

# --- model: the parser reads the span the writer owns (#132) -----------------
if begin_case "12. model: the parser reads the span the writer owns (#132)"; then
# `upsert_metadata_block` rewrites the last complete innermost BEGIN..END pair so
# a stray or interrupted marker never eats human prose. The parser used to split
# on the FIRST BEGIN instead, and kept everything after it when END was missing,
# so a quoted marker or a half-written block injected a phantom parent or
# dependency into every local and GitHub read. The assertions tagged (#132)
# failed before the fix; the rest guard the shared span locator and the block
# state contract the fix introduced.
model_parse="$("$PY" - <<'EOF'
import pathlib, tempfile
from registry.config import Config
from registry.model import (
    METADATA_BEGIN, METADATA_END, ExternalRef, Task, TaskModelError, metadata_block_state,
    parse_metadata_block, render_metadata_block, upsert_metadata_block, task_from_metadata,
)
from registry.providers.base import ProviderError, WriteGate
from registry.providers.local import LocalMarkdownProvider

real = Task(
    id="real.task", title="Real task", kind="bug",
    evidence=("model.py:255, first BEGIN", "model.py:298, innermost pair"),
    reproduction=("run it, twice",),
    proposed_fix=("reuse the bounds",),
)
block = render_metadata_block(real)

# 1. A stray BEGIN before the real block carries fields the real block lacks.
leading = METADATA_BEGIN + "\nparent: phantom\ndepends-on: ghost\n\n" + block
meta = parse_metadata_block(leading)
print("leading-parent=" + str(meta.get("parent")))
print("leading-deps=" + repr(meta.get("depends-on", ())))
print("leading-id=" + str(meta.get("task-id")))

# 2. An incomplete BEGIN after the real block.
trailing = block + "\n\nQuoted: " + METADATA_BEGIN + "\nparent: phantom\n"
meta = parse_metadata_block(trailing)
print("trailing-parent=" + str(meta.get("parent")))
print("trailing-id=" + str(meta.get("task-id")))

# 3. An unfinished-only body has no block at all.
print("unfinished=" + repr(parse_metadata_block(METADATA_BEGIN + "\nparent: phantom\nstatus: done\n")))
print("empty=" + repr(parse_metadata_block("")))
print("none=" + repr(parse_metadata_block(None)))

# 4. Repeated entries keep their order and their commas.
meta = parse_metadata_block(leading)
print("evidence=" + " | ".join(meta["evidence"]))
print("reproduction=" + " | ".join(meta["reproduction"]))
print("proposed-fix=" + " | ".join(meta["proposed-fix"]))

# 5. Parser and writer agree on which pair is authoritative.
rewritten = upsert_metadata_block(leading, real.with_(kind="feature"))
meta = parse_metadata_block(rewritten)
print("agree-kind=" + meta["kind"])
print("agree-parent=" + str(meta.get("parent")))
print("agree-ends=" + str(rewritten.count(METADATA_END)))

# 5b. Two complete pairs: the reader takes the last, like the writer would — but
# which block is the record is now a guess, so the writer refuses instead.
stale = render_metadata_block(Task(id="stale.id", title="Stale", parent="phantom"))
two = stale + "\n\nProse between two blocks.\n\n" + block
meta = parse_metadata_block(two)
print("two-id=" + str(meta.get("task-id")))
print("two-parent=" + str(meta.get("parent")))
try:
    upsert_metadata_block(two, real.with_(kind="feature"))
    print("two-write=proceeded")
except TaskModelError as exc:
    print("two-write=refused: " + str(exc))

# 5c. Stray markers on both sides of the real block, read and rewritten.
both = METADATA_BEGIN + "\nparent: phantom\n\n" + block + "\n\nQuoted: " + METADATA_BEGIN + "\nparent: phantom2\n"
meta = parse_metadata_block(both)
print("both-id=" + str(meta.get("task-id")) + " both-parent=" + str(meta.get("parent")))
both_rewritten = upsert_metadata_block(both, real.with_(kind="feature"))
meta = parse_metadata_block(both_rewritten)
print("both-rewritten=" + meta["kind"] + "/" + str(meta.get("parent")) + "/" + str(both_rewritten.count(METADATA_END)))

# 5d. A complete pair a human quoted AFTER the real block wins on read, by the
# shared rule. Pinned as intended; the read is noted and the write refused (8b, 11).
quoted = block + "\n\nThe registry owns the text between " + METADATA_BEGIN + " and " + METADATA_END + " only.\n"
print("quoted-after=" + repr(parse_metadata_block(quoted)))

# 6. The GitHub read path keeps identity, status and the external reference.
ref = ExternalRef("github", "7", "https://github.com/o/r/issues/7")
task = task_from_metadata(title="Issue title", body=leading, external=ref,
                          status="in_progress", fallback_id="")
print("gh-id=" + task.id)
print("gh-parent=" + str(task.parent))
print("gh-deps=" + repr(task.depends_on))
print("gh-status=" + task.status)
print("gh-ref=" + task.external.id)

# 7. The local read path: a human quotes the marker above the managed block.
root = tempfile.mkdtemp()
local = LocalMarkdownProvider(Config(root=root), WriteGate(apply=True))
created = local.create_task(real.with_(status="blocked"))
path = pathlib.Path(root, "tasks/details/real.task.md")
original = path.read_text(encoding="utf-8")
path.write_text("Quoted marker: " + METADATA_BEGIN + "\nparent: phantom\ndepends-on: ghost\n\n" + original, encoding="utf-8")
read = local.get_task(created.external)
print("local-id=" + read.id)
print("local-parent=" + str(read.parent))
print("local-deps=" + repr(read.depends_on))
print("local-status=" + read.status)
print("local-ref=" + read.external.id)
print("local-stray-noted=" + str(any("real.task.md" in n and "outside the managed block" in n for n in local.limitations)))

# 8. The local write path: a rewrite next to the quoted marker keeps the prose.
path.write_text("Quoted marker: " + METADATA_BEGIN + "\nparent: phantom\n\n"
                "A paragraph a human wrote that must survive.\n\n" + original, encoding="utf-8")
local.update_task(local.get_task(created.external).with_(status="done"))
after = path.read_text(encoding="utf-8")
print("write-prose-kept=" + str("A paragraph a human wrote that must survive." in after))
print("write-quote-kept=" + str("Quoted marker: " + METADATA_BEGIN in after))
print("write-status=" + local.get_task(created.external).status)
print("write-parent=" + str(local.get_task(created.external).parent))
print("write-ends=" + str(after.count(METADATA_END)))

# 8b. A complete pair quoted after the real block: read noted, rewrite refused, file intact.
local.create_task(Task(id="quoted.task", title="Quoted", kind="bug", parent="epic.one"))
quoted_path = pathlib.Path(root, "tasks/details/quoted.task.md")
quoted_text = quoted_path.read_text(encoding="utf-8") + "\nThe registry owns the text between " + METADATA_BEGIN + " and " + METADATA_END + " only.\n"
quoted_path.write_text(quoted_text, encoding="utf-8")
quoted_read = local.get_task(ExternalRef("local", "quoted.task", "tasks/details/quoted.task.md"))
print("quoted-local-noted=" + str(any("quoted.task.md" in n and "several complete" in n for n in local.limitations)))
try:
    local.update_task(quoted_read.with_(status="done"))
    print("quoted-local-write=proceeded")
except ProviderError as exc:
    print("quoted-local-write=refused")
print("quoted-local-unchanged=" + str(quoted_path.read_text(encoding="utf-8") == quoted_text))

# 9. Block states: markers with no complete pair are damaged — empty on read, refused on write.
damaged = METADATA_BEGIN + "\ntask-id: real.task\nkind: bug\nparent: epic.one\n"
print("states=" + ",".join(metadata_block_state(b) for b in ("plain prose", block, leading, damaged, METADATA_END + "\nonly", two, quoted)))
try:
    upsert_metadata_block(damaged, real)
    print("damaged-write=proceeded")
except TaskModelError as exc:
    print("damaged-write=refused: " + str(exc))

# 10. The local provider: a hand-broken END is reported on read and refused on write.
local.create_task(Task(id="broken.task", title="Broken", kind="bug", parent="epic.one"))
broken_path = pathlib.Path(root, "tasks/details/broken.task.md")
broken_text = broken_path.read_text(encoding="utf-8").replace(METADATA_END + "\n", "")
broken_path.write_text(broken_text, encoding="utf-8")
broken = local.get_task(ExternalRef("local", "broken.task", "tasks/details/broken.task.md"))
print("broken-read-id=" + broken.id)
print("broken-noted=" + str(any("broken.task.md" in n and "no complete block" in n for n in local.limitations)))
try:
    local.update_task(broken.with_(status="done"))
    print("broken-write=proceeded")
except ProviderError as exc:
    print("broken-write=refused: " + str(exc))
print("broken-file-unchanged=" + str(broken_path.read_text(encoding="utf-8") == broken_text))

# 11. The GitHub read path reports damaged and stray bodies instead of staying silent.
from registry.providers.github import GitHubProvider
gh = GitHubProvider(Config(root=root, repository="o/r"), WriteGate(apply=False))
def issue(number, body):
    return {"number": number, "title": "Issue " + str(number), "body": body, "state": "OPEN",
            "labels": [], "url": "https://github.com/o/r/issues/" + str(number)}
gh_damaged = gh._to_task(issue(9, damaged))
print("gh-damaged-identity=" + gh_damaged.extra.get("registry_identity", "none"))
print("gh-damaged-noted=" + str(any("#9" in n and "no complete block" in n for n in gh.limitations)))
gh_quoted = gh._to_task(issue(10, quoted))
print("gh-quoted-identity=" + gh_quoted.extra.get("registry_identity", "none"))
print("gh-quoted-noted=" + str(any("#10" in n and "several complete" in n for n in gh.limitations)))
gh_clean = gh._to_task(issue(11, block))
print("gh-clean-silent=" + str(not any("#11" in n for n in gh.limitations)))
EOF
)"
assert_contains "$model_parse" "leading-parent=None" \
  "Model: a stray BEGIN before the real block does not inject a phantom parent (#132)"
assert_contains "$model_parse" "leading-deps=()" \
  "Model: a stray BEGIN before the real block does not inject a phantom dependency (#132)"
assert_contains "$model_parse" "leading-id=real.task" \
  "Model: the identity read comes from the writer-owned block"
assert_contains "$model_parse" "trailing-parent=None" \
  "Model: the parser skips a trailing BEGIN that never closes, like the writer"
assert_contains "$model_parse" "trailing-id=real.task" \
  "Model: a trailing BEGIN that never closes does not change the identity read"
assert_contains "$model_parse" "unfinished={}" \
  "Model: a body with no complete BEGIN..END pair yields empty metadata (#132)"
assert_contains "$model_parse" "empty={}" "Model: an empty body yields empty metadata"
assert_contains "$model_parse" "none={}" "Model: a None body yields empty metadata"
assert_contains "$model_parse" "evidence=model.py:255, first BEGIN | model.py:298, innermost pair" \
  "Model: repeated evidence entries keep order and commas"
assert_contains "$model_parse" "reproduction=run it, twice" \
  "Model: a reproduction entry keeps its comma"
assert_contains "$model_parse" "proposed-fix=reuse the bounds" \
  "Model: a proposed-fix entry survives the read"
assert_contains "$model_parse" "agree-kind=feature" \
  "Model: the parser reads back the pair the writer rewrote"
assert_contains "$model_parse" "agree-parent=None" \
  "Model: a rewrite next to a stray marker does not adopt its phantom parent"
assert_contains "$model_parse" "agree-ends=1" \
  "Model: a rewrite next to a stray marker still leaves exactly one END"
assert_contains "$model_parse" "two-id=real.task" \
  "Model: with two complete pairs the parser reads the last one, like the writer (#132)"
assert_contains "$model_parse" "two-parent=None" \
  "Model: with two complete pairs the first pair's parent is not read (#132)"
assert_contains "$model_parse" "two-write=refused: several complete metadata blocks" \
  "Model: the writer refuses to rewrite when two complete pairs compete"
assert_contains "$model_parse" "both-id=real.task both-parent=None" \
  "Model: stray markers on both sides of the real block read as the real block (#132)"
assert_contains "$model_parse" "both-rewritten=feature/None/1" \
  "Model: the rewrite of a both-sided body is what the parser reads back, one END"
assert_contains "$model_parse" "quoted-after={}" \
  "Model: a complete pair quoted after the real block is the one read — intended, noted by providers, refused by writers"
assert_contains "$model_parse" "gh-id=real.task" \
  "Model: a GitHub read with a stray marker keeps the real identity (#132)"
assert_contains "$model_parse" "gh-parent=None" \
  "Model: a GitHub read with a stray marker does not gain a phantom parent (#132)"
assert_contains "$model_parse" "gh-deps=()" \
  "Model: a GitHub read with a stray marker does not gain a phantom dependency (#132)"
assert_contains "$model_parse" "gh-status=in_progress" \
  "Model: a GitHub read with a stray marker keeps the provider status"
assert_contains "$model_parse" "gh-ref=7" \
  "Model: a GitHub read with a stray marker keeps the external reference"
assert_contains "$model_parse" "local-id=real.task" \
  "Local: a quoted marker above the managed block keeps the real identity (#132)"
assert_contains "$model_parse" "local-parent=None" \
  "Local: a quoted marker above the managed block does not inject a phantom parent"
assert_contains "$model_parse" "local-deps=()" \
  "Local: a quoted marker above the managed block does not gain a phantom dependency (#132)"
assert_contains "$model_parse" "local-status=blocked" \
  "Local: a quoted marker above the managed block keeps the status"
assert_contains "$model_parse" "local-ref=real.task" \
  "Local: a quoted marker above the managed block keeps the external reference"
assert_contains "$model_parse" "local-stray-noted=True" \
  "Local: a stray marker is reported as a limitation naming the file"
assert_contains "$model_parse" "write-prose-kept=True" \
  "Local: a rewrite next to a quoted marker keeps the human paragraph (#132)"
assert_contains "$model_parse" "write-quote-kept=True" \
  "Local: a rewrite next to a quoted marker keeps the quoted line itself"
assert_contains "$model_parse" "write-status=done" \
  "Local: the rewrite next to a quoted marker still applies the status change"
assert_contains "$model_parse" "write-parent=None" \
  "Local: the rewrite does not adopt the quoted marker's phantom parent"
assert_contains "$model_parse" "write-ends=1" \
  "Local: the rewrite leaves exactly one managed block"
assert_contains "$model_parse" "quoted-local-noted=True" \
  "Local: a complete pair quoted after the block is reported as competing on read"
assert_contains "$model_parse" "quoted-local-write=refused" \
  "Local: a rewrite over competing complete pairs is refused"
assert_contains "$model_parse" "quoted-local-unchanged=True" \
  "Local: the refused rewrite leaves the file with competing pairs byte-identical"
assert_contains "$model_parse" "states=absent,intact,stray-markers,damaged,damaged,competing-blocks,competing-blocks" \
  "Model: block state names absent, intact, stray-markers, damaged and competing-blocks bodies"
assert_contains "$model_parse" "damaged-write=refused: metadata markers are present" \
  "Model: the writer refuses to rewrite over a damaged block"
assert_contains "$model_parse" "broken-read-id=broken.task" \
  "Local: a hand-broken END still reads, identity from the filename"
assert_contains "$model_parse" "broken-noted=True" \
  "Local: a hand-broken END is reported as a limitation on read"
assert_contains "$model_parse" "broken.task.md: metadata markers are present but form no complete" \
  "Local: a rewrite over a hand-broken END is refused, naming the file"
assert_contains "$model_parse" "broken-file-unchanged=True" \
  "Local: the refused rewrite leaves the damaged file byte-identical"
assert_contains "$model_parse" "gh-damaged-identity=provisional-title-slug" \
  "GitHub: a damaged block reads as a provisional identity"
assert_contains "$model_parse" "gh-damaged-noted=True" \
  "GitHub: a damaged block is reported as a limitation naming the issue"
assert_contains "$model_parse" "gh-quoted-identity=provisional-title-slug" \
  "GitHub: a complete pair quoted after the block reads as provisional, by the shared rule"
assert_contains "$model_parse" "gh-quoted-noted=True" \
  "GitHub: competing complete pairs are reported as a limitation naming the issue"
assert_contains "$model_parse" "gh-clean-silent=True" \
  "GitHub: an intact block produces no limitation"
fi
end_case

# --- index: titles, references, indentation, provider classification ---------
if begin_case "12. index: titles, references, indentation, provider classification"; then
index_reg="$("$PY" - <<'EOF'
from registry.index import TaskIndex, render_row
from registry.model import ExternalRef, Task

text = "\n".join([
    "# Plan",
    "- [ ] -fno-strict-aliasing crashes the build <!-- task-id: bug.aliasing --> — a compiler flag",
    "  - [ ] Nested child row <!-- task-id: bug.aliasing.child --> — indented on purpose",
    "- [ ] Crafted ref ([--body-file=/etc/passwd](https://github.com/o/r/issues/1)) <!-- task-id: evil.one -->",
    "- [ ] Foreign tracker ([REG-4](https://tracker.example.com/browse/REG-4)) <!-- task-id: foreign.one -->",
])
index = TaskIndex("tasks/todo.md", text, "tasks/todo.md")
by_id = {row.task.id: row for row in index.rows}
print("title=" + by_id["bug.aliasing"].task.title)
print("indent=[" + by_id["bug.aliasing.child"].indent + "]")
child = by_id["bug.aliasing.child"]
print("rerendered-indent=[" + render_row(child.task, child.indent)[:2] + "]")
print("crafted-parsed=" + str("evil.one" in by_id))
print("crafted-problem=" + str(any("body-file" in p.message for p in index.problems)))
print("foreign-provider=" + by_id["foreign.one"].task.external.provider)
label = render_row(Task(id="j", title="J", external=ExternalRef("local", "REG-4", "u")))
print("foreign-label-plain=" + str("[REG-4]" in label and "#REG-4" not in label))
gh_label = render_row(Task(id="g", title="G", external=ExternalRef("github", "42", "u")))
print("github-label-hashed=" + str("[#42]" in gh_label))
EOF
)"
assert_contains "$index_reg" "title=-fno-strict-aliasing crashes the build" \
  "Index: a title that starts with a dash is not silently trimmed"
assert_contains "$index_reg" "indent=[  ]" "Index: a nested row's indentation is captured"
assert_contains "$index_reg" "rerendered-indent=[  ]" \
  "Index: rewriting a nested row preserves its indentation"
assert_contains "$index_reg" "crafted-parsed=False" \
  "Index: a reference id shaped like a CLI flag is not turned into a task"
assert_contains "$index_reg" "crafted-problem=True" \
  "Index: the rejected reference is reported as malformed input, not dropped"
assert_contains "$index_reg" "foreign-provider=local" \
  "Index: a URL no shipped provider owns falls back to local, never to a guess"
assert_contains "$index_reg" "foreign-label-plain=True" \
  "Index: a non-GitHub reference renders as its own key, not as #key"
assert_contains "$index_reg" "github-label-hashed=True" \
  "Index: a GitHub reference still renders as #number"
fi
end_case

# --- config: merging, pointer precedence, confinement, floors ----------------
if begin_case "12. config: merging, pointer precedence, confinement, floors"; then
F_CFG="$(registry_project)"
mkdir -p "$F_CFG/.claude"
cat > "$F_CFG/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local

[labels.kind]
question = research
EOF
printf '```\n' >> "$F_CFG/docs/task-tracking.md"
cp "$F_CFG/docs/task-tracking.md" "$F_CFG/docs/project-owned.md"
printf 'Task tracking instructions: docs/project-owned.md\n' > "$F_CFG/.claude/project.md"
printf 'Task tracking instructions: docs/template-managed.md\n' > "$F_CFG/CLAUDE.md"
cp "$F_CFG/docs/task-tracking.md" "$F_CFG/docs/template-managed.md"

cfg_reg="$(cd "$F_CFG" && "$PY" - <<'EOF'
from registry.config import Config, ConfigError, load_config
from registry.redaction import redactor_for

config = load_config(".")
print("source=" + str(config.source_path))
labels = config.kind_labels
print("declared=" + labels.get("question", "(missing)"))
print("default-bug=" + labels.get("bug", "(missing)"))
print("default-enhancement=" + labels.get("enhancement", "(missing)"))
print("default-decision=" + labels.get("design-decision", "(missing)"))

confined = Config(root=".", local_detail_dir="../../escape")
try:
    confined.path(confined.local_detail_dir)
    print("escape=allowed")
except ConfigError as exc:
    print("escape-refused=" + str(exc))

# A retired provider must leave no half-configuration behind: a `jira_*` field
# surviving on Config is a credential slot nothing fills and nothing redacts.
print("jira-attrs=" + str(sorted(a for a in dir(Config(root=".")) if "jira" in a.lower())))
# Dropping the configured-secret list must not cost the generic scrubbing. The
# masker keeps its own patterns, so an Authorization header and the password half
# of URL userinfo are still masked with no secret registered at all.
#
# Scope, stated rather than implied: pattern 3 requires a scheme, so userinfo in
# text that names the host WITHOUT `https://` is not matched. That is precisely
# the case the deleted `_url_credentials` existed for. Nothing leaks today, since
# no shipped provider keeps a URL credential in config -- but the gap is real and
# is asserted below as a known gap rather than left for someone to discover.
redactor = redactor_for(Config(root="."))
print("mask-auth=" + redactor.scrub("Authorization: Basic ZmFrZTp0b2tlbg=="))
print("mask-userinfo=" + redactor.scrub("https://user:sup3rsecretvalue@site.example/x"))
print("leaks-userinfo=" + str("sup3rsecretvalue" in redactor.scrub(
    "https://user:sup3rsecretvalue@site.example/x")))
print("no-scheme-gap=" + str("sup3rsecretvalue" in redactor.scrub(
    "cannot reach user:sup3rsecretvalue@site.example")))

EOF
)"
assert_contains "$cfg_reg" "source=docs/project-owned.md" \
  "Config: the project-owned pointer wins over the template-managed one"
assert_contains "$cfg_reg" "declared=research" "Config: a declared label mapping is read"
assert_contains "$cfg_reg" "default-bug=bug" \
  "Config: declaring one mapping does not unmap the shipped defaults"
assert_contains "$cfg_reg" "default-enhancement=feature" \
  "Config: 'enhancement' still maps after a section is declared"
assert_contains "$cfg_reg" "default-decision=decision" \
  "Config: 'design-decision' still maps after a section is declared"
assert_contains "$cfg_reg" "escape-refused=" \
  "Config: a configured path outside the project root is refused"
assert_contains "$cfg_reg" "jira-attrs=[]" \
  "Config: a retired provider leaves no credential field behind on Config"
assert_contains "$cfg_reg" "mask-auth=Authorization: ***REDACTED***" \
  "Redaction: an Authorization header is masked with no configured secret"
assert_contains "$cfg_reg" "mask-userinfo=https://user:***REDACTED***@site.example/x" \
  "Redaction: the password is masked and the username is preserved"
assert_contains "$cfg_reg" "leaks-userinfo=False" \
  "Redaction: the with-scheme userinfo pattern still masks the password half"
assert_contains "$cfg_reg" "no-scheme-gap=True" \
  "Redaction: userinfo without a scheme is a KNOWN gap — a provider carrying a URL credential must register it through redactor_for, not rely on the patterns"

# The configured-secret path has no production caller since Cut 1 (redactor_for
# returns Redactor([])), and the assertions that exercised it lived in the Jira
# block this cut deleted. The seam is kept deliberately, so it is tested
# deliberately -- an untested seam is not a seam, and the next provider to carry
# a credential inherits this mechanism.
redactor_unit="$("$PY" - <<'EOF'
from registry.redaction import Redactor
print("registered=" + Redactor(["sup3rsecretvalue"]).scrub("saw sup3rsecretvalue here"))
print("short-filtered=" + Redactor(["ab"]).scrub("saw ab here"))
merged = Redactor(["alpha-secret"])
merged.adopt(Redactor(["beta-secret"]))
print("adopted=" + merged.scrub("alpha-secret and beta-secret"))
EOF
)"
assert_contains "$redactor_unit" "registered=saw ***REDACTED*** here" \
  "Redaction: a registered secret is masked wherever it appears"
assert_contains "$redactor_unit" "short-filtered=saw ab here" \
  "Redaction: a secret under four characters is not registered -- it would mask prose"
assert_contains "$redactor_unit" "adopted=***REDACTED*** and ***REDACTED***" \
  "Redaction: adopt() merges both sets, so a late-loaded credential is still masked"

# A pointer that escapes the repository must not be followed — and must not be
# silently skipped either. It is a declared intent with a broken target, the
# same shape as a missing file (#82), and the configuration guide already
# documents escapes as refused. The declared string is echoed, never opened.
F_ESC="$(registry_project)"
printf 'Task tracking instructions: ../../../etc/passwd\n' > "$F_ESC/AGENTS.md"
esc_out="$(cd "$F_ESC" && "$PY" - <<'EOF'
from registry.config import ConfigError, find_config_path
try:
    print("resolved=" + str(find_config_path(".")))
except ConfigError as exc:
    print("refused=" + str(exc))
EOF
)"
assert_contains "$esc_out" "refused=" \
  "Config: a pointer resolving outside the project root is refused, not silently skipped"
assert_contains "$esc_out" "AGENTS.md" \
  "Config: the refusal names the file that declared the escaping pointer"
assert_contains "$esc_out" "outside the project root" \
  "Config: the refusal says why"

# Approval is a floor: a repository file may add it, never remove it.
F_FLOOR="$(registry_project)"
cat > "$F_FLOOR/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = github
require_write_approval = false
EOF
printf '```\n' >> "$F_FLOOR/docs/task-tracking.md"
install_gh_mock "$F_FLOOR"
floor_out="$(cd "$F_FLOOR" && "$PY" - <<'EOF'
from registry.config import load_config
plain = load_config(".", env={})
trusted = load_config(".", env={"TASK_REGISTRY_TRUSTED_CONFIG": "1"})
print("untrusted=" + str(plain.require_write_approval))
print("ignored-flag=" + str(plain.approval_relaxation_ignored))
print("trusted=" + str(trusted.require_write_approval))
EOF
)"
assert_contains "$floor_out" "untrusted=True" \
  "Config: a checked-in file cannot switch off the approval requirement"
assert_contains "$floor_out" "ignored-flag=True" \
  "Config: the ignored relaxation is recorded so doctor can say so"
assert_contains "$floor_out" "trusted=False" \
  "Config: an operator who trusts the repository can lower the floor"
floor_doctor="$(cd "$F_FLOOR" && TASK_REGISTRY_TRUSTED_CONFIG=0 PATH="$F_FLOOR/bin:$PATH" GH_MOCK_DIR="$F_FLOOR/ghdata" \
  reg doctor --repo "$F_FLOOR" 2>&1)"
assert_contains "$floor_doctor" "approval is a floor" \
  "Doctor: the refused relaxation is visible to the user"
fi
end_case

# --- local provider: a compact row must not delete detail --------------------
if begin_case "12. local provider: a compact row must not delete detail"; then
F_LOSS="$(registry_project)"
write_index "$F_LOSS"
loss_out="$(cd "$F_LOSS" && "$PY" - <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers import build_provider
from registry.providers.base import WriteGate

config = load_config(".")
provider = build_provider("local", config, WriteGate(apply=True))

rich = Task(
    id="recipe.morph-live-grid",
    title="Morph live grid recipe",
    kind="feature",
    summary="Ship the live grid morph.",
    acceptance_criteria=("the grid morphs live", "no frame drops"),
)
provider.create_task(rich)
path = "tasks/details/recipe.morph-live-grid.md"
with open(path, "a", encoding="utf-8") as handle:
    handle.write("\n## Notes\n\nA human wrote this.\n")

# Exactly what a compact index row produces: title, status, nothing else.
provider.update_task(Task(id="recipe.morph-live-grid", title="Morph live grid recipe"))
after = open(path, encoding="utf-8").read()
print("summary-kept=" + str("Ship the live grid morph." in after))
print("criteria-kept=" + str("no frame drops" in after))
print("kind-kept=" + str("kind: feature" in after))
print("human-section-kept=" + str("A human wrote this." in after))
EOF
)"
assert_contains "$loss_out" "summary-kept=True" \
  "Local: updating from a compact row does not delete the Summary section"
assert_contains "$loss_out" "criteria-kept=True" \
  "Local: updating from a compact row does not delete the Acceptance Criteria"
assert_contains "$loss_out" "kind-kept=True" \
  "Local: updating from a compact row does not downgrade the recorded kind"
assert_contains "$loss_out" "human-section-kept=True" \
  "Local: a section a human added survives an update"

# The offline provider writes inside the repository, so approval has no subject.
F_OFFLINE="$(registry_project)"
write_index "$F_OFFLINE"
cat > "$F_OFFLINE/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local
EOF
printf '```\n' >> "$F_OFFLINE/docs/task-tracking.md"
offline_pub="$(reg upsert offline.record --repo "$F_OFFLINE" --title 'Recorded offline' --apply 2>&1)"
offline_code=$?
assert_eq "0" "$offline_code" \
  "Local: --apply alone writes offline — approval gates external writes only"
assert_contains "$offline_pub" "created" "Local: the offline write actually created the task"
fi
end_case

finish
