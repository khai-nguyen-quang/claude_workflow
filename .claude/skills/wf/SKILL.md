---
name: wf
description: >
  Run a single Claude workflow phase for a GitLab issue or MR.
  Usage: /wf <phase> <ref>
  Phases: planning, plan-review, coding, test, lint, review, fix_review, collect, debug
  Examples: /wf review projectX#MR!177  |  /wf planning projectX#309  |  /wf fix_review projectX#MR!186  |  /wf collect projectX  |  /wf debug projectX#123  |  /wf debug fcw_not_alert
---

## Parse args

Split the args into `<phase>` (first token) and `<ref>` (everything after).

If args are empty, print this usage and stop:

```
Usage: /wf <phase> <ref>

Phases:
  planning      Phase 1 — strategy + design document        [wf-planner agent]
  plan-review   Phase 2 — review design docs for conflicts
  coding        Phase 3 — implement the approved design     [wf-coder agent]
  test          Phase 4 — write unit and integration tests
  lint          Phase 5 — fix lint / code quality violations
  review        Phase 6 — review code or a GitLab MR        [wf-reviewer agent]
  fix_review    Phase 7 — fix review comments (online MR or offline file) [wf-coder agent]
  collect       Utility — collect project context into a must-read file
  debug         Utility — investigate a bug, produce root cause analysis [wf-debugger agent]

Ref formats:
  projectX#309        GitLab issue 309 in projectX
  projectX#MR!177     GitLab MR 177 in projectX
  projectB#MR!32     GitLab MR 32 in projectB
  projectX            Project name only (for collect phase)
  projectX#123        GitLab issue for debug phase
  fcw_not_alert        Free-form bug slug (describe bug in the prompt message)
```

If the first token is **not** a recognized phase, do not stop — go to **Fallback** instead.

For the `collect` phase, `<ref>` is just a bare project name (no `#`).
`<project>` = `<ref>` directly.

## Prepare context (always, before any phase)

**Step 0 — derive workspace root**
`WORKSPACE_ROOT` is the parent directory of `claude_workflow/`. Derive it from the workspace-level `CLAUDE.md` path (the `CLAUDE.md` that contains `@claude_workflow/workflow.md`) — its directory is `WORKSPACE_ROOT`. Use it for every path below, and inject it into every agent prompt you build.

**Step 1 — derive identifiers**
From `<ref>`, extract:
- `<project>`: the part before `#`, or `<ref>` itself if there is no `#` (e.g. `projectX`)
- `<id>`: the number after `#` or `#MR!` (e.g. `309` or `177`); empty for `collect`

**Step 2 — load state file** (skip for `collect` phase)
Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` if it exists.
Store as `<state_context>`.

**Step 3 — load project context** (skip for `collect` phase — it reads source files itself)
Read `$WORKSPACE_ROOT/<project>/CLAUDE.md`.
If the file does not exist, warn the user:
> "No CLAUDE.md found for project `<project>`. The agent will lack project-specific context.
> Create `$WORKSPACE_ROOT/<project>/CLAUDE.md` with build commands, architecture, and conventions."

Store as `<project_context>`.

---

## Phase execution

Phases marked **[agent]** spawn a named subagent. All other phases run inline.

---

### [wf-planner] planning — Phase 1

Spawn an Agent with:
- **subagent_type**: `wf-planner`
- **description**: `Planning phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

---

### plan-review — Phase 2

Run inline:
1. Read all files in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/`.
2. Check for conflicts or inconsistencies between `_strategy.md` and `_design.md`.
3. Report findings. If conflicts exist, list them and ask the user for confirmation before continuing.
4. Update the state file with the review outcome.

---

### [wf-coder] coding — Phase 3

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Coding phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Design document: $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

---

### test — Phase 4

Run inline:
1. Read `$WORKSPACE_ROOT/claude_workflow/instructions/testing.md`.
2. Follow it with `<ref>` as input.

---

### lint — Phase 5

Run inline:
1. Read `$WORKSPACE_ROOT/claude_workflow/instructions/lint.md`.
2. Follow it with `<ref>` as input.

---

### [wf-reviewer] review — Phase 6

**Pre-step** (MR refs only — when `<ref>` contains `MR!`):

1. Checkout the MR branch:
   ```bash
   bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/checkout_mr_branch.sh <ref>
   ```
   Announce the branch name to the user. If checkout fails, stop and report the error.

2. Fetch the MR description:
   ```bash
   bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_mr_content.sh <ref>
   ```
   Extract the **Summary** and **Implementation Details** sections from the output. Store as `<mr_summary>` and `<mr_implementation>`.

Spawn an Agent with:
- **subagent_type**: `wf-reviewer`
- **description**: `Review phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  <if ref contains MR!>
  ## MR context
  ### Summary
  <mr_summary>

  ### Implementation Details
  <mr_implementation>
  </if>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

---

### [wf-coder] fix_review — Phase 7

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Fix review comments for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Instructions: $WORKSPACE_ROOT/claude_workflow/instructions/fix_review.md

  Read the instructions file above and follow it exactly.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

---

### [wf-debugger] debug — Bug Investigation

**Ref types:**
- GitLab issue `<project>#<id>` → fetch bug description from GitLab, project known
- Free-form slug (no `#`) → user describes bug in the prompt message, project may be inferred

**Step 1 — derive debug identifiers**

If `<ref>` contains `#`:
- `<project>` = part before `#`, `<id>` = part after `#`
- `<debug_slug>` = `<project>-<id>`
- `<bug_source>` = `gitlab-issue`

Else:
- `<debug_slug>` = `<ref>` (use as-is)
- `<bug_source>` = `user-prompt`
- Try to infer `<project>` from the slug prefix (e.g. `projectX-fcw` → `projectX`) or from the only entry in `$WORKSPACE_ROOT/claude_workflow/projects/`. If no project can be determined, set `<project>` = `(unknown)` and skip project-specific steps.

`<debug_folder>` = `$WORKSPACE_ROOT/claude_workflow/.tmp/debug/<debug_slug>/`
`<debug_prefix>` = `<debug_slug>`

**Step 2 — load debug state** (if resuming)

Read `<debug_folder>/<debug_prefix>_state.md` if it exists → `<debug_state>`.

**Step 3 — fetch bug description**

- GitLab issue: run `python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>` and capture output → `<bug_description>`.
- Free-form: `<bug_description>` = the text the user provided in this session describing the bug (everything beyond the `/wf debug <slug>` command).

**Step 4 — load project context** (skip if `<project>` = `(unknown)`)

- Read `$WORKSPACE_ROOT/<project>/CLAUDE.md` → `<project_context>`
- Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` and extract the `# Technical note` section (everything from that heading to end of file) → `<technical_note>`

If `<project>_must_read.md` does not exist, warn:
> "No `<project>_must_read.md` found. Run `/wf collect <project>` first for richer debug context."

**Step 5 — discover relevant module docs**

Scan `<bug_description>` for module/subsystem name keywords (e.g. `sim`, `simulation`, `managerd`, `streamerd`, `camerad`, `selfdrive`, `loggerd`, `ui`). For each candidate module name:
- Check `$WORKSPACE_ROOT/<project>/docs/<module>.md`
- Check `$WORKSPACE_ROOT/<project>/tools/<module>/README.md`
- Check `$WORKSPACE_ROOT/<project>/<module>/README.md`

Read all found files. Collect as `<module_docs_content>` (each entry: file path header + full content).

**Step 6 — spawn wf-debugger subagent**

Spawn an Agent with:
- **subagent_type**: `wf-debugger`
- **description**: `Debug investigation: <debug_slug>`
- **prompt**:
  ```
  ## Bug report
  Slug: <debug_slug>
  Source: <bug_source>

  <bug_description>

  ## Debug workspace
  WORKSPACE_ROOT: <WORKSPACE_ROOT>
  Debug folder: <debug_folder>
  State file: <debug_folder>/<debug_prefix>_state.md
  Findings file: <debug_folder>/<debug_prefix>_findings.md
  RCA file: <debug_folder>/<debug_prefix>_rca.md

  ## Project context
  <project_context — or "(not available)" if project unknown>

  ## Technical note
  <technical_note — or "(not available)" if must_read not found>

  ## Relevant module docs
  <module_docs_content — each file as "### <path>\n<content>"; omit section if no docs found>

  <if debug_state exists>
  ## Current investigation state (resuming)
  <debug_state>
  </if>
  ```

After the subagent finishes, report the RCA summary to the user and the path to `<debug_prefix>_rca.md`.

---

### collect — Project context collection

Run inline. `<project>` is the bare project name from `<ref>` (no `#`).

**Goal**: read all relevant documents of the project, extract operational details, and produce
`$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` following
the template at `$WORKSPACE_ROOT/claude_workflow/projects/template_must_read.md`.

The template file has two sections:
- **`# Abbreviation`** — reference table mapping placeholder names to their meaning (for extraction guidance only; do NOT copy this into the output)
- **`# Setup instructions`** — the actual output format; the output file starts here

**Steps**:

1. **Discover and read all relevant documents** for the project. Check all of these (skip missing files silently):
   - `$WORKSPACE_ROOT/<project>/CLAUDE.md`
   - `$WORKSPACE_ROOT/<project>/README.md`
   - `$WORKSPACE_ROOT/<project>/docs/SETUP.md`
   - `$WORKSPACE_ROOT/<project>/docs/SCons.md`
   - Any other `.md` files under `$WORKSPACE_ROOT/<project>/docs/` that appear relevant to building, testing, or running the project
   - Any shell scripts named `dev.sh`, `build.sh`, `Makefile`, or similar that expose build/test commands

2. **Preserve existing free-form notes** (if file already exists):
   - Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
   - Extract only the content under the `## Others` sub-section of `# Technical note` (may be empty).
   - Store as `<existing_others>`.
   - The `## Unit test framework` and `## Integration test framework` sub-sections are always re-generated — do not preserve them.

3. **Extract values** from all documents read in step 1.
   Use only information explicitly stated in the documents; write `(unknown)` for anything not found.

   **Commands** — each must be a single concise bash command (or a short command with a representative placeholder argument):

   | Placeholder | Meaning |
   |---|---|
   | `<git_clone_cmd>` | git command to clone project source code |
   | `<compile_cmd>` | bash command to compile source code |
   | `<unit_tests_all>` | bash command to run all unit tests at once |
   | `<unit_tests_file>` | bash command to run a specific unit test file |
   | `<itest_all>` | bash command to run all integration tests at once |
   | `<itest_file>` | bash command to run a particular integration test |
   | `<lint_all>` | bash command to run lint on all files |
   | `<lint_file>` | bash command to run lint on a specific file |
   | `<other_tests>` | any other test/validation commands not covered above |

   **Test framework and naming conventions** — extract descriptive text, not commands:

   | Placeholder | What to extract |
   |---|---|
   | `<unit_test_framework>` | Name of the unit test framework (e.g. Catch2, GoogleTest, pytest, unittest). Include the typical unit test file naming pattern and location (e.g. `<module>/tests/test_<name>.cc`) and any registration step needed (e.g. `env.UnitTest()` in SConscript). |
   | `<itest_framework>` | Name of the integration test framework. Include the typical integration test file naming pattern and location (e.g. `<module>/tests/test_<name>_docker.py`), and any required environment or infrastructure (e.g. mocked hardware, Docker). |

4. **Write the output file** at `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
   - The `# Setup instructions` block must **exactly follow the template** — same headings, same bash block structure, same `cd <project>` / `cd ../` lines. Substitute each command placeholder with its extracted value.
   - The `# Technical note` section must contain three sub-sections:
     - `## Unit test framework (if any)` — populate with `<unit_test_framework>`
     - `## Integration test framework (if any)` — populate with `<itest_framework>`
     - `## Others` — restore `<existing_others>` verbatim (leave empty if none existed)

5. **Report** which placeholders were filled, which were left as `(unknown)`, and
   whether existing `## Others` content was preserved.

---

## Fallback — natural language prompt

Reached when the first token is not a recognized phase. Handle the entire args string as a free-form request.

**Step 1 — extract a ref**

Scan the full args for a token that matches any known ref pattern:
- `<word>#MR!<number>` → MR ref
- `<word>#<number>` → issue ref
- `https?://.../-/(merge_requests|issues|work_items)/<number>` → full URL ref

If a ref is found, set `<ref>` to it and treat the remaining words as `<intent>`.
If no ref is found, `<ref>` is empty and the full args is `<intent>`.

**Step 2 — infer and execute**

Use `<intent>` and `<ref>` together to decide what to do. Common examples:

| Intent keywords | Action |
|---|---|
| verify, check, access, accessible, ping | Run `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/verify_access.sh` with the project from `<ref>` |
| fetch, show, describe, info, what is | Run the appropriate fetch tool (`fetch_ticket_description.py` for issues, `fetch_mr_content.sh` for MRs) |
| diff, changes | Run `fetch_mr_content.sh <ref> --diff` |
| comments, notes, discussion | Run `fetch_mr_content.sh <ref> --notes` |

Execute the inferred tool inline and display the output to the user.

**Step 3 — if intent is still unclear**

If the intent cannot be mapped to any known tool or action, explain what was understood and print the usage block from **Parse args**.

---

## After each phase

Write or update:
`$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md`

Note: the `collect` phase does not use a state file (it is stateless and idempotent).
