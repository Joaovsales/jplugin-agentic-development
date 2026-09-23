# Review Dispatch Contract

What every dispatch of a reviewer must carry, so the reviewer measures the change
against the intent behind it instead of its own priors about what code should be.

## The seven items

A dispatched reviewer knows only what its prompt carries. `/build` already holds
implementers to a contract (§ *Delegation prompt must include* in `/build`);
reviewers get the same treatment here, because a reviewer without the spec is
reviewing what the code *is* against nothing but its own priors about what code
should be.

This contract governs what crosses a **dispatch boundary**. An inline run already
holds all of it in context; *Dispatch Disclosure* governs what its agreement is
worth.

Every dispatch of `code-reviewer`, `critic`, `security-reviewer`, or
`software-design-expert-review` must carry all seven:

| # | Item | Why the reviewer cannot supply it itself |
|---|------|------------------------------------------|
| 1 | The `<base>...HEAD` diff — inline when small, else truncated-plus-path per *Large-Artifact Handoff* | it can run `git diff`, but not know which base this session used |
| 2 | **Every spec relevant to this session** — each spec's path **and** the AC list verbatim, with the checkbox state stripped | nothing in a diff names the spec it implements |
| 3 | The `tasks/todo.md` entries completed this run | separates "not implemented" from "next task, deliberately" |
| 4 | The `[AMBIGUITY]` lines emitted this run | a decision already made and recorded reads as a defect |
| 5 | The `TODO(shortcut):` markers touching changed files | same: a documented limit with an upgrade path is not a finding |
| 6 | The boundary — review issues **introduced** by this session; pre-existing patterns are out of scope | today this is stated to the orchestrator and never to the agent |
| 7 | The output format — four axes, `evidence` required at `75` or above | a persona drifts from the gate that consumes it |

Item 2 is plural because a session is. One shared module can belong to several
features, so a change routinely touches more than one spec — and a reviewer handed
one of three measures the other two's changes against nothing but its own priors,
then reports the difference as a defect. List **each spec** with its own criteria
rather than merging them into a single list, or the reviewer cannot tell which
contract an unmet criterion belongs to.

## Empty is not absent

**Items 2–5 must distinguish **empty** from **absent**.** Pass `deferrals: none`
and `no spec — <reason>`, never a missing line. A reviewer that cannot tell
"nothing was deferred" from "nobody told me" has to assume the latter and re-flag
everything, which is the noise this contract exists to remove. Items 1, 6 and 7
have no empty form — a dispatch without them is incomplete, not empty.

## Bounded items

Keep items 2–5 bounded the way item 1 is. A 250-line spec pasted verbatim into four
parallel dispatches costs four times what it reads; truncate-plus-path applies to
any of them that outgrows the diff it explains.

## Repo-survey dispatch

**A repo-survey dispatch has no session to describe.** `/sweep --routine architect`
reviews the whole tree through `/software-design-expert-review --scope tree`
rather than a change, so items 2, 3 and 6 have no subject. It passes `no spec — repo survey, nothing built this run` and
`deferrals: none`, and carries items 1, 4, 5 and 7 unchanged. This is the one
exception, and it is an exception to the *subject* of the items, never to stating
them.

## Share intent, withhold conclusions

**Share intent** — spec, acceptance criteria, task text, constraints, and the
documented deferrals above. These are facts about what was asked for, and a
reviewer denied them reviews against its own assumptions instead.

**Withhold conclusions** — the builder's account of why the code is correct, and
any other reviewer's findings. These are judgements about whether the ask was met,
and that judgement is the reviewer's own product. Passing them would import
exactly those priors that *Independence Accounting* keeps out, and the promotion
rule would then count a downstream echo as an independent witness.

The split is imperfect in one direction worth naming. A spec written by the builder
argues for its own design, and an AC list encodes what the builder decided "done"
means — so intent arrives carrying some of the author's case. Strip the checkbox
state (item 2), and treat the spec's rationale as a **claim to be tested**, not as
evidence. A reviewer that finds the spec's argument unsound should say so; that is
a finding, not a scope violation.

**A shared payload narrows independence to the reading, not the framing.** Four
passes handed identical intent share a frame by construction, which is exactly the
property *Independence Accounting* discounts. Their agreement still promotes,
because each read the diff separately — but a finding that merely restates
something the payload told all four is not corroboration, and must not be promoted
on that basis.

The split is why this contract does not simply forward the whole build trace.
