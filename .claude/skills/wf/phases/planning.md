# planning — Phase 1 [wf-planner]

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
