---
name: grilling
description: Interview the user relentlessly about a plan, decision, or idea until a shared understanding is reached, working the design tree in frontier rounds with a recommended answer on every question. Use when the user wants to stress-test their thinking, uses any 'grill' phrasing, or when another skill needs the decisions behind a piece of work settled before it acts.
argument-hint: "[plan, decision, or idea to grill]"
disable-model-invocation: false
harness: universal
---

# /grilling — Frontier-Round Interview

## Overview

Interview the user until you reach a shared understanding. Map the subject as a
**design tree**: every decision branches into the decisions that hang off it.
The product is the settled tree, held in the conversation. This skill writes
nothing; the caller decides what to record.

## The Process

### 1. Root the tree

The argument is the root. When another skill invokes this, the surrounding task
is the root. List the decisions that hang off it before answering any of them.
A caller may hand you seed questions along with the root; fold them into the
first frontier under the same prerequisite rule as every other question, never
ahead of it.

### 2. Compute the frontier

The **frontier** is every decision whose prerequisites are already settled: the
questions you can ask now without guessing at answers you have not heard yet. A
question whose answer depends on another question still open in this round
belongs to a later round, not this one.

### 3. Ask the whole frontier in one round

Number each question and give your recommended answer on its own line:

```
❓ **Q1** - **<question title>**: <question body, may run several paragraphs and include multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body>

➡️ <your recommended answer>
```

Every question carries a recommendation. A question without one is either a
fact you should have looked up or a decision you are handing back unframed.
Prefer multiple-choice bodies: they are faster to answer and leave less room
for ambiguity.

### 4. Facts are yours, decisions are the user's

When a frontier question needs a fact from the environment (filesystem, tools,
documentation), dispatch a read-only Scout-tier lookup (the `Explore` agent
on Claude Code, per `.agents/references/model-routing.md` § *Tiers*; the `scout`
builtin on Pi) rather than asking the user for anything you could look up.
The lookup reads; it never edits, so "writes nothing" holds whatever it
finds. Do not block on it: a running lookup is an
unsettled prerequisite, so only the questions downstream of it wait for the
sub-agent to report. Ask the rest of the frontier now.

Decisions are the user's. Put each to them and wait for the answer.

### 5. Recompute and repeat

Each round of answers reshapes the tree: settled decisions push the frontier
outward and unblock the questions that depended on them. Recompute the
frontier and ask the next round.

The frontier is your judgement, not a computed graph. When the user says two
questions in one round depended on each other, reopen that branch and
recompute the next round from the reopened state.

### 6. End condition

The session is done when the frontier is empty: every branch of the design
tree visited, nothing left silently assumed. Do not act on the outcome until
the user confirms you have reached a shared understanding.

## Opt-out

A user who prefers the sequential rhythm adds the line
`When grilling, ask one question at a time.` to `CLAUDE.local.md` (Claude Code)
or `~/.pi/agent/AGENTS.md` (Pi). Honour it: one question per turn, each still
carrying its ➡️ recommendation.

## Integration

- Called by: `/grill-me` (typed by the user, writes nothing) and `/brainstorm`
  Step 3 (with its domain-modeling layer active).
- Writes: nothing. Any file the interview produces is the caller's.

## Provenance

Adapted from `skills/productivity/grilling/SKILL.md` in
[mattpocock/skills](https://github.com/mattpocock/skills) at revision
`c55ee46073ed923f86ce59a5eb3b6d895095d1b7`. The design tree, frontier rounds,
the round format and the facts-versus-decisions split are upstream's. The
Scout-tier dispatch, the opt-out line and the dependency-reopen rule are local.
The upstream MIT notice is bundled as `LICENSE.mattpocock`; repository-level
provenance is in `THIRD_PARTY_NOTICES.md`.
