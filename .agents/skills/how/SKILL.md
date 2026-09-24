---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Use why for motivation."
disable-model-invocation: false
harness: universal
---

# How

Explore the codebase to answer "how does X work?" questions. Produce architectural explanations at the level of a senior engineer onboarding onto a subsystem, enough to build a working mental model, not so much that it reads like annotated source code.

Each spawn below names a tier from `.agents/references/model-routing.md`. Explorers are Scout tier. The explainer is Ceiling tier: pass no `model`, so it inherits the session model. On Pi, never pass per-call model params; `subagents.agentOverrides` resolves them.

## Step 1. Assess Complexity

If the scope is ambiguous, state your interpretation and explore. The user can redirect.

- **Simple** (a single module, a small utility, a narrow question such as "how does function X work"): no explorers. One explainer explores and explains in a single pass. Go to Step 2b.
- **Complex** (a subsystem spanning multiple files or services, a cross-cutting feature, a full architectural overview): spawn parallel explorers first, then hand off to the explainer. Go to Step 2a.

When in doubt, take the simple path.

## Step 2a. Explore (complex questions only)

Decompose the question into 2 to 4 exploration angles, each a distinct slice of the subsystem. Spawn all explorers in a single message:

- Scout tier, read-only: the `Explore` agent with `model: "haiku"` on Claude Code, the `scout` builtin on Pi

Each explorer gets the prompt in `references/explorer-prompt.md` with its angle filled in. Then go to Step 3.

## Step 2b. Direct Explain (simple questions)

Spawn one sub-agent that explores and explains in one pass:

- Ceiling tier, read-only: the `general-purpose` agent on Claude Code, and pass no `model`. Its prompt forbids edits

Build its prompt from `references/explainer-prompt.md` without the explorer-findings section. Go to Step 4.

## Step 3. Synthesize (complex questions only)

Once all explorers have returned, spawn one sub-agent to synthesize their findings into one explanation:

- Ceiling tier, read-only: the `general-purpose` agent on Claude Code, and pass no `model`. Its prompt forbids edits

Build its prompt from `references/explainer-prompt.md` with every explorer's findings filled in.

## Step 4. Present

Present the explainer's output to the user. Light edits for clarity or context from the conversation are fine. Do not substantially rewrite it.

## Output Format

The explanation uses the sections defined in `references/explainer-prompt.md`, dropping any that do not apply: Overview, Key Concepts, How It Works, Where Things Live, Gotchas.

## Provenance

Adapted from pstack's `how` skill — `pstack/skills/how/` in `cursor/plugins`,
revision `12d587dfb20741cafc376c42c696c5f6e2a64487`. The references are
upstream's, unmodified. SKILL.md changes only what this harness needs: the
model-routing tiers replace the models rule file and the per-spawn Task
settings, and `disable-model-invocation` is `false` so `/go`'s investigate lane
can run it. The upstream MIT notice is bundled as `LICENSE.pstack`;
repository-level provenance is in `THIRD_PARTY_NOTICES.md`.
