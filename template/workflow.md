
## Workflow
Working on a Gitlab Issue includes sequential phases: Planning, Planning review, Coding, Write tests, Code quality assurance, Coding review, Create merge request

Working on a Gitlab Merge request includes a single phase: Coding Review

Format of requested Gitlab Issue or Gitlab Merge Request is according to `Gitlab Input format` section of `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`

---

## Artifact paths

Artifact filenames use a prefix derived from the work item type:

| Work item | Folder | File prefix |
|-----------|--------|-------------|
| GitLab Issue `#<id>` | `.tmp/<project>-<id>/` | `<project>-<id>_` |
| GitLab MR `!<id>` | `.tmp/<project>-mr-<id>/` | `<project>-mr-<id>_` |

All paths below use `<prefix>` as a shorthand for the appropriate prefix above.

---

## Resume after conversation compaction

Conversation compaction is unavoidable in long sessions. When Claude resumes after compaction it **must** do this before anything else:

1. Determine whether the work item is an Issue or MR and derive the correct folder/prefix (see **Artifact paths** above).
2. Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<folder>/<prefix>state.md` if it exists.
3. If no state file is found, scan `$WORKSPACE_ROOT/claude_workflow/.tmp/` for the most recently modified project folder and infer state from which files exist (see State file format below).
4. Announce to the user: "Resuming `<project>#<id>` — currently at **Phase N: <name>**, next step: <next step>."
5. Ask for confirmation before continuing: "Shall I continue from here?"

If the user provides a project/issue in their message, use that instead of scanning.

### State file

**Path**: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` (Issue)
**Path**: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_state.md` (MR)

**Claude must write/update this file** at the end of every phase and every approved step within a phase. Never skip this update — it is the only reliable recovery mechanism after compaction.

**Format**:
```markdown
# State: <project>#<id>

## Active work
- **Project**: <project>
- **Issue/MR**: #<id>
- **Type**: issue | mr
- **Phase**: <phase number and name>

## Completed steps
- [x] Phase 1 – Brainstorm spec approved
- [x] Phase 1 – Design approved
- [x] Phase 2 – Planning review passed
- [ ] Phase 3 – Coding in progress

## Next step
<One sentence describing exactly what to do next>

## Key decisions
<Bullet list of any non-obvious decisions made that affect future phases>
```

### Inferring state from files (fallback when no state file)

| Files present | Inferred state |
|---|---|
| No files | Phase 1 — start brainstorming |
| `_brainstorm.md` only | Phase 1 — brainstorm done, awaiting design |
| `_brainstorm.md` + `_design.md` | Phase 2 — planning review |
| Above + review passed noted | Phase 3 — start coding |
| Source code changes in git | Phase 4 — write tests |
| Tests written | Phase 5 — lint/QA |
| `_review.md` | Phase 6 — review done |
| `_mr.md` | Phase 8 — merge request created |

---

### Phase 1: Planning
- This phase can be invoked individually with prompt format "Planning <project>#<number>" for a GitLab issue (e.g. "Planning projectX#309"), or with a free-form slug / project name when there is no issue (e.g. "Planning fcw_alert_tuning"), describing the feature in the prompt.
- Inform user that you are entering "Planning phase"
- Planning starts with a **brainstorming step**: it delegates to the `superpowers:brainstorming` skill to turn the ticket into an approved design spec (`*_brainstorm.md`), then hands that spec to the wf-planner. Brainstorming stops after the spec is approved — it does **not** run into `writing-plans`; the wf-planner does the planning.
- Planning phase includes brainstorming the high-level approach (the brainstorm spec replaces the old strategy document) and writing the design document
- The design document embeds Mermaid diagrams (block / architectural / sequence) following `$WORKSPACE_ROOT/claude_workflow/template/diagram.md`.
- **How**: Uses `$WORKSPACE_ROOT/claude_workflow/instructions/planning.md` as the main instruction going through all steps of planning phase.
- **Resume from previous step**: Read `_state.md` first. If absent, look for existing `_brainstorm.md` and `_design.md` to determine which step to resume.
- **Input**: Gitlab Issue number or Gitlab Merge Request
- **Output**: `*_brainstorm.md`, `*_design.md`
- **State update**: Write `_state.md` after the brainstorm spec is approved, and again after design is approved.

### Phase 2: Planning review
- This phase can be invoked individually with prompt format "Planning review <project>#<number>". Example: "Planning review projectX#309"
- Inform user that you are entering "Planning Review phase"
- This phase is to look back all design documents of Gitlab Issue, review it once again, detecting conflicting points between them that may cause harm to Coding phase later
- **Confirmation required**: In case conflicts are detected, ask user for confirmation.
- **State update**: Write `_state.md` after review passes.

### Phase 3: Coding
- This phase can be invoked individually with prompt format "Coding <project>#<number>". Example: "Coding projectX#309"
- Inform user that you are entering "Coding phase"
- Coding is started **only when design document of corresponding Gitlab Issue is available**. Otherwise, run planning phase before proceeding with coding.
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/coding.md` to implement the approved design document.
- **Input**: Design document of that Gitlab Issue at `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` (use the correct prefix per **Artifact paths**). If it is not available, iterate back to planning phase to complete planning steps.
- **Output**: Source code
- **State update**: Update `_state.md` with each completed sub-task (e.g., per-file or per-component milestone).

### Phase 4: Write tests
- Inform user that you are entering "Writing test cases"
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/testing.md` as the main instruction for writing tests.
- **Input**: the code changes made at phase 3
- **Output**: Unit and integration test files
- **State update**: Write `_state.md` after tests pass.

### Phase 5: Code quality assurance
- Inform user that you are entering "Code Quality Assurance phase"
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/lint.md` as the main instruction for code quality assurance.
- **Input**: the code changes made at phase 3
- **Output**: Fixed lint warnings, errors
- **State update**: Write `_state.md` after lint is clean.

### Phase 6: Review
- This phase is to review the code changes made at phase 3 Coding
- Code changes are reviewed against the design document, coding must follow design
- Inform user that you are entering "Code Review phase"
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/review.md` as the main instruction for coding review
- **Input**: the code changes made at phase 3
- **Output**: Review document stored using the correct prefix per **Artifact paths**. Examples: `$WORKSPACE_ROOT/claude_workflow/.tmp/projectX-309/projectX-309_review.md` (Issue), `$WORKSPACE_ROOT/claude_workflow/.tmp/projectX-mr-177/projectX-mr-177_review.md` (MR)
- **State update**: Write `_state.md` with review outcome.

### Phase 8: Create Merge Request
- This phase can be invoked individually with `/wf create_mr <project>#<number>`. Example: `/wf create_mr projectX#309`
- Inform user that you are entering "Create Merge Request phase"
- `<ref>` must be a Gitlab **Issue**, not an MR. The phase turns a completed issue into a draft merge request.
- Use `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/create_mr.md` as the main instruction.
- MR title and description follow the template at `$WORKSPACE_ROOT/claude_workflow/template/gitlab_mr.md` (draft flag and labels come from its "Others" section).
- The composed body is filled from the design document and `git diff`; testing-checklist boxes are left as the template provides them (no invented test evidence).
- **Confirmation required**: creating an MR is outward-facing — show the title, target branch, draft flag, and labels, and ask before creating.
- **Input**: the code changes from Coding (committed and pushed on the working branch).
- **Output**: created draft MR; composed body stored at `<prefix>mr.md`.
- **Tool**: `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/create_merge_request.py`.
- **State update**: Write `_state.md` with the created MR iid/URL.

### Debug (utility)
- Invoke with `/wf debug <ref>` where `<ref>` is either a GitLab issue (`projectX#123`) or a free-form bug slug (`fcw_not_alert`).
- Fetches bug description from GitLab when given an issue ref; otherwise the user describes the bug in the prompt.
- The skill (sole reader of `projects/<project>_must_read.md`) forwards `# Technical note` and the `# Setup instructions` commands to the subagent, and discovers relevant module docs (e.g. `docs/managerd.md`, `tools/sim/README.md`) from keywords in the bug description.
- Spawns a `wf-debugger` subagent to search code, form hypotheses, and write a root cause analysis.
- **Temp files**: stored under `$WORKSPACE_ROOT/claude_workflow/.tmp/debug/<slug>/`
  - `<slug>_state.md` — investigation state (updated after each major step)
  - `<slug>_findings.md` — code search notes and hypothesis validation
  - `<slug>_rca.md` — root cause analysis with fix suggestion
- **State update**: the subagent writes and updates `_state.md` throughout to survive context compaction.

## Tools
Content of Gitlab Issue or Gitlab Merge Request is fetched using tools in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/`
**If new tools needed**: implement them in accordance to `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`
