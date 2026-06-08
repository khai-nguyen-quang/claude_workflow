# coding — Phase 3 [wf-coder]

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
