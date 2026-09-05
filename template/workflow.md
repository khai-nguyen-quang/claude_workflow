
## Workflow
Working on a Gitlab Issue includes sequential phases: Planning, Planning review, Coding, Write tests, Code quality assurance, Coding review, Create merge request

Working on a Gitlab Merge request includes a single phase: Coding Review

Working on a Gitlab **Epic** (`Epic#<id>`) follows a separate, epic-level workflow —
four phases ending in merged code. See `$WORKSPACE_ROOT/claude_workflow/template/epic_workflow.md`.

Working on a **research** Gitlab Issue — one whose description starts with `research::` — includes
two phases: Research, then Doc. It answers a question instead of shipping a change, so it has no
design document, no coding and no tests.

Format of requested Gitlab Issue or Gitlab Merge Request is according to `Gitlab Input format` section of `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`

---

## Global rules (all phases)

These apply to every phase, every project, and every subagent — no exceptions.

- **Commit messages are at most 5 lines.** Subject line plus at most 4 body lines. If the change
  needs more explanation than that, it belongs in the design document or the MR description.
- **Commit messages carry no Claude/Anthropic attribution.** Never add a `Co-Authored-By:` trailer
  (e.g. `Co-Authored-By: Claude <noreply@anthropic.com>`) or any similar attribution line.
- **Code comments are at most 3 lines.** Explain *why*, not *what*. Anything longer belongs in the
  design document or module docs, not inline.
- **Every phase works inside the ticket's own worktree**, never in the shared main checkout. See
  **Parallel work** below.

---

## Artifact paths

Artifact filenames use a prefix derived from the work item type:

| Work item | Folder | File prefix | Worktree |
|-----------|--------|-------------|----------|
| GitLab Issue `#<id>` | `.tmp/<project>-<id>/` | `<project>-<id>_` | `<project>-worktree/<project>-<id>` |
| GitLab MR `!<id>` | `.tmp/<project>-mr-<id>/` | `<project>-mr-<id>_` | `<project>-worktree/<project>-mr-<id>` |

All paths below use `<prefix>` as a shorthand for the appropriate prefix above. The `.tmp/` folder
name and the worktree directory name are deliberately the same `<slug>`.

---

## Parallel work — one worktree per ticket

Several tickets are normally in flight at once, each in its **own Claude session**. They must not
share a checkout: a single working tree can only be on one branch, and two sessions building in it
would overwrite each other's artifacts and test stamps.

**Layout** — worktrees are siblings of the main checkout, grouped per project:

```
workspace/
├── claude_workflow/.tmp/<slug>/       ← shared: state + design + review artifacts, per ticket
├── <project>/                         ← main checkout: stays on master, never used for ticket work
└── <project>-worktree/
    ├── <project>-387/                 ← issue 387, branch feature/<title-slug>-387
    ├── <project>-508/                 ← issue 508
    └── <project>-mr-123/              ← MR !123, branch = the MR's source branch
```

**Creation is automatic.** Every `/wf <phase> <ref>` whose `<ref>` contains `#` runs, before the
phase itself:

```bash
bash $WORKSPACE_ROOT/claude_workflow/tools/git/worktree.sh ensure <ref>
```

It is idempotent — it creates the worktree the first time and reuses it afterwards — and it
resolves the branch from the ticket: an issue gets `feature/<title-slug>-<id>` off `origin/HEAD`
(or an existing `*-<id>` branch), an MR gets its source branch. It also initialises submodules and
hard-links the gitignored assets listed in `projects/<project>_worktree.conf` (downloaded models,
vendored checkouts) so the new tree is buildable without re-downloading anything.

The resolved path becomes **`REPO_ROOT`**, is exported as `WF_REPO` for the workflow tools, is
recorded in `_state.md`, and is passed to every subagent. It replaces `$WORKSPACE_ROOT/<project>`
throughout the phases.

**Rules**

- Artifacts under `.tmp/<slug>/` are per-ticket, so parallel sessions never collide there.
- Never `git checkout`, commit, or build for a ticket in `$WORKSPACE_ROOT/<project>` — other
  sessions are using that repository.
- Never run two phases for the *same* ticket concurrently; the worktree is single-writer.
- Removing a finished ticket's worktree is manual and never automatic:
  `worktree.sh remove <ref>` (the branch is kept). `worktree.sh list` shows what exists.
- Build caches are shared across worktrees by the project's own tooling, which is intended — but
  it means a test-result cache can make a phase's tests *appear* to run when they did not. Trust
  the test summary output, not the exit code, when verifying in a fresh worktree.

### Unattended cycle

`tools/auto/run_cycle.sh` is always **stage flags + refs**. The flags say what to run, the refs
say what to run it on; there is no default stage, and a run with none prints the usage and exits.

```bash
run_cycle.sh --design 'projectX#123' 'projectX#456'
run_cycle.sh --code   'projectX#123' 'projectX#456'
run_cycle.sh --verify 'projectX#123'
run_cycle.sh --design --code --verify 'projectX#309'   # the whole issue cycle
run_cycle.sh --research --doc 'projectX#412'           # a research ticket
run_cycle.sh --review --fix_review 'projectX#MR!123' 'projectX#MR!456'
```

`--research`, `--design`, `--code`, `--verify` and `--doc` take **issue** refs and combine, always
running in that order whatever order they were typed. `--review` and `--fix_review` take **MR**
refs. The two sets cannot be mixed in one command, and `--research` cannot be combined with
`--design` — both write `<slug>_brainstorm.md`, so design's brainstorming step would overwrite what
research produced.

**Every stage takes any number of refs.** Each ref gets its own worktree and its own window and
they **all run at the same time** (`--serial` for one at a time). One ref failing does not stop
the others; the exit code reports whether any did.

Each stage runs in its own terminal window in that ticket's worktree. The window closes when the
stage's gate passes; the next stage starts a fresh session, so no context carries across stages.

Every window runs **Claude Code interactively** — the normal TUI, as if you had typed `claude`
yourself — with the phase prompt already submitted, so you can watch it, answer its prompts, and
steer it.

You **exit a session (Ctrl-D or `/exit`) when its phase is done**; the driver then runs that
phase's gate and starts the next phase in the same window by itself, or drops you back into the
*same* session with the real failure output. You never type a phase yourself — ending a session is
the only manual step, and it exists because a TUI never exits on its own.

`--headless` swaps the TUI for `claude -p`. That is not the old blind mode — the work is still
rendered in the window (assistant text, tool calls, results) — but it costs the human: Claude
never stops to ask, so brainstorming records its assumptions in the spec instead of interviewing
you, and **nobody but the model reviews the design**. It is also selected automatically when there
is no TTY. `--interactive` only exists to override a `--headless` earlier on the command line.

| Flag | Phases | Loops until |
|-------|--------|-------------|
| `--research` | `research` (brainstorming only) | `_brainstorm.md` written by this run |
| `--design` | `planning` → `plan-review` | `_plan_review.md` ends in `DESIGN OK` |
| `--code` | `coding` → `review` → `fix_review` | `_review.md` verdict is `PRODUCTION READY` |
| `--verify` | `test` → `lint` → integration tests | build, test, lint and itest gates all pass |
| `--doc` | `doc` | `_doc.md` names a `Document:` that exists in the worktree |
| `--review` / `--fix_review` | `review` and/or `fix_review` | `_review.md` verdict is `PRODUCTION READY` |

Every gate is run by the *driver*, not the model — build, test (with a check that tests really
executed), lint, itest, and a fresh verdict file. A failed gate is fed back into the same session
with the real output for up to `--max-repair` attempts; a non-approving verdict costs a round of
the stage's own loop, capped by `--max-iter`. The driver assigns each phase its session id up
front (`--session-id`), so a repair resumes that exact session without parsing anything out of it.

The terminal is auto-detected (`gnome-terminal`, `terminator`, `xterm`, `tmux`); `--no-terminal`
runs the stages inline, and `--terminal <kind>` forces one.

**Every window is named `<ref> <branch>`** — e.g. `openpilot#MR!258 feature/472-master-pipeline-alert`
— so parallel windows are told apart at a glance. Claude Code overwrites the terminal title with
its own, so the driver passes `claude --name`, which is what Claude puts there instead of
"Claude Code"; between phases, while the driver is running gates, it re-asserts the title itself.

**Single-quote MR refs.** Bare `projectX#MR!177` makes an interactive bash attempt a history
expansion on `!177` and fail with `event not found` before the script runs at all. Double quotes
do not help; single quotes do (`set +H` disables the behaviour session-wide).

`--review` alone treats the verdict as the deliverable: `NEEDS WORK` is a result, not a failure,
and the run ends with a table of every MR, its verdict, and its report path. Combined with
`--fix_review` it loops review → fix → re-review until `PRODUCTION READY` or `--max-iter` rounds.
The gate is a *fresh* report carrying a verdict — a review that did not happen fails the gate and
is retried. After a fix the code must still build, except in a repo with no `./dev.sh`, where the
driver says the gate was skipped rather than implying it passed.

The **worktrees are created one at a time before any window opens** — `worktree.sh ensure` fetches
and runs `git worktree add` in the shared main checkout, and concurrent runs race on its
`index.lock`. Once the checkouts exist the windows share nothing, so they run together safely.
Pass `--jobs $(( $(nproc) / <n> ))` when several builds will overlap.

A worktree that does **not exist yet** takes ~2 minutes to create (fetch + recursive submodule
init), so three new refs means several minutes before the first window appears. The driver streams
`worktree.sh`'s own progress and prints the elapsed time per ref — it does not pass `--quiet`,
because a silent multi-minute wait is indistinguishable from a hang.

**Research tickets.** A ticket whose description starts with `research::` answers a question
instead of shipping a change. `--research` runs the brainstorming step alone — the same
`<slug>_brainstorm.md` that `--design` produces first, and nothing after it: no design document, no
code. The phase refuses a ticket that is not marked `research::` rather than researching it anyway.
`--doc` then writes the findings up as a document under the worktree's `docs/`, committed on the
branch so it ships with the MR; it works just as well after `--design`, and refuses when neither
`_brainstorm.md` nor `_design_detailed.md` exists. The driver's gate reads the `Document:` line the phase
records and then checks that file really exists.

**`--design` automates a gate that is otherwise a human's.** Nobody reviews the brainstorm spec or
the design before coding starts — the model writes both and reviews its own work. When that review
matters, approve a design by hand and run `--code` on its own. `create_mr` is still never driven:
the cycle stops before the MR.

Phases must therefore leave objective evidence — a build that compiles, tests that run, a report
file with a verdict — not just a claim of success in the transcript.

---

## Resume after conversation compaction

Conversation compaction is unavoidable in long sessions. When Claude resumes after compaction it **must** do this before anything else:

1. Determine whether the work item is an Issue or MR and derive the correct folder/prefix (see **Artifact paths** above).
2. Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<folder>/<prefix>state.md` if it exists.
3. If no state file is found, scan `$WORKSPACE_ROOT/claude_workflow/.tmp/` for the most recently modified project folder and infer state from which files exist (see State file format below).
3b. Re-attach to the ticket's worktree: use the **Repo** field from the state file, or re-derive it with `tools/git/worktree.sh ensure <ref>` (idempotent). Export it as `WF_REPO`. Do not resume against the main checkout.
4. Announce to the user: "Resuming `<project>#<id>` — currently at **Phase N: <name>** in `<repo_root>`, next step: <next step>."
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
- **Repo**: <absolute path to this ticket's worktree>
- **Branch**: <branch checked out there>

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
| `_brainstorm.md` + `_design_{overview,detailed}.md` | Phase 2 — planning review |
| Above + review passed noted | Phase 3 — start coding |
| Source code changes in git | Phase 4 — write tests |
| Tests written | Phase 5 — lint/QA |
| `_review.md` | Phase 6 — review done |
| `_doc.md` | Doc written — nothing left but the MR |
| `_mr.md` | Phase 8 — merge request created |

---

### Research (`research::` ticket)
- Invoke with `/wf research <project>#<number>`. Example: `/wf research projectX#412`
- Inform user that you are entering "Research phase"
- Only for a GitLab issue whose **description starts with `research::`**. The phase fetches the
  issue and **stops if the marker is absent**, pointing at Planning instead — the marker is what
  separates a question from a change, and guessing removes the distinction.
- It is the brainstorming step of Planning **on its own**: it delegates to the
  `superpowers:brainstorming` skill and stops when the spec is approved. No design document, no
  wf-planner, no code.
- The spec records what was investigated, what was found, the evidence, and what is still open —
  findings and a recommendation, not an implementation plan.
- **How**: `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/research.md`
- **Input**: GitLab Issue whose description starts with `research::`
- **Output**: `*_brainstorm.md`
- **Next**: `/wf doc <ref>` writes the findings up.
- **State update**: Write `_state.md` after the spec is approved.

### Phase 1: Planning
- This phase can be invoked individually with prompt format "Planning <project>#<number>" for a GitLab issue (e.g. "Planning projectX#309"), or with a free-form slug / project name when there is no issue (e.g. "Planning fcw_alert_tuning"), describing the feature in the prompt.
- Inform user that you are entering "Planning phase"
- Planning starts with a **brainstorming step**: it delegates to the `superpowers:brainstorming` skill to turn the ticket into an approved design spec (`*_brainstorm.md`), then hands that spec to the wf-planner. Brainstorming stops after the spec is approved — it does **not** run into `writing-plans`; the wf-planner does the planning.
- Planning phase includes brainstorming the high-level approach (the brainstorm spec replaces the old strategy document) and writing the design
- **The design is two documents, not one**, structured by `$WORKSPACE_ROOT/claude_workflow/template/design_document.md`:
  - `*_design_overview.md` — purpose and scope, architecture at a glance, diagrams, primary flow, component map, key decisions, assumptions. Readable start to finish in one sitting.
  - `*_design_detailed.md` — one section per component (what it receives, what it produces, what it assumes about the rest of the system, types and signatures, error conditions, edge cases and failure modes), then `## Interfaces`, build integration, test strategy, and an end-to-end walkthrough of the main user actions.
  - Every component section names its upstream and downstream components. A component described in isolation is the failure this structure exists to prevent.
- The design overview embeds Mermaid diagrams (block / architectural / sequence) following `$WORKSPACE_ROOT/claude_workflow/template/diagram.md`, **before** any detailed section.
- **How**: Uses `$WORKSPACE_ROOT/claude_workflow/instructions/planning.md` as the main instruction going through all steps of planning phase.
- **Resume from previous step**: Read `_state.md` first. If absent, look for existing `_brainstorm.md`, `_design_overview.md` and `_design_detailed.md` to determine which step to resume.
- **Input**: Gitlab Issue number or Gitlab Merge Request
- **Output**: `*_brainstorm.md`, `*_design_overview.md`, `*_design_detailed.md`
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
- Coding is started **only when both design documents of the corresponding Gitlab Issue are available**. Otherwise, run planning phase before proceeding with coding.
- Use `$WORKSPACE_ROOT/claude_workflow/instructions/coding.md` to implement the approved design.
- **Input**: both design documents of that Gitlab Issue at `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design_overview.md` and `..._design_detailed.md` (use the correct prefix per **Artifact paths**). Read the overview first for placement, then implement from the detailed document. If they are not available, iterate back to planning phase to complete planning steps.
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

### Doc: generate documentation
- Invoke with `/wf doc <project>#<number>`. Example: `/wf doc projectX#412`
- Inform user that you are entering "Doc phase"
- Turns `*_brainstorm.md` and/or the `*_design_{overview,detailed}.md` pair into a **document in the project repository**, under
  the worktree's `docs/`, following the naming and style of the docs already there. It stops if
  neither artifact exists — this phase documents work that was done, not work that was described.
- The document addresses a reader who has never seen the ticket or this workflow: no phases, no
  `.tmp/` artifacts, no mention of Claude.
- An existing document on the same subject is **updated in place**, never duplicated.
- Commits that one file on the ticket's branch so it ships with the MR (≤5 lines, no attribution).
  It never pushes.
- **How**: `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/doc.md`
- **Input**: `*_brainstorm.md` and/or `*_design_overview.md` + `*_design_detailed.md`
- **Output**: `docs/<topic>.md` in the worktree, committed; plus `*_doc.md` whose first line is
  `Document: <path>` — what the unattended driver's gate reads before checking the file exists.
- **State update**: Write `_state.md` with the document path and the commit.

### Phase 8: Create Merge Request
- This phase can be invoked individually with `/wf create_mr <project>#<number>`. Example: `/wf create_mr projectX#309`
- Inform user that you are entering "Create Merge Request phase"
- `<ref>` must be a Gitlab **Issue**, not an MR. The phase turns a completed issue into a draft merge request.
- Use `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/create_mr.md` as the main instruction.
- MR title and description follow the template at `$WORKSPACE_ROOT/claude_workflow/template/gitlab_mr.md` (draft flag and labels come from its "Others" section).
- The composed body is filled from the design documents and `git diff`; testing-checklist boxes are left as the template provides them (no invented test evidence).
- **Confirmation required**: creating an MR is outward-facing — show the title, target branch, draft flag, and labels, and ask before creating.
- **Input**: the code changes from Coding (committed and pushed on the working branch).
- **Output**: created draft MR; composed body stored at `<prefix>mr.md`.
- **Tool**: `$WF_TOOLS/create_merge_request.py`.
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
Content of an issue, merge request or pull request is fetched using the forge tools in `$WF_TOOLS/` — `tools/gitlab/` or `tools/github/`, chosen by `tools/forge/resolve.sh`
**If new tools needed**: implement them in accordance to `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`
