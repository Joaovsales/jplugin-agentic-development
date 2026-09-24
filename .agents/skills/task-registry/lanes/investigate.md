---
cues: how does X work, why was Y built this way, is Z safe, compare A and B
ends: a cited answer, no diff
---
# Lane: investigate

Runs when the goal asks how something works, why it was built a way, whether
it is safe, or how two things compare, and requests no code. Decided before
every other lane, by what the human wants back: a question with error text
pasted is still a question.

1. Restate the question as a falsifiable claim and name the files it turns on
2. Read those files; quote the lines that answer it
3. Trace one live run if the code alone is inconclusive
4. Reply with the cited answer
5. `/checkpoint` — keep the answer on disk, only if the human asks — optional

## Reply

The claim, the verdict, and every quoted line with its `file:line`. If a live
run was traced, the command and its output. No diff: this lane never edits a
file, and a goal that turns out to need one goes back through the front door.
