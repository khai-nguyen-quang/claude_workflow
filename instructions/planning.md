# Planning instructions

## Goal

Produce a detailed design document for a GitLab issue **or a free-form feature request**, building on the approved brainstorm spec. The brainstorm spec (high-level approach) and the design document are the inputs the Coding phase accepts — both must be approved by the user before work proceeds.

This single workflow serves both input variants; every step is identical except the sub-steps marked **(GitLab issue only)**. The variant is fixed by the phase as `<plan_source>` = `gitlab-issue` (`<ref>` has `#`) or `user-prompt` (free-form).

## Inputs (from task context)

- `<plan_slug>` — canonical identifier for this planning run (derived by the phase): `<project>-<id>` for a GitLab issue, or the free-form slug otherwise. All artifacts live under `.tmp/<plan_slug>/`.
- `<plan_source>` — `gitlab-issue` or `user-prompt`.
- `<project>` — GitLab project name (e.g. `projectX`); may be `(unknown)` for a free-form slug.
- `<id>` — GitLab issue number (e.g. `309`); empty for a free-form request.
- `<feature_description>` — for a free-form request, the feature text from the user's prompt (the issue fetch is skipped); absent for a GitLab issue.
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)
- `<brainstorm_spec>` — `.tmp/<plan_slug>/<plan_slug>_brainstorm.md`, the design spec
  approved during the planning phase's brainstorming step. It is the approved high-level
  approach (replacing a separate strategy document) and the primary source for the design;
  the raw issue/request is supporting context.

---

## Prerequisites (complete before any step)

You have already completed the **Required reading** in your agent definition (`CLAUDE.md`), you
hold the `## Technical note` and `## Setup commands` blocks the skill forwarded, and you emitted
the "Context loaded" gate. Apply every constraint from the forwarded `## Technical note`
throughout the entire planning. If you have not done that reading yet, do it now before continuing.

---

## Process

> **Mode**: Use Claude Plan Mode for planning steps.
> **Model**: `claude-opus-4-8`

### Step 0 — Set up the working branch

Before producing any artifacts, make sure the repo is on a dedicated branch so the whole
lifecycle (planning → coding → MR) stays on one branch. **Skip this step entirely when
`<project>` is `(unknown)`** — there is no repo to branch.

```bash
cd "$WORKSPACE_ROOT/<project>"
current="$(git rev-parse --abbrev-ref HEAD)"
```

- If `current` already ends in `-<id>` (issue: `feature/<slug>-<id>` / `bug/<slug>-<id>`) or
  matches `feature/<plan_slug>` (free-form), you are on the dedicated branch — continue.
- Otherwise create it:
  - **(GitLab issue)** `bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/branch/create_branch.sh <project>#<id> --type feature` — enforces the `feature/<slug>-<id>` (or `bug/...`) convention and checks out the new branch.
  - **(Free-form)** `git checkout -b feature/<plan_slug>` off the intended base.

**Base-branch caveat**: branch creation branches off the **current HEAD**, not the default
branch. If this work should start from `master`, check out `master` (or the agreed base branch)
*before* creating; if it stacks on another in-flight ticket, check out that ticket's branch
first. When unsure which base is correct, ask the user.

If the branch already exists from a previous session, `create_branch.sh` aborts — just
`git checkout` it instead.

---

### Step 1 — Capture the request

**(GitLab issue only)** Fetch the issue description with tools in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/`:

```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>
```

For a **free-form** request (`<plan_source>` = `user-prompt`), the source is `<feature_description>` from the prompt — no fetch.

Extract from the issue or the feature description:
- Goal of the work: what problem is being solved?
- Acceptance criteria or expected outcome
- Any linked issues, MRs, or references

If `<brainstorm_spec>` exists, read it first and treat it as the approved design intent; use
the issue/request here only to fill gaps and confirm scope. Do not re-litigate decisions already
settled in the spec.

If you need a tool that does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

---

### Step 2 — Read relevant documentation

Identify which modules and components are touched by this issue/request. For each relevant module:
- Scan `$WORKSPACE_ROOT/<project>/docs/` for matching `.md` files
- Check `$WORKSPACE_ROOT/<project>/README.md` for top-level architecture
- Apply the project-specific constraints from the forwarded `## Technical note` block (already in your context — do not read the must_read file)

Read all found documents. Note any build-system conventions, concurrency rules, or architectural invariants that affect the design.

---

### Step 3 — Write design document

The brainstorm spec (`_brainstorm.md`) is the approved high-level approach and replaces the
former strategy document. Do not rewrite it — build the design directly on top of it.

Write `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_design.md` covering each of the following sections:

**Components and modules**
- List every component or module to implement, with its responsibility in one sentence.

**Diagrams**
- Draw the design using Mermaid, following `$WORKSPACE_ROOT/claude_workflow/template/diagram.md`.
- Include at minimum an architectural diagram and a sequence diagram for the main flow; add a block diagram when the component breakdown needs it.
- Embed the diagrams inline in this design document as ```` ```mermaid ```` fenced blocks.

**Communication flow**
- Describe how components interact at a high level (IPC, function calls, shared state, message queues, etc.).

**Behaviors and responsibilities**
- For each component: what it owns, what it produces, what it consumes, and what invariants it must maintain.

**Build system integration**
- How new files are included in the build. Specify whether changes apply to Docker build only or both Docker and cross-build (rk3588).
- List any new `SConscript` entries, CMakeLists changes, or script modifications needed.

**Detailed design**
- Class and function signatures for all new or changed code
- Data structures and their fields
- Algorithms with enough detail to implement without ambiguity

**Error handling strategy**
- How errors are surfaced, logged, and recovered from in each component.

**Manual test strategy**
- Step-by-step instructions to verify the feature works end-to-end by hand.

**Automated test strategy**
- Unit tests: what to test, which framework and naming convention to use, which edge cases to cover.
- Integration tests: what interaction boundaries to exercise and what environment is required.

Write the state file:

```markdown
# State: <plan_slug>

## Active work
- **Project**: <project>
- **Issue/MR**: #<id>   (omit or "—" for a free-form request)
- **Type**: <plan_source>   (issue | user-prompt)
- **Phase**: Phase 1 – Planning (design written, awaiting approval)

## Completed steps
- [x] Request captured (issue fetched / prompt described)
- [x] Relevant docs read
- [x] Brainstorm spec approved
- [x] Design written
- [ ] Design approved

## Next step
Present design to user for approval.

## Key decisions
(carried from brainstorm spec)
```

**Approval required**: present the design to the user and wait for explicit approval before declaring the Planning phase complete. If the user requests changes, revise the document and re-present.

---

### Step 4 — Final state update

After design is approved, update `_state.md`:

```markdown
## Completed steps
- [x] Request captured (issue fetched / prompt described)
- [x] Relevant docs read
- [x] Brainstorm spec approved
- [x] Design written
- [x] Design approved

## Next step
Proceed to Phase 2: Planning review.
```

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_brainstorm.md` — approved high-level approach (from the brainstorming step; replaces the old strategy doc)
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_design.md` — detailed design for coding
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_state.md` — phase state (update after every approved step)
