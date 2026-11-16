---
title: Source-check a coordinator brief's figures against the artifact
date: 2026-11-16
problem_type: process
module: orchestration briefs (coordinator → worker)
tags: [orchestration, brief, verification, units, source-check]
applies_when: a worker receives a brief that carries numbers, paths, delimiters or claims about a document, or a coordinator drafts one
---

In the 2026-11-15/16 session the coordinator's brief was the **least
reliable** component in the pipeline. Six factual defects started in the
coordinator's own instructions. Workers or gates caught all six:

- Shell quoting mangled a message and silently dropped tokens from it.
- A row delimiter was misdescribed.
- Two GB-versus-GiB errors spread into a routing document. #425's PR body
  records one: the brief gave 3.80 and 2.56 "GiB", but those are decimal GB
  file sizes (llama-bench reports 3.53 and 2.37 GiB).
- A pp512 throughput range was copied from benchmarks on other hardware.
- "Keep that stated in the document", about a fact the document never
  stated.

The 2026-11-16 wrap-up brief contained another one. It said the debt-ledger
entries came from this session's pushes, but every entry dated from
September to November 15 (PRs #83/#85, #92, #363, and a merge range).

**Rule.** A worker checks a brief's numbers, units, paths and claims about
existing documents against the artifact itself (file, PR, benchmark log),
not against the brief. A mismatch is reported back, not copied over. A
coordinator writes a long message to a file and passes the file, rather
than quoting it on the command line.
