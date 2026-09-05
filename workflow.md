
## Workflow
Working on a Gitlab Issue includes sequential phases: Planning, Planning review, Coding, Write tests, Code quality assurance, Coding review

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
- [x] Phase 1 – Strategy approved
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
| No files | Phase 1 — start strategy |
| `_strategy.md` only | Phase 1 — strategy done, awaiting design |
| `_strategy.md` + `_design_{overview,detailed}.md` | Phase 2 — planning review |
| Above + review passed noted | Phase 3 — start coding |
| Source code changes in git | Phase 4 — write tests |
| Tests written | Phase 5 — lint/QA |
| `_review.md` | Phase 6 — review done |

---

### Phase 1: Planning
- This phase can be invoked individually with prompt format "Planning <project>#<number>". Example: "Planning projectX#309"
- Inform user that you are entering "Planning phase"
- Planning phase includes making the strategy and the design
- **The design is two documents, not one**, structured by `$WORKSPACE_ROOT/claude_workflow/template/design_document.md`:
  - `*_design_overview.md` — purpose and scope, architecture at a glance, diagrams, primary flow, component map, key decisions, assumptions.
  - `*_design_detailed.md` — one section per component (receives / produces / assumes about the rest of the system / types and signatures / error conditions / edge cases and failure modes), then `## Interfaces`, build integration, test strategy, and an end-to-end walkthrough.
  - Every component section names its upstream and downstream components.
- **How**: Uses `$WORKSPACE_ROOT/claude_workflow/instructions/planning.md` as the main instruction going through all steps of planning phase.
- **Resume from previous step**: Read `_state.md` first. If absent, look for existing `_strategy.md`, `_design_overview.md` and `_design_detailed.md` to determine which step to resume.
- **Input**: Gitlab Issue number or Gitlab Merge Request
- **Output**: `*_strategy.md`, `*_design_overview.md`, `*_design_detailed.md`
- **State update**: Write `_state.md` after strategy is approved; update it after design is approved.

### Phase 2: Planning review
- This phase can be invoked individually with prompt format "Planning review <project>#<number>". Example: "Planning review projectX#309"
- Inform user that you are entering "Planning Review phase"
- This phase is to look back all design documents of Gitlab Issue, review it once again, detecting conflicting points between them that may cause harm to Coding phase later
- **Confirmation required**: In case conflicts are detected, ask user for confirmation.
- **State update**: Write `_state.md` after review passes.

### Phase 3: Coding
- This phase can be invoked individually with prompt format "Coding <project>#<number>". Example: "Coding projectX#309"
- Inform user that you are entering "Coding phase"
- Coding is started **only when both design documents of the corresponding Gitlab Issue are available**. Otherwise, run planning phase before proceeding with coding.
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/coding.md` to implement the approved design.
- **Input**: both design documents of that Gitlab Issue at `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design_overview.md` and `..._design_detailed.md` (use the correct prefix per **Artifact paths**). If they are not available, iterate back to planning phase to complete planning steps.
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
- Code changes are reviewed against the design documents, coding must follow design
- Inform user that you are entering "Code Review phase"
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/review.md` as the main instruction for coding review
- **Input**: the code changes made at phase 3
- **Output**: Review document stored using the correct prefix per **Artifact paths**. Examples: `$WORKSPACE_ROOT/claude_workflow/.tmp/projectX-309/projectX-309_review.md` (Issue), `$WORKSPACE_ROOT/claude_workflow/.tmp/projectX-mr-177/projectX-mr-177_review.md` (MR)
- **State update**: Write `_state.md` with review outcome.

### Debug (utility)
- Invoke with `/wf debug <ref>` where `<ref>` is either a GitLab issue (`projectX#123`) or a free-form bug slug (`fcw_not_alert`).
- Fetches bug description from GitLab when given an issue ref; otherwise the user describes the bug in the prompt.
- Loads `# Technical note` from `projects/<project>_must_read.md` and discovers relevant module docs (e.g. `docs/managerd.md`, `tools/sim/README.md`) from keywords in the bug description.
- Spawns a `wf-debugger` subagent to search code, form hypotheses, and write a root cause analysis.
- **Temp files**: stored under `$WORKSPACE_ROOT/claude_workflow/.tmp/debug/<slug>/`
  - `<slug>_state.md` — investigation state (updated after each major step)
  - `<slug>_findings.md` — code search notes and hypothesis validation
  - `<slug>_rca.md` — root cause analysis with fix suggestion
- **State update**: the subagent writes and updates `_state.md` throughout to survive context compaction.

## Tools
Content of an issue, merge request or pull request is fetched using the forge tools in `$WF_TOOLS/` — `tools/gitlab/` or `tools/github/`, chosen by `tools/forge/resolve.sh`
**If new tools needed**: implement them in accordance to `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`
