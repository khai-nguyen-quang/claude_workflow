# review — Phase 6 [wf-reviewer]

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
   Extract the **Summary** and **Implementation Details** sections. Store as `<mr_summary>` and `<mr_implementation>`.

Spawn an Agent with:
- **subagent_type**: `wf-reviewer`
- **description**: `Review phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Technical note
  <technical_note>

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
