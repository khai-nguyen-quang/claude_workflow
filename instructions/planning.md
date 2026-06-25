# Planning instructions

## Goal

Produce a detailed design document for a GitLab issue, building on the approved brainstorm spec. The brainstorm spec (high-level approach) and the design document are the inputs the Coding phase accepts — both must be approved by the user before work proceeds.

## Inputs (from task context)

- `<project>` — GitLab project name (e.g. `projectX`)
- `<id>` — GitLab issue number (e.g. `309`)
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)
- `<brainstorm_spec>` — `.tmp/<project>-<id>/<project>-<id>_brainstorm.md`, the design spec
  approved during the planning phase's brainstorming step. It is the approved high-level
  approach (replacing a separate strategy document) and the primary source for the design;
  the raw issue is supporting context.

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

Before producing any artifacts, make sure the repo is on the ticket's dedicated branch so
the whole ticket lifecycle (planning → coding → MR) stays on one branch.

```bash
cd "$WORKSPACE_ROOT/<project>"
current="$(git rev-parse --abbrev-ref HEAD)"
```

- If `current` already ends in `-<id>` (e.g. `feature/<slug>-<id>` or `bug/<slug>-<id>`),
  you are on the ticket branch — continue.
- Otherwise create it:
  ```bash
  bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/branch/create_branch.sh <project>#<id> --type feature
  ```
  `create_branch.sh` enforces the `feature/<slug>-<id>` (or `bug/...`) convention and
  checks out the new branch.

**Base-branch caveat**: `create_branch.sh` branches off the **current HEAD**, not the
default branch. If this ticket should start from `master`, check out `master` (or the
agreed base branch) *before* running it; if it stacks on another in-flight ticket, check
out that ticket's branch first. When unsure which base is correct, ask the user.

If the branch already exists from a previous session, `create_branch.sh` aborts — just
`git checkout` it instead.

---

### Step 1 — Fetch issue content

Use tools in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/` to fetch the issue description:

```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>
```

Extract from the issue:
- Goal of the work: what problem is being solved?
- Acceptance criteria or expected outcome
- Any linked issues, MRs, or references

If `<brainstorm_spec>` exists, read it first and treat it as the approved design intent; use
the issue here only to fill gaps and confirm scope. Do not re-litigate decisions already
settled in the spec.

If you need a tool that does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

---

### Step 2 — Read relevant documentation

Identify which modules and components are touched by this issue. For each relevant module:
- Scan `$WORKSPACE_ROOT/<project>/docs/` for matching `.md` files
- Check `$WORKSPACE_ROOT/<project>/README.md` for top-level architecture
- Apply the project-specific constraints from the forwarded `## Technical note` block (already in your context — do not read the must_read file)

Read all found documents. Note any build-system conventions, concurrency rules, or architectural invariants that affect the design.

---

### Step 3 — Write design document

The brainstorm spec (`_brainstorm.md`) is the approved high-level approach and replaces the
former strategy document. Do not rewrite it — build the design directly on top of it.

Write `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` covering each of the following sections:

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
# State: <project>#<id>

## Active work
- **Project**: <project>
- **Issue/MR**: #<id>
- **Type**: issue
- **Phase**: Phase 1 – Planning (design written, awaiting approval)

## Completed steps
- [x] Issue content fetched
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
- [x] Issue content fetched
- [x] Relevant docs read
- [x] Brainstorm spec approved
- [x] Design written
- [x] Design approved

## Next step
Proceed to Phase 2: Planning review.
```

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_brainstorm.md` — approved high-level approach (from the brainstorming step; replaces the old strategy doc)
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` — detailed design for coding
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` — phase state (update after every approved step)
