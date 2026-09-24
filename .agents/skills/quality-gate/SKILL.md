---
name: quality-gate
description: "The post-build review gate: run when all tasks in tasks/todo.md are done, before wrap-up or commit. Sequential phases — structural quality and reuse (simplify), AI anti-pattern cleanup (deslop), the security checklist, and APOSD design audit — emitting four-axis findings (severity, confidence, autofix_class, owner), then the affected tests and a quality receipt bound to the diff. Triggers on: 'review before I call it done', 'thorough review of what I just built', 'I finished the tasks, check the code', 'run the quality gate', 'post-build review'."
argument-hint: "[--scope <path> ...] [--parent <fingerprint>]"
---

# /quality-gate — Post-Build Quality Review

> **Dispatching sub-agents?** Read `.agents/skills/build/references/subagent-resilience.md` first. This skill runs unattended, so a hung
> sub-agent has no human watching it: give every agent a tool-call budget with a "write partial
> work and stop" escape hatch, arm a stall monitor, and never retry a deterministic failure
> with an identical prompt.

Six sequential phases run after all build tasks are complete: four review
phases, each with a unique mandate, then the tests and the receipt. This is the
one review pass a diff gets — `/wrap-up-session` reuses its receipt instead of
reviewing again (`specs/quality-receipt-closure.md`).

## Scope

Determine files to review — **the gate's own file list**, which every phase uses:
1. If `--scope <path> ...` provided: review only those paths. `/wrap-up-session`
   passes the delta `receipt.py check` printed, with `--parent <fingerprint>`.
2. Otherwise: every file that differs between the merge-base and the working
   tree — committed, staged, unstaged and untracked, `tasks/**` excluded. The
   merge-base is the first field `receipt.py fingerprint` prints; call it with
   no `--base`, so the gate and wrap-up agree on one base:

   ```bash
   python3 .agents/skills/quality-gate/scripts/receipt.py fingerprint
   # <merge-base> <tree> <fingerprint>
   git diff --name-only <merge-base> -- . ':(exclude)tasks/**'
   git ls-files --others --exclude-standard -- . ':(exclude)tasks/**'
   ```

Skip: generated files, lock files, migration files, test fixtures.

---

## Finding Model

Every finding this gate produces or consumes carries four orthogonal fields.
Rationale and the cross-harness rule live in `.agents/references/finding-model.md`; the
operational contract is here, at the point where findings get applied.

| Field | Answers | Values |
|-------|---------|--------|
| `severity` | how urgent | `MUST-FIX` / `SHOULD-FIX` / `NITPICK` |
| `confidence` | how sure | `50` / `75` / `100` |
| `autofix_class` | what shape the fix is | `gated_auto` / `manual` / `advisory` |
| `owner` | who acts | `agent` / `human` / `release` |

```
[MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent] file.py:42 — description and impact
  evidence: `except Exception: pass` (file.py:42)
```

**Confidence anchors** — behavioral criteria, not a feeling:

| Anchor | Criterion |
|--------|-----------|
| `100` | You read the defect in the diff and can quote the line that proves it. Reproducible from the evidence alone. |
| `75` | You located the defect and can cite the line, but correctness turns on a caller, config, or runtime value outside the reviewed scope. |
| `50` | Pattern-matched or inferred. No line proves it, or you never read the path it depends on. |

### Apply Gate

| Condition | Action |
|-----------|--------|
| `gated_auto` **and** `confidence >= 75` | Apply in-phase, then run tests. |
| `gated_auto` but `confidence` `50` | Report only. An unproven fix is not cheaper than no fix. |
| `manual` or `advisory`, any confidence | Report only, with `owner`. |

A `MUST-FIX` at `confidence` `50` is worth one verification attempt before you
report it: read the path it depends on. Evidence found → it is `75`+ and the gate
clears it. Refuted → say so, and drop it. Reporting an unverified `MUST-FIX`
onward makes the next gate solve a problem you were holding the context to solve.

- A finding at `75` or `100` **must** carry `evidence` — the verbatim motivating
  line with `file:line`. Missing evidence **demotes** it to `50`.
- A finding arriving with no `confidence` — an older single-axis reviewer, or an
  agent that ignored this contract — is read as `50` / `autofix_class: manual`:
  reported, never auto-applied, never discarded.
- Where two phases or reviewers disagree on a finding, synthesis takes the
  **more conservative** `autofix_class`. It never widens.
- A `MUST-FIX` that the gate will not auto-apply is still a `MUST-FIX`. Report it
  under `owner` and let the caller's gate decide — do not downgrade it to make
  this phase come out clean.

---

## Phase 1 — Structural Quality (simplify)

**Mandate**: "Is this code structurally sound?" — function size, naming, reuse, SOLID.

For each file in scope:

### 1.1 Code Reuse
- **Duplicated logic** across files → extract shared function/module
- **Existing utilities** that already do what new code does → replace

### 1.2 Clean Code
- Functions **>20 LOC** → split
- Functions with **>3 parameters** → use options object/dataclass
- **Poor naming**: generic names (`data`, `info`, `tmp`, `result`) → rename to reveal intent
- **Dead code**: unreachable branches, unused imports → remove

### 1.3 SOLID
- **Single Responsibility**: class/function does more than one thing → split
- **Open/Closed**: new behavior via `if/else` chains → strategy/registry
- **Dependency Inversion**: hard-coded dependencies → inject

### 1.4 Unnecessary Complexity
- **Over-abstraction**: wrappers adding no value → inline
- **Premature generalization**: configurable with only one config → simplify
- **Defensive code for impossible cases** (internal values already guaranteed) → remove

**Process**: Read → list issues as four-axis findings → apply those the **Apply Gate** clears → run tests after all fixes. Revert any fix that breaks tests.

---

## Phase 2 — AI Anti-Patterns (deslop)

**Mandate**: "Does this code contain AI behavioral artifacts?" — hedge words, filler, over-engineering.

**Iron law: deletion over rewriting.**

**Never delete `TODO`, `FIXME`, or `TODO(shortcut):` markers.** They record a known
limitation and its upgrade path, so they must survive this phase even when the
surrounding comment is reworded. A deliberate shortcut is not slop.

For each file in scope:

### 2.1 Hedge Words in Comments
Comments with: "should", "might", "probably", "seems to", "basically", "essentially"
→ Delete or rewrite as single declarative statement.

### 2.2 Restating-the-Code Comments
```
// Set the user name
user.name = name;
```
→ Delete. Code is documentation.

### 2.3 Over-Documented Simple Functions
Docstring longer than function body for trivial functions (getters, setters, one-liners)
→ Delete the docstring.

### 2.4 Obvious Type Annotations
```typescript
const name: string = "hello";  // type is self-evident
```
→ Remove annotation, let inference work.

### 2.5 Impossible-Case Error Handling
Guards on internal values already validated by the caller → Delete.
Keep validation ONLY at system boundaries (user input, API responses, file I/O).

### 2.6 Filler Abstractions
- Wrapper functions that just call another with same args
- Manager/Handler/Helper classes with one method
→ Inline and delete.

### 2.7 Verbose Logging
Entry/exit logging for short functions → Remove.
Keep only: surprising states, errors, branch decisions.

### 2.8 Passthrough Catch Blocks
```javascript
try { doThing(); } catch (e) { throw e; }  // passthrough
```
→ Remove entirely.

**Process**: Scan → list findings as four-axis findings → apply the deletions the **Apply Gate** clears → run tests per file. Revert if tests fail.

---

## Phase 3 — Security

**Mandate**: "Does this change open a vulnerability?" — injection, auth, secrets,
unsafe input handling.

Run the `/security-scan` checklist inline over **the gate's own file list**
(untracked files included, `--scope` honoured) — not the `git diff --name-only`
list the skill builds when it is invoked on its own. Emit its findings in the
four-axis format and apply its fixes under the **Apply Gate**; a `MUST-FIX` it
will not apply stays unresolved and reaches the receipt. Record the phase as
`{"phase": 3, "lens": "security-scan", "dispatch": "inline"}`.

Security runs before Phase 4 so the dispatched design reviewer sees the
security fixes too.

---

## Phase 4 — Design Quality (APOSD)

**Mandate**: "Are modules well-designed?" — deep/shallow, info leakage, complexity flow.

### Inline checks (all harnesses):

Read all changed files together. For each module, check:

1. **Deep vs shallow**: Is the interface simpler than the implementation? Shallow = interface as complex as implementation → flag
2. **Information leakage**: Does a design decision appear in >1 file? → flag
3. **Pull complexity down**: Does the caller need internal knowledge to use this? → flag
4. **Temporal decomposition**: Is the module split by execution order, not responsibility? → flag
5. **Pass-through methods**: Any method that just forwards to another with same signature? → flag
6. **Vague names**: Any public name that requires reading the body to understand? → flag
7. **Conjoined methods**: Methods so coupled you can't use one without the other? → flag

Report findings in the canonical four-axis format from *Finding Model*. Apply per
the **Apply Gate** — `MUST-FIX` and `SHOULD-FIX` are not self-applying licences.
Run tests after fixes.

### Dispatch Disclosure

Phase 4 runs either as a dispatched `software-design-expert-review` agent or
inline in the main context. The two are not equivalent, and the output must say
which happened:

| How it ran | Disclosure | Promotion |
|-----------|-----------|-----------|
| Dispatched agent | `dispatched` | Its agreement with a Phase 1, 2 or 3 finding is independent corroboration: promote `confidence` by exactly one anchor. |
| Inline in the main context | `inline` | **No promotion.** Phase 4 shares this context's priors with Phases 1–3, so agreement is one perspective repeated. Name the corroboration lost. |

Per `.agents/references/finding-model.md` § *Independence Accounting*, agreement inside one context is not
two witnesses. An inline run is a complete run — it reports and applies under the
Apply Gate — but it may never report a promoted confidence.

**No phase after 4 edits the tree.** Phase 4's applied fixes are the last edit;
Phases 5 and 6 only observe, so the receipt describes exactly the tree that was
reviewed.

## Claude Code Enhancements

Dispatch the `software-design-expert-review` skill (invokes the `software-design-expert-review` agent at Ceiling tier — pass no `model`, so it inherits the session model) instead of running inline Phase 4. The agent is read-only — it reports findings only. Apply findings in the main context after the agent returns per the Apply Gate. Run tests after applying fixes. Because this path is a separate dispatch, record it as `dispatched`.

The dispatch carries the full payload in `.agents/references/review-dispatch-contract.md` —
diff, every relevant spec's path plus its acceptance criteria verbatim (or `no spec — <reason>`), the closed
`tasks/todo.md` entries, the `[AMBIGUITY]` batch and `TODO(shortcut):` markers (or
`deferrals: none`), the introduced-only boundary, and the four-axis format. A design
reviewer told only *what* changed reports structural debt the spec deliberately
accepted; the deferral list is what makes an accepted trade-off distinguishable from
an oversight. Withhold the findings of Phases 1–3 — passing them makes Phase 4 an
echo rather than a witness.

**Item 7 is read, not remembered.** Before dispatching, resolve `finding-model.md` in
order — the project's `.agents/references/`, then `${CLAUDE_PLUGIN_ROOT}/.agents/references/`
on Claude Code (the skill body and the reference then come from the same plugin version),
then `~/.agents/references/` on Pi and Codex — and paste its § *Emission format* into the
prompt verbatim. When all three are missing, stop before dispatch:
`review dispatch refused: finding-model.md not found in .agents/references/, ${CLAUDE_PLUGIN_ROOT}/.agents/references/, ~/.agents/references/ — run /sync`. Never dispatch a reviewer with no output format.

---

## Phase 5 — Tests

**Mandate**: "Is the reviewed tree green?" — evidence for the receipt, run once
after every fix has landed.

Run the project's `Affected tests:` command (below the `AGENTS.md` end marker,
`{base}` replaced by the merge-base from *Scope*) through the cache:
`.agents/skills/build/scripts/cached-suite.sh -- <affected-test command>`. With
no declaration, run the test files that cover the gate's file list. Record
`{"command": "<command>", "exit": <status>, "tree": "<tree>"}`, where `"tree"`
is the second field `receipt.py fingerprint` prints immediately before the run.

A failure here is a red `tests` record that the receipt turns into STOP —
never a silent fix. Fixing it is a new edit, and a new edit means a new gate
run on the new tree. This phase never runs the full suite: `/wrap-up-session`
Step 6 owns that, through the same cache.

## Phase 6 — Receipt

**Mandate**: "What exactly was reviewed, and what was left?" — a receipt bound
to the diff, which `/wrap-up-session` checks instead of reviewing again.

Write the outcome JSON under the git common dir, never in the worktree (a file
there would change the fingerprint it describes), then mint the receipt:

```bash
outcome="$(git rev-parse --path-format=absolute --git-common-dir)/quality-receipts/outcome.json"
python3 .agents/skills/quality-gate/scripts/receipt.py write --outcome "$outcome" [--parent <fingerprint>]
```

| Outcome field | Value |
|---------------|-------|
| `reviewers` | one `{phase, lens, dispatch, verdict?}` per Phase 1–4, `dispatch` as *Dispatch Disclosure* recorded it |
| `unresolved` | every finding in `Reported, not applied`, four-axis, with `location` (`file:line`) and `summary` |
| `design_verdict` | Phase 4's GO / HOLD / STOP |
| `tests` | Phase 5's record |
| `scope` | `"full"`, or the `--scope` path list — which requires `--parent <fingerprint>` |

The gate never supplies a verdict: `receipt.py` derives it from `unresolved`,
`design_verdict` and `tests`, and ignores a `verdict` key. On exit 2 the
receipt was refused and nothing was written — report `Receipt: none —` with
its stderr. The caller treats that as a stale receipt, never as GO.

---

## Task Reporting

Findings that outlive this run belong on the task, not in the transcript. When
the project tracks tasks externally, report them through `/task-registry`
(comment on the task) rather than calling a provider directly. Findings that were
auto-applied need no report; the ones that matter here are `owner: human` and
`owner: release`.

## Output

```
══════════════════════════════════════════
  QUALITY GATE — [N] files reviewed
══════════════════════════════════════════

Phase 1 — Structural Quality
  Applied: [N changes — list with file:line]
  Tests: [PASS / FAIL — N reverted]

Phase 2 — AI Anti-Patterns
  Removed: [N lines — list with file:line and category]
  Tests: [PASS / FAIL — N reverted]

Phase 3 — Security (/security-scan checklist, inline)
  Applied: [N fixes — list with file:line]
  Tests: [PASS / FAIL — N reverted]

Phase 4 — APOSD Design (/software-design-expert-review)
  Verdict: 🟢 GO / 🟡 HOLD (N refactors applied) / 🔴 STOP
  Tests: [PASS / FAIL]

Phase 5 — Tests: [<affected-test command> exit N on tree <tree8>]

Review independence: [Phase 4 dispatched / Phase 4 inline — no promotion; lost corroboration: <what>]
Reported, not applied: [N findings — list with file:line, autofix_class, owner]

Receipt: <GO|HOLD|STOP> <fp8> policy <qg1-xxxxxxxx> [parent <fp8>]
   or:   Receipt: none — <receipt.py stderr>

══════════════════════════════════════════
```

The `Reported, not applied` line is not optional. A finding the Apply Gate held
back is the one most likely to be lost, and an output that lists only what was
fixed reads as though nothing else was found.
