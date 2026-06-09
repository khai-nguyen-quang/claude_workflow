# fix_review — Phase 7 [wf-coder]

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Fix review comments for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Technical note
  <technical_note>

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
