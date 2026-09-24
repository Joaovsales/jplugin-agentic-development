---
cues: how does X work, where should X live, why was Y built this way, is Z safe, compare A and B
ends: a cited answer, no diff
---
# Lane: investigate

Runs when the goal asks how something works, where it belongs, why it was built
a way, whether it is safe, or how two things compare, and requests no code.
Decided before every other lane, by what the human wants back: a question with
error text pasted is still a question.

1. Restate the question as a falsifiable claim and name the files it turns on
2. `/how <ref>` — the question asks how it works or where it belongs; its explanation answers it — optional
3. `/why <ref>` — the question asks why it is this way; its cited read answers it — optional
4. Read those files; quote the lines that answer it
5. Trace one live run if the code alone is inconclusive
6. Reply with the cited answer
7. `/checkpoint` — keep the answer on disk, only if the human asks — optional

## Reply

The claim, the verdict, and every quoted line with its `file:line`. If a live
run was traced, the command and its output. When `/how` or `/why` ran, its
output is the answer, in that skill's own format. No diff: this lane never
edits a file, and a goal that turns out to need one goes back through the front
door.
