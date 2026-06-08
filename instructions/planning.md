# Planning instructions

## Goal

Produce a strategy document and a detailed design document for a GitLab issue. These two artifacts are the only inputs the Coding phase accepts — both must be approved by the user before work proceeds.

## Inputs (from task context)

- `<project>` — GitLab project name (e.g. `projectX`)
- `<id>` — GitLab issue number (e.g. `309`)
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)

---

## Prerequisites (complete before any step)

Derive `<project>` from the GitLab ref in your task context (the part before `#`).
Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
Apply every constraint in its `# Technical note` section throughout the entire planning.
**Do not proceed to any step below until this file is read.**

---

## Process

> **Mode**: Use Claude Plan Mode for planning steps.
> **Model**: `claude-opus-4-8`

### Step 1 — Fetch issue content

Use tools in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/` to fetch the issue description:

```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>
```

Extract from the issue:
- Goal of the work: what problem is being solved?
- Acceptance criteria or expected outcome
- Any linked issues, MRs, or references

If you need a tool that does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

---

### Step 2 — Read relevant documentation

Identify which modules and components are touched by this issue. For each relevant module:
- Scan `$WORKSPACE_ROOT/<project>/docs/` for matching `.md` files
- Check `$WORKSPACE_ROOT/<project>/README.md` for top-level architecture
- Check `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` for project-specific constraints

Read all found documents. Note any build-system conventions, concurrency rules, or architectural invariants that affect the design.

---

### Step 3 — Write strategy document

Write `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_strategy.md` covering:

- **Goal**: one-paragraph restatement of what this issue asks for
- **Approach**: at a high level, what will be done and what will not
- **Affected modules**: which existing components are touched
- **New components**: any new modules, classes, or files to be created
- **Key risks and unknowns**: anything that could block implementation

Write the state file:

```markdown
# State: <project>#<id>

## Active work
- **Project**: <project>
- **Issue/MR**: #<id>
- **Type**: issue
- **Phase**: Phase 1 – Planning (strategy written, awaiting approval)

## Completed steps
- [x] Issue content fetched
- [x] Relevant docs read
- [x] Strategy written
- [ ] Strategy approved
- [ ] Design written
- [ ] Design approved

## Next step
Present strategy to user and wait for approval before writing design document.

## Key decisions
(none yet)
```

**Approval required**: present the strategy to the user and wait for explicit approval before continuing. Do not proceed to the design document until approved.

---

### Step 4 — Write design document

Write `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` covering each of the following sections:

**Components and modules**
- List every component or module to implement, with its responsibility in one sentence.

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

Update the state file: mark "Design written" and set next step to "Present design to user for approval".

**Approval required**: present the design to the user and wait for explicit approval before declaring the Planning phase complete. If the user requests changes, revise the document and re-present.

---

### Step 5 — Final state update

After design is approved, update `_state.md`:

```markdown
## Completed steps
- [x] Issue content fetched
- [x] Relevant docs read
- [x] Strategy written
- [x] Strategy approved
- [x] Design written
- [x] Design approved

## Next step
Proceed to Phase 2: Planning review.
```

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_strategy.md` — high-level approach
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` — detailed design for coding
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` — phase state (update after every approved step)
