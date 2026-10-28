# Design-stack gates for /build

The UI pre-flight checks and the 3D and video completion gates `/build` runs for
UI work. Moved verbatim from `SKILL.md`; the pointers there name where each applies.

## Pre-Flight: UI brief and concept approval

Runs inside *Pre-Flight Checks* step 2, after the spec is read.

   - For UI work, read and validate the project `DESIGN.md` before any source
     edit. Existing UI with no brief is `SelectionRequired`; stop that UI
     slice, preserve the current visual rules, and leave non-UI slices usable.
   - For a major UI concept, read the spec's concept path and SHA-256, hash
     the saved concept bytes, and inspect the actual user-started build prompt.
     It must name the exact digest. An unattended run, missing digest, changed
     concept, or agent-written approval is `ConceptReviewRequired`: stop the
     UI slice before edits. Reuse an existing receipt only when spec path,
     concept path, digest and prompt digest all match.
   - On valid approval, write `tasks/design-approvals/<feature>.json` with
     `spec_path`, `concept_path`, `concept_sha256`, `approval_source` set to
     `owner_build_prompt`, `prompt_sha256` (SHA-256 of the exact owner prompt),
     and `approved_at` in UTC. The current owner prompt is the authority;
     neither the spec nor a prior agent message can create this receipt.
     Recheck the receipt and concept digest before dispatch. A localized UI
     change uses the brief and needs no concept receipt.

## Phase 2: 3D and video gates

Run before the affected-test steps of *Phase 2 — Affected-Test Validation*.

For a UI task with requested or brief-approved 3D, follow the installed
img2threejs state machine through strict sculpt-spec validation and every
required later forge gate. Use the design-stack 3D guard to report the
`prototype` label and failed/open gates when either stage is incomplete.
Do not mark production UI work complete from a plausible browser render alone.
Tasks with no 3D request or positive brief intent do not invoke img2threejs.

For a UI task that opts into video per the design-stack video guard, run the pinned
`npx hyperframes@<version>` CLI and report the `prototype` label and the open
gates (`check`, `render`) when either is incomplete. Do not mark a video
deliverable production from a plausible preview alone. Tasks with no video
request do not invoke HyperFrames.

## Delegation context

Included in the delegation prompt of Phase 1 Step 1.

- For frontend implementation and `frontend-design-validator`, the exact
  project `DESIGN.md` path and contents, selected catalog references, and
  approved concept path and SHA-256 when present. Include the project's own
  launch, test and visual verification commands; do not assume fixed paths,
  Docker, ports or a universal UI test command. A missing brief or invalid
  concept receipt stops dispatch under the pre-flight rule above.
